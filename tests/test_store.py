"""The bundle store (INTEGRATION.md §5.1).

Every behavioural test runs against both backends: the `file://` store and a real
`s3://` store served in-process by moto, so the s3 path is exercised by the gate
offline rather than skipped. `StoreHarness` is what makes that possible — it carries
the raw write a test needs to fake an entry the API refuses to create (a newer
`schema_version`, a misleading key, a half-uploaded bundle).

Two guards can only be tested on one backend, and are written as single-backend tests
rather than as a parametrized test that quietly asserts nothing on the other:
`test_open_refuses_an_s3_key_that_escapes_the_destination` (a POSIX directory entry
cannot be named `..`, so only an S3 key can spell the traversal) and
`test_botocore_faults_surface_as_store_errors` (there is no botocore on the file path).
"""

from __future__ import annotations

import json
import logging
import sys
import tempfile
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from typing import Any

import boto3
import pytest
from botocore.exceptions import NoCredentialsError
from moto import mock_aws

from mediacore import (
    BUNDLE_RELEASE_FILENAME,
    SCHEMA_VERSION,
    BundleEntry,
    BundleError,
    LabelRef,
    Provenance,
    Release,
    StoreError,
    Track,
    its_saxy_bundle,
    open_store,
    read_bundle,
    release_slug,
    seed_its_saxy_store,
    write_bundle,
)
from mediacore import fixtures as mediacore_fixtures
from mediacore import store as mediacore_store
from mediacore.store import (
    EXPORTED_AT_KEY_FORMAT,
    RECORD_PROVENANCE_KIND,
    SCHEMA_VERSION_FIELD,
    SLUG_FALLBACK,
    FileBundleStore,
    S3BundleStore,
)

from conftest import (
    SAMPLE_EXPORTED_AT,
    SAMPLE_RECORD_ID,
    make_audio_file,
    make_media_file,
    make_release,
    sha256_bytes,
    write_source_files,
)

# The two backends every shared test runs against.
FILE_BACKEND = "file"
S3_BACKEND = "s3"

# moto serves these in-process; no request leaves the machine and no real credential is
# read — the store itself takes none, it uses whatever the ambient chain provides.
TEST_BUCKET = "mediacore-test-bundles"
TEST_PREFIX = "bundles/releases"
TEST_AWS_REGION = "us-east-1"
FAKE_AWS_CREDENTIAL = "testing"
AWS_ENVIRONMENT_OVERRIDES = ("AWS_PROFILE", "AWS_SHARED_CREDENTIALS_FILE", "AWS_CONFIG_FILE")
# Never created by any test: the s3 half of "a store root that is not there is empty".
MISSING_BUCKET = "mediacore-test-bucket-that-was-never-created"

# Payloads for the bundle a test puts into a store.
IMAGE_BYTES = b"\x89PNG\r\n\x1a\n-placeholder-image"
AUDIO_BYTES = b"RIFF-placeholder-audio"
OTHER_IMAGE_BYTES = b"\x89PNG\r\n\x1a\n-second-image"
CORRUPT_BYTES = b"corrupted"
TRACK_POSITION = "A1"
TRACK_TITLE = "LOVE GROWS"
LABEL_NAME = "A. A. E."
CATALOGUE_NUMBER = "SAAE 1012"
PROVENANCE_KIND = RECORD_PROVENANCE_KIND
PROVENANCE_LABEL = "Test"
# A second kind of provenance (§4 names `cd-rip` and `digital` as future ones): evidence
# the store must *not* key on, recorded before the one it must.
OTHER_PROVENANCE_KIND = "cd-rip"
OTHER_PROVENANCE_ID = "01M0000000000000000000000X"
OTHER_EXPORTED_AT = SAMPLE_EXPORTED_AT - timedelta(days=30)

# Source directories are named after a digest of the export they hold, not after the
# record id: a test that puts a traversing id must not spell that traversal on disk.
SOURCE_DIR_PREFIX = "sources"
SOURCE_DIR_DIGEST_LENGTH = 12

# The slug `release_slug` derives for the release `make_bundle` builds, and the version
# segment for `SAMPLE_EXPORTED_AT` (2026-01-02T03:04:05Z).
EXPECTED_SLUG = "the-duke-s-combo--it-s-saxy--saae-1012"
EXPECTED_SLUG_WITHOUT_LABEL = "the-duke-s-combo--it-s-saxy"
EXPECTED_VERSION_SEGMENT = "20260102T030405Z"
SECOND_RECORD_ID = "01M08WYYQGY1S66KY425FYCBS8"
RE_EXPORT_OFFSET = timedelta(days=1)
# Smaller than the whole-second key granularity: a re-export this close is the same
# version, whatever else changed.
SUB_SECOND_OFFSET = timedelta(microseconds=1)
NAIVE_EXPORTED_AT = SAMPLE_EXPORTED_AT.replace(tzinfo=None)

# INTEGRATION.md §11 pins these for the committed fixture.
FIXTURE_RECORD_ID = "01M08WYYQGY1S66KY425FYCBS7"
FIXTURE_SLUG = "the-duke-s-combo--it-s-saxy--saae-1012"

# §5.1: "A BundleStore has three methods and nothing else."
STORE_METHODS = {"list", "open", "put"}

# Record ids that would walk `put` out of the store root if the key guard were absent.
# `"/tmp/escaped"` lands at an absolute path; `"../../escaped"` lands beside `tmp_path`,
# in pytest's per-run basetemp — both are checked, since neither is under `tmp_path`.
ESCAPE_TARGET_NAME = "escaped"
ESCAPING_RECORD_IDS = ("../../escaped", "/tmp/escaped")
ESCAPED_ABSOLUTE_PATH = Path("/tmp") / ESCAPE_TARGET_NAME
# A bucket key that spells a traversal out of the directory `open` is filling.
ESCAPED_FILENAME = "escaped.txt"
RELATIVE_KEY_SEGMENT = ".."
# Deep enough to leave the store root from an entry key three segments down.
ESCAPING_URI_SUFFIX = "/../../../../escaped"
# A field only a newer mediacore would write; this install's models forbid it.
FUTURE_FIELD_NAME = "a_field_from_the_future"
FUTURE_FIELD_VALUE = "written by a newer mediacore"


@dataclass
class StoreHarness:
    """A store under test, plus the two things a test needs to reach around its API."""

    store: Any
    write_raw: Callable[..., None]
    entry_uri: Callable[..., str]


@pytest.fixture
def aws_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    """Ambient credentials that are unmistakably fake, and no developer profile."""
    for name in AWS_ENVIRONMENT_OVERRIDES:
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", FAKE_AWS_CREDENTIAL)
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", FAKE_AWS_CREDENTIAL)
    monkeypatch.setenv("AWS_SESSION_TOKEN", FAKE_AWS_CREDENTIAL)
    monkeypatch.setenv("AWS_DEFAULT_REGION", TEST_AWS_REGION)


def file_harness(root: Path) -> StoreHarness:
    def write_raw(*key_parts: str, name: str, data: bytes) -> None:
        path = root.joinpath(*key_parts, name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def entry_uri(*key_parts: str) -> str:
        return root.joinpath(*key_parts).absolute().as_uri()

    return StoreHarness(open_store(root.absolute().as_uri()), write_raw, entry_uri)


def s3_harness(client: Any) -> StoreHarness:
    def write_raw(*key_parts: str, name: str, data: bytes) -> None:
        key = "/".join((TEST_PREFIX, *key_parts, name))
        client.put_object(Bucket=TEST_BUCKET, Key=key, Body=data)

    def entry_uri(*key_parts: str) -> str:
        return f"s3://{TEST_BUCKET}/{'/'.join((TEST_PREFIX, *key_parts))}"

    store = open_store(f"s3://{TEST_BUCKET}/{TEST_PREFIX}", s3_client=client)
    return StoreHarness(store, write_raw, entry_uri)


@pytest.fixture(params=[FILE_BACKEND, S3_BACKEND])
def harness(
    request: pytest.FixtureRequest, tmp_path: Path, aws_environment: None
) -> Iterator[StoreHarness]:
    if request.param == FILE_BACKEND:
        yield file_harness(tmp_path / "bundles")
        return
    with mock_aws():
        client = boto3.client("s3", region_name=TEST_AWS_REGION)
        client.create_bucket(Bucket=TEST_BUCKET)
        yield s3_harness(client)


def source_directory(tmp_path: Path, *parts: str) -> Path:
    """A per-export directory for the source files, named after a digest of `parts`.

    Never after the record id itself: a test that puts an id like `"../../escaped"` would
    otherwise write its own source files outside `tmp_path` while setting up.
    """
    digest = sha256_bytes("|".join(parts).encode("utf-8"))[:SOURCE_DIR_DIGEST_LENGTH]
    return tmp_path / f"{SOURCE_DIR_PREFIX}-{digest}"


def make_bundle(
    tmp_path: Path,
    *,
    record_id: str = SAMPLE_RECORD_ID,
    exported_at: Any = SAMPLE_EXPORTED_AT,
    with_label: bool = True,
    provenance: list[Provenance] | None = None,
) -> tuple[Release, dict[str, Path]]:
    """A release with one photo and one audio file, plus the `files` mapping `put` takes."""
    release = make_release(
        provenance=provenance
        if provenance is not None
        else [
            Provenance(
                kind=PROVENANCE_KIND,
                id=record_id,
                label=PROVENANCE_LABEL,
                exported_at=exported_at,
            )
        ],
        labels=[LabelRef(name=LABEL_NAME, catalogue_number=CATALOGUE_NUMBER)]
        if with_label
        else [],
        tracks=[Track(position=TRACK_POSITION, title=TRACK_TITLE)],
        media=[make_media_file(IMAGE_BYTES)],
        audio=[make_audio_file(AUDIO_BYTES, position=TRACK_POSITION)],
    )
    files = write_source_files(
        source_directory(tmp_path, record_id, exported_at.isoformat()),
        {"photo.png": IMAGE_BYTES, "track.wav": AUDIO_BYTES},
    )
    return release, files


def paths_under(root: Path) -> set[Path]:
    """Everything below `root`, for "and it created nothing" assertions."""
    return set(root.rglob("*"))


def valid_payload(release: Release, **overrides: Any) -> bytes:
    payload = release.model_dump(mode="json")
    payload.update(overrides)
    return json.dumps(payload).encode("utf-8")


# ── open_store: scheme dispatch ───────────────────────────────────────────────


def test_open_store_dispatches_on_scheme(tmp_path: Path, aws_environment: None) -> None:
    assert isinstance(open_store(tmp_path.absolute().as_uri()), FileBundleStore)
    with mock_aws():
        assert isinstance(open_store(f"s3://{TEST_BUCKET}/{TEST_PREFIX}"), S3BundleStore)


@pytest.mark.parametrize(
    "uri",
    ["http://example.test/bundles", "/tmp/bundles", "bundles", "ftp://host/bundles", ""],
)
def test_open_store_refuses_an_unsupported_uri(uri: str) -> None:
    with pytest.raises(StoreError):
        open_store(uri)


def test_file_store_refuses_a_remote_host() -> None:
    with pytest.raises(StoreError, match="another host"):
        open_store("file://elsewhere/bundles")


def test_file_store_accepts_a_percent_encoded_path(tmp_path: Path) -> None:
    root = tmp_path / "bundle store"
    root.mkdir()
    store = open_store(root.absolute().as_uri())
    assert "%20" in store.uri
    assert store.list() == []


@pytest.mark.parametrize("uri", ["s3://", "s3:///prefix", "s3://key:secret@bucket/prefix"])
def test_s3_store_refuses_a_malformed_uri(uri: str, aws_environment: None) -> None:
    with pytest.raises(StoreError):
        open_store(uri)


def test_s3_store_names_the_extra_when_boto3_is_missing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setitem(sys.modules, "boto3", None)
    with pytest.raises(StoreError, match=r"mediacore\[s3\]"):
        open_store(f"s3://{TEST_BUCKET}/{TEST_PREFIX}")


def test_s3_store_uses_the_ambient_credential_chain(
    tmp_path: Path, aws_environment: None
) -> None:
    """No key reaches `mediacore`: the store builds its own client from the environment."""
    release, files = make_bundle(tmp_path)
    with mock_aws():
        boto3.client("s3", region_name=TEST_AWS_REGION).create_bucket(Bucket=TEST_BUCKET)
        store = open_store(f"s3://{TEST_BUCKET}/{TEST_PREFIX}")
        entry = store.put(release, files)
        assert [listed.uri for listed in store.list()] == [entry.uri]
        assert store.open(entry) == release


# ── the interface itself ──────────────────────────────────────────────────────


def test_store_has_exactly_three_methods(harness: StoreHarness) -> None:
    """§5.1: three methods and nothing else — in particular, no delete."""
    public = {
        name
        for name in dir(harness.store)
        if not name.startswith("_") and callable(getattr(harness.store, name))
    }
    assert public == STORE_METHODS
    assert not hasattr(harness.store, "delete")
    assert not hasattr(harness.store, "remove")


# ── put / list / open round trip ──────────────────────────────────────────────


def test_put_returns_an_entry_read_from_the_release(
    harness: StoreHarness, tmp_path: Path
) -> None:
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)

    assert entry.record_id == SAMPLE_RECORD_ID
    assert entry.exported_at == SAMPLE_EXPORTED_AT
    assert entry.slug == EXPECTED_SLUG
    assert entry.schema_version == SCHEMA_VERSION
    assert entry.uri == harness.entry_uri(
        SAMPLE_RECORD_ID, EXPECTED_VERSION_SEGMENT, EXPECTED_SLUG
    )


def test_the_entry_keys_on_the_vinylcat_provenance_not_the_first_one(
    harness: StoreHarness, tmp_path: Path
) -> None:
    """§5.1: `record_id` is the `vinylcat:record` ULID. A bundle may record other evidence
    first (§4 names `cd-rip` and `digital` as future kinds); keying on `provenance[0]`
    would then key the store on the wrong export entirely."""
    release, files = make_bundle(
        tmp_path,
        provenance=[
            Provenance(
                kind=OTHER_PROVENANCE_KIND,
                id=OTHER_PROVENANCE_ID,
                label=PROVENANCE_LABEL,
                exported_at=OTHER_EXPORTED_AT,
            ),
            Provenance(
                kind=PROVENANCE_KIND,
                id=SAMPLE_RECORD_ID,
                label=PROVENANCE_LABEL,
                exported_at=SAMPLE_EXPORTED_AT,
            ),
        ],
    )
    entry = harness.store.put(release, files)

    assert entry.record_id == SAMPLE_RECORD_ID
    assert entry.exported_at == SAMPLE_EXPORTED_AT
    assert entry.uri == harness.entry_uri(
        SAMPLE_RECORD_ID, EXPECTED_VERSION_SEGMENT, EXPECTED_SLUG
    )
    assert harness.store.list() == [entry]


def test_put_refuses_a_release_with_no_vinylcat_provenance(
    harness: StoreHarness, tmp_path: Path
) -> None:
    """Without that entry the store cannot say which record the bundle is a version of,
    so there is no key to write it under."""
    release, files = make_bundle(
        tmp_path,
        provenance=[
            Provenance(
                kind=OTHER_PROVENANCE_KIND,
                id=OTHER_PROVENANCE_ID,
                label=PROVENANCE_LABEL,
                exported_at=OTHER_EXPORTED_AT,
            )
        ],
    )
    with pytest.raises(StoreError, match=RECORD_PROVENANCE_KIND):
        harness.store.put(release, files)
    assert harness.store.list(all_versions=True) == []


def test_put_uses_the_documented_key_layout(harness: StoreHarness, tmp_path: Path) -> None:
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)

    assert SAMPLE_EXPORTED_AT.strftime(EXPORTED_AT_KEY_FORMAT) == EXPECTED_VERSION_SEGMENT
    assert entry.uri.endswith(
        f"/{SAMPLE_RECORD_ID}/{EXPECTED_VERSION_SEGMENT}/{EXPECTED_SLUG}"
    )


def test_list_then_open_round_trips_the_release(harness: StoreHarness, tmp_path: Path) -> None:
    release, files = make_bundle(tmp_path)
    put_entry = harness.store.put(release, files)

    listed = harness.store.list()
    assert listed == [put_entry]
    assert harness.store.open(listed[0]) == release


def test_list_is_empty_for_a_store_with_nothing_in_it(harness: StoreHarness) -> None:
    assert harness.store.list() == []
    assert harness.store.list(all_versions=True) == []


def test_list_orders_newest_export_first(harness: StoreHarness, tmp_path: Path) -> None:
    older, older_files = make_bundle(tmp_path, record_id=SECOND_RECORD_ID)
    newer, newer_files = make_bundle(
        tmp_path, exported_at=SAMPLE_EXPORTED_AT + RE_EXPORT_OFFSET
    )
    harness.store.put(older, older_files)
    harness.store.put(newer, newer_files)

    assert [entry.record_id for entry in harness.store.list()] == [
        SAMPLE_RECORD_ID,
        SECOND_RECORD_ID,
    ]


# ── versions: a re-export is a new version beside the old one ─────────────────


def test_re_export_is_a_new_version_beside_the_old_one(
    harness: StoreHarness, tmp_path: Path
) -> None:
    first, first_files = make_bundle(tmp_path)
    second_exported_at = SAMPLE_EXPORTED_AT + RE_EXPORT_OFFSET
    second, second_files = make_bundle(tmp_path, exported_at=second_exported_at)

    first_entry = harness.store.put(first, first_files)
    second_entry = harness.store.put(second, second_files)

    assert harness.store.list() == [second_entry]
    assert set(entry.uri for entry in harness.store.list(all_versions=True)) == {
        first_entry.uri,
        second_entry.uri,
    }
    # The older version is untouched, not superseded in place.
    assert harness.store.open(first_entry) == first


def test_put_refuses_to_overwrite_an_existing_version(
    harness: StoreHarness, tmp_path: Path
) -> None:
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)

    replacement = make_release(
        provenance=release.provenance,
        labels=release.labels,
        tracks=release.tracks,
        media=[make_media_file(OTHER_IMAGE_BYTES)],
    )
    replacement_files = write_source_files(
        tmp_path / "replacement", {"other.png": OTHER_IMAGE_BYTES}
    )

    with pytest.raises(StoreError, match="refusing to overwrite"):
        harness.store.put(replacement, replacement_files)

    assert harness.store.open(entry) == release
    assert harness.store.list() == [entry]


def test_put_refuses_a_same_second_re_export_with_a_different_slug(
    harness: StoreHarness, tmp_path: Path
) -> None:
    """A version is `<record>/<timestamp>`, not `<record>/<timestamp>/<slug>`: editing the
    metadata between two exports of one second must not buy a second entry under the same
    timestamp, which `list` would then choose between by lexicographic slug."""
    first, first_files = make_bundle(tmp_path)
    first_entry = harness.store.put(first, first_files)

    # Dropping the label changes the derived slug, and nothing else.
    second, second_files = make_bundle(tmp_path, with_label=False)
    assert release_slug(second) == EXPECTED_SLUG_WITHOUT_LABEL != EXPECTED_SLUG

    with pytest.raises(StoreError, match="refusing to overwrite"):
        harness.store.put(second, second_files)
    assert harness.store.list(all_versions=True) == [first_entry]


def test_put_refuses_a_re_export_that_differs_only_in_microseconds(
    harness: StoreHarness, tmp_path: Path
) -> None:
    """The key is whole seconds, so a sub-second re-export is the same version."""
    first, first_files = make_bundle(tmp_path)
    first_entry = harness.store.put(first, first_files)
    second, second_files = make_bundle(
        tmp_path, exported_at=SAMPLE_EXPORTED_AT + SUB_SECOND_OFFSET, with_label=False
    )

    with pytest.raises(StoreError, match="refusing to overwrite"):
        harness.store.put(second, second_files)
    assert harness.store.list(all_versions=True) == [first_entry]


# ── store-level faults are StoreError on both backends ────────────────────────


def test_list_is_empty_for_a_store_root_that_does_not_exist(
    tmp_path: Path, aws_environment: None
) -> None:
    """Both backends agree: a store nobody has created yet is empty, not broken. On
    `file://` that is a missing directory, on `s3://` a missing bucket — which botocore
    reports as `NoSuchBucket` and would otherwise escape `except StoreError` entirely."""
    file_store = open_store((tmp_path / "never-created").absolute().as_uri())
    assert file_store.list() == []
    assert file_store.list(all_versions=True) == []

    with mock_aws():
        s3_store = open_store(
            f"s3://{MISSING_BUCKET}/{TEST_PREFIX}",
            s3_client=boto3.client("s3", region_name=TEST_AWS_REGION),
        )
        assert s3_store.list() == []
        assert s3_store.list(all_versions=True) == []


def test_botocore_faults_surface_as_store_errors(aws_environment: None) -> None:
    """A consumer wraps store calls in `except StoreError`; an absent or expired ambient
    credential must not sail through that handler as a botocore type it never imported."""

    class NoCredentialsClient:
        def get_paginator(self, name: str) -> Any:
            raise NoCredentialsError()

    store = open_store(
        f"s3://{TEST_BUCKET}/{TEST_PREFIX}", s3_client=NoCredentialsClient()
    )
    with pytest.raises(StoreError, match="credentials"):
        store.list()


# ── the list / open asymmetry on schema_version ───────────────────────────────


def test_list_reports_a_newer_schema_version_beside_the_entries_it_can_read(
    harness: StoreHarness, tmp_path: Path
) -> None:
    """A page must be able to say "upgrade to import this", so `list` never refuses —
    including for a bundle carrying fields this install's models forbid. The invariant
    that matters is that the too-new entry does not take the older valid ones down with
    it, so the store holds both."""
    older, older_files = make_bundle(tmp_path, record_id=SECOND_RECORD_ID)
    older_entry = harness.store.put(older, older_files)

    future, _ = make_bundle(tmp_path)
    payload = future.model_dump(mode="json")
    payload[SCHEMA_VERSION_FIELD] = SCHEMA_VERSION + 1
    payload[FUTURE_FIELD_NAME] = FUTURE_FIELD_VALUE
    harness.write_raw(
        SAMPLE_RECORD_ID,
        EXPECTED_VERSION_SEGMENT,
        EXPECTED_SLUG,
        name=BUNDLE_RELEASE_FILENAME,
        data=json.dumps(payload).encode("utf-8"),
    )

    listed = harness.store.list()
    assert {entry.record_id: entry.schema_version for entry in listed} == {
        SAMPLE_RECORD_ID: SCHEMA_VERSION + 1,
        SECOND_RECORD_ID: SCHEMA_VERSION,
    }
    assert older_entry in listed
    assert {entry.slug for entry in listed} == {EXPECTED_SLUG}


def test_open_refuses_a_newer_schema_version_with_the_upgrade_message(
    harness: StoreHarness, tmp_path: Path
) -> None:
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)
    harness.write_raw(
        SAMPLE_RECORD_ID,
        EXPECTED_VERSION_SEGMENT,
        EXPECTED_SLUG,
        name=BUNDLE_RELEASE_FILENAME,
        data=valid_payload(release, schema_version=SCHEMA_VERSION + 1),
    )

    listed = harness.store.list()
    assert [item.schema_version for item in listed] == [SCHEMA_VERSION + 1]
    with pytest.raises(BundleError, match="upgrade"):
        harness.store.open(entry)


# ── open verifies like read_bundle ────────────────────────────────────────────


def test_open_rejects_a_media_file_that_does_not_match_its_hash(
    harness: StoreHarness, tmp_path: Path
) -> None:
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)
    harness.write_raw(
        SAMPLE_RECORD_ID,
        EXPECTED_VERSION_SEGMENT,
        EXPECTED_SLUG,
        name=release.media[0].file,
        data=CORRUPT_BYTES,
    )

    with pytest.raises(BundleError, match="hash mismatch"):
        harness.store.open(entry)
    # The same entry still opens with verification off — the bundle is intact enough to
    # parse, which is exactly the distinction `verify` draws.
    assert harness.store.open(entry, verify=False) == release


def test_open_rejects_an_audio_file_of_the_wrong_size(
    harness: StoreHarness, tmp_path: Path
) -> None:
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)
    resized = AUDIO_BYTES + b"-longer"
    payload = release.model_dump(mode="json")
    payload["audio"][0]["sha256"] = sha256_bytes(resized)
    payload["audio"][0]["file"] = f"media/{sha256_bytes(resized)}.wav"
    harness.write_raw(
        SAMPLE_RECORD_ID,
        EXPECTED_VERSION_SEGMENT,
        EXPECTED_SLUG,
        name=payload["audio"][0]["file"],
        data=resized,
    )
    harness.write_raw(
        SAMPLE_RECORD_ID,
        EXPECTED_VERSION_SEGMENT,
        EXPECTED_SLUG,
        name=BUNDLE_RELEASE_FILENAME,
        data=json.dumps(payload).encode("utf-8"),
    )

    with pytest.raises(BundleError, match="size mismatch"):
        harness.store.open(entry)


# ── open(dest=...): getting the bytes out of the store ────────────────────────


def test_open_materialises_the_whole_bundle_into_dest(
    harness: StoreHarness, tmp_path: Path
) -> None:
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)
    dest = tmp_path / "materialised"

    assert harness.store.open(entry, dest=dest) == release
    assert (dest / BUNDLE_RELEASE_FILENAME).is_file()
    assert (dest / release.media[0].file).read_bytes() == IMAGE_BYTES
    assert (dest / release.audio[0].file).read_bytes() == AUDIO_BYTES
    # Reading it back with no store involved is the point: the media landed with the
    # same hashes an upload would have produced.
    assert read_bundle(dest) == release


def test_open_refuses_a_non_empty_dest(harness: StoreHarness, tmp_path: Path) -> None:
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)
    dest = tmp_path / "occupied"
    dest.mkdir()
    (dest / "keep.txt").write_text("mine")

    with pytest.raises(StoreError, match="non-empty"):
        harness.store.open(entry, dest=dest)
    assert (dest / "keep.txt").read_text() == "mine"


# ── the entry is read from release.json, never parsed out of the key ──────────


def test_entry_fields_come_from_release_json_not_from_the_key(
    harness: StoreHarness, tmp_path: Path
) -> None:
    release, _ = make_bundle(tmp_path)
    misleading_key = ("not-the-record-id", "not-a-timestamp", "not-the-slug")
    harness.write_raw(
        *misleading_key, name=BUNDLE_RELEASE_FILENAME, data=valid_payload(release)
    )

    (entry,) = harness.store.list()
    assert entry.record_id == SAMPLE_RECORD_ID
    assert entry.exported_at == SAMPLE_EXPORTED_AT
    assert entry.slug == EXPECTED_SLUG
    # Only the address is the key's business.
    assert entry.uri == harness.entry_uri(*misleading_key)


def test_a_directory_without_release_json_is_not_an_entry(
    harness: StoreHarness, tmp_path: Path
) -> None:
    """Also the half-uploaded case: `put` writes release.json last, so an interrupted
    write leaves an invisible entry rather than a partial one."""
    release, _ = make_bundle(tmp_path)
    harness.write_raw(
        SAMPLE_RECORD_ID,
        EXPECTED_VERSION_SEGMENT,
        EXPECTED_SLUG,
        name=release.media[0].file,
        data=IMAGE_BYTES,
    )
    assert harness.store.list() == []
    assert harness.store.list(all_versions=True) == []


@pytest.mark.parametrize(
    ("payload", "logged"),
    [
        (b"{not json", "not valid JSON"),
        (b"[]", "not a JSON object"),
        (b'{"schema_version": 1}', "provenance"),
        (
            b'{"provenance": [{"kind": "vinylcat", "id": "x", '
            b'"exported_at": "2026-01-02T03:04:05Z"}]}',
            "schema_version",
        ),
        (b'{"schema_version": 1, "provenance": []}', "provenance"),
        (
            b'{"schema_version": 1, "provenance": [{"kind": "cd-rip", "id": "x", '
            b'"exported_at": "2026-01-02T03:04:05Z"}]}',
            "vinylcat",
        ),
        (
            b'{"schema_version": 1, "provenance": [{"kind": "vinylcat", '
            b'"exported_at": "2026-01-02T03:04:05Z"}]}',
            "id",
        ),
        (b'{"schema_version": 1, "provenance": [{"kind": "vinylcat", "id": "x"}]}', "exported_at"),
        (
            b'{"schema_version": 1, "provenance": [{"kind": "vinylcat", "id": "x", '
            b'"exported_at": "nope"}]}',
            "ISO 8601",
        ),
    ],
)
def test_a_malformed_entry_is_logged_and_left_out_of_the_listing(
    harness: StoreHarness, caplog: pytest.LogCaptureFixture, payload: bytes, logged: str
) -> None:
    """`list` never fails on one entry's account (§5.1) — the fault goes to the
    `mediacore.store` logger with the entry's own URI, and the listing goes on."""
    harness.write_raw(
        SAMPLE_RECORD_ID,
        EXPECTED_VERSION_SEGMENT,
        EXPECTED_SLUG,
        name=BUNDLE_RELEASE_FILENAME,
        data=payload,
    )
    with caplog.at_level(logging.WARNING, logger=mediacore_store.__name__):
        assert harness.store.list() == []
        assert harness.store.list(all_versions=True) == []

    assert logged in caplog.text
    assert SAMPLE_RECORD_ID in caplog.text


def test_a_corrupt_entry_does_not_hide_the_valid_ones(
    harness: StoreHarness, caplog: pytest.LogCaptureFixture, tmp_path: Path
) -> None:
    release, files = make_bundle(tmp_path, record_id=SECOND_RECORD_ID)
    entry = harness.store.put(release, files)
    harness.write_raw(
        SAMPLE_RECORD_ID,
        EXPECTED_VERSION_SEGMENT,
        EXPECTED_SLUG,
        name=BUNDLE_RELEASE_FILENAME,
        data=CORRUPT_BYTES,
    )

    with caplog.at_level(logging.WARNING, logger=mediacore_store.__name__):
        assert harness.store.list() == [entry]

    assert SAMPLE_RECORD_ID in caplog.text
    assert harness.store.open(entry) == release


# ── entry URIs are untrusted input ────────────────────────────────────────────


def test_open_refuses_an_entry_from_another_store(
    harness: StoreHarness, tmp_path: Path
) -> None:
    """A consumer posts `entry.uri` back from a browser (§5.1 preview-from-store), so a
    store only ever opens its own entries."""
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)
    elsewhere = tmp_path / "elsewhere" / SAMPLE_RECORD_ID / EXPECTED_VERSION_SEGMENT
    elsewhere.mkdir(parents=True)

    foreign = entry.model_copy(update={"uri": (elsewhere / EXPECTED_SLUG).as_uri()})
    with pytest.raises(StoreError, match="is not in the store"):
        harness.store.open(foreign)


def test_open_refuses_a_uri_that_is_not_an_entry_key(
    harness: StoreHarness, tmp_path: Path
) -> None:
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)

    too_shallow = entry.model_copy(update={"uri": entry.uri.rsplit("/", 1)[0]})
    with pytest.raises(StoreError, match="not a store entry key"):
        harness.store.open(too_shallow)


def test_open_refuses_an_entry_that_is_not_there(harness: StoreHarness) -> None:
    missing = BundleEntry(
        record_id=SAMPLE_RECORD_ID,
        exported_at=SAMPLE_EXPORTED_AT,
        slug=EXPECTED_SLUG,
        uri=harness.entry_uri(SAMPLE_RECORD_ID, EXPECTED_VERSION_SEGMENT, EXPECTED_SLUG),
        schema_version=SCHEMA_VERSION,
    )
    with pytest.raises(StoreError, match="no such entry"):
        harness.store.open(missing)


def test_open_accepts_the_entry_uri_a_browser_posts_back(
    harness: StoreHarness, tmp_path: Path
) -> None:
    """§5.1's `preview-from-store` posts `{entry_uri}`, so the server holds the string and
    not the `BundleEntry` — `open` takes either."""
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)
    dest = tmp_path / "from-a-uri"

    assert harness.store.open(entry.uri) == release
    assert harness.store.open(entry.uri, dest=dest) == release
    assert (dest / BUNDLE_RELEASE_FILENAME).is_file()


@pytest.mark.parametrize("bad", ["", "   ", "not a uri", "http://example.test/bundles"])
def test_open_refuses_an_entry_uri_string_that_is_not_this_store(
    harness: StoreHarness, tmp_path: Path, bad: str
) -> None:
    release, files = make_bundle(tmp_path)
    harness.store.put(release, files)
    with pytest.raises(StoreError):
        harness.store.open(bad)


def test_open_refuses_an_entry_uri_string_that_escapes_the_root(
    harness: StoreHarness, tmp_path: Path
) -> None:
    """The string is validated exactly as an entry's `uri` is: a traversal appended to a
    real entry key still has to resolve to one entry key under this store's own root."""
    release, files = make_bundle(tmp_path)
    entry = harness.store.put(release, files)

    with pytest.raises(StoreError):
        harness.store.open(entry.uri + ESCAPING_URI_SUFFIX)
    with pytest.raises(StoreError, match="not a store entry key"):
        harness.store.open(
            f"{entry.uri.rsplit('/', 1)[0]}/{RELATIVE_KEY_SEGMENT}/{EXPECTED_SLUG}"
        )


# ── nothing is ever written outside the entry it addresses ────────────────────


@pytest.mark.parametrize("record_id", ESCAPING_RECORD_IDS)
def test_put_refuses_a_record_id_that_is_not_one_key_segment(
    harness: StoreHarness, tmp_path: Path, record_id: str
) -> None:
    """The record id is the one key segment that reaches `put` out of `release.json`
    unfiltered, and `Provenance.id` is an unconstrained `str`. `Path.joinpath` silently
    leaves the root on an absolute or `..` segment, and §5.1's import path `put`s bundles
    that arrived as browser uploads."""
    release, files = make_bundle(tmp_path, record_id=record_id)
    before = paths_under(tmp_path)

    with pytest.raises(StoreError, match="single key segment"):
        harness.store.put(release, files)

    assert harness.store.list(all_versions=True) == []
    assert paths_under(tmp_path) == before
    assert not ESCAPED_ABSOLUTE_PATH.exists()
    assert not (tmp_path.parent / ESCAPE_TARGET_NAME).exists()


def test_open_refuses_an_s3_key_that_escapes_the_destination(
    tmp_path: Path, aws_environment: None
) -> None:
    """Object keys come from the bucket, not from `mediacore`, so a key spelling `..` must
    never put bytes outside the directory `open` is filling. s3 only: a `file://` entry is
    a directory, and a directory entry cannot be named `..`."""
    release, files = make_bundle(tmp_path)
    with mock_aws():
        client = boto3.client("s3", region_name=TEST_AWS_REGION)
        client.create_bucket(Bucket=TEST_BUCKET)
        store = open_store(f"s3://{TEST_BUCKET}/{TEST_PREFIX}", s3_client=client)
        entry = store.put(release, files)
        client.put_object(
            Bucket=TEST_BUCKET,
            Key="/".join(
                (
                    TEST_PREFIX,
                    SAMPLE_RECORD_ID,
                    EXPECTED_VERSION_SEGMENT,
                    EXPECTED_SLUG,
                    RELATIVE_KEY_SEGMENT,
                    ESCAPED_FILENAME,
                )
            ),
            Body=CORRUPT_BYTES,
        )

        with pytest.raises(StoreError, match="escapes its destination"):
            store.open(entry)

    # `open` without `dest` downloads into a TemporaryDirectory; the escaping key aimed
    # one level above it, which is the system temp directory itself.
    assert not (Path(tempfile.gettempdir()) / ESCAPED_FILENAME).exists()


# ── slugs ─────────────────────────────────────────────────────────────────────


def test_release_slug_is_artist_title_catalogue_number(tmp_path: Path) -> None:
    release, _ = make_bundle(tmp_path)
    assert release_slug(release) == EXPECTED_SLUG


def test_release_slug_skips_a_missing_segment(tmp_path: Path) -> None:
    release, _ = make_bundle(tmp_path, with_label=False)
    assert release_slug(release) == "the-duke-s-combo--it-s-saxy"


def test_release_slug_folds_accents_to_their_base_letters() -> None:
    release = make_release(title="Café Solo", artists=[{"name": "Ángel"}])
    assert release_slug(release) == "angel--cafe-solo"


def test_release_slug_falls_back_when_nothing_survives_the_fold() -> None:
    release = make_release(title="!!!", artists=[{"name": "???"}])
    assert release_slug(release) == SLUG_FALLBACK


# ── the fixture seeded into a file:// store (§5.1, "Fixture") ─────────────────


def test_seed_its_saxy_store_puts_the_fixture_bundle(tmp_path: Path) -> None:
    store_uri = (tmp_path / "dev-store").absolute().as_uri()
    entry = seed_its_saxy_store(store_uri)

    assert entry.record_id == FIXTURE_RECORD_ID
    assert entry.slug == FIXTURE_SLUG
    assert entry.schema_version == SCHEMA_VERSION

    store = open_store(store_uri)
    assert store.list() == [entry]
    assert store.open(entry) == read_bundle(its_saxy_bundle())


def test_seed_its_saxy_store_is_idempotent(tmp_path: Path) -> None:
    store_uri = (tmp_path / "dev-store").absolute().as_uri()
    first = seed_its_saxy_store(store_uri)
    second = seed_its_saxy_store(store_uri)

    assert second == first
    assert open_store(store_uri).list(all_versions=True) == [first]


def test_seed_its_saxy_store_is_idempotent_for_a_naive_exported_at(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """`Provenance.exported_at` is a plain `datetime` and need not carry a timezone, while
    a `BundleEntry`'s always does. Comparing the two datetimes would make the seed miss its
    own entry and call `put`, which refuses to overwrite — so it compares version keys."""
    release, files = make_bundle(tmp_path, exported_at=NAIVE_EXPORTED_AT)
    assert release.provenance[0].exported_at.tzinfo is None
    bundle = write_bundle(release, tmp_path / "naive-bundle", files)
    monkeypatch.setattr(mediacore_fixtures, "its_saxy_bundle", lambda: bundle)

    store_uri = (tmp_path / "dev-store").absolute().as_uri()
    first = seed_its_saxy_store(store_uri)
    second = seed_its_saxy_store(store_uri)

    assert second == first
    assert first.exported_at == SAMPLE_EXPORTED_AT
    assert open_store(store_uri).list(all_versions=True) == [first]
