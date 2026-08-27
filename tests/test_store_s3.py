"""The `s3://` bundle store backend (INTEGRATION.md §5.1) — the same layout under a
key prefix. Run against moto, which intercepts botocore below the HTTP layer, so this
suite needs no network and no real credentials.
"""

from __future__ import annotations

import inspect
import json
import re
from datetime import UTC, datetime
from pathlib import Path

import pytest

import mediacore.store
from mediacore import (
    SCHEMA_VERSION,
    BundleError,
    Provenance,
    Release,
    StoreError,
    bundle_slug,
    open_store,
)

from conftest import (
    S3_TEST_BUCKET,
    S3_TEST_CREDENTIAL,
    S3_TEST_PREFIX,
    S3_TEST_REGION,
    SAMPLE_EXPORTED_AT,
    SAMPLE_RECORD_ID,
    make_media_file,
    make_release,
    write_source_files,
)

# Objects an entry is made of
ENTRY_RELEASE_KEY_SUFFIX = "/release.json"
ENTRY_MEDIA_KEY_PART = "/media/"
# A release.json claiming a schema this install does not know
FUTURE_SCHEMA_VERSION = SCHEMA_VERSION + 1

# The layout §5.1 fixes, as this test spells it
ENTRY_TIMESTAMP_DIRNAME = "20260102T030405Z"
SECOND_EXPORT_AT = datetime(2026, 3, 4, 5, 6, 7, tzinfo=UTC)
OTHER_RECORD_ID = "01M08WYYQGY1S66KY425FYCBS8"


def _entry_key_prefix(record_id: str, timestamp: str, slug: str) -> str:
    """The key prefix under which one entry's objects live."""
    return f"{S3_TEST_PREFIX}/{record_id}/{timestamp}/{slug}"


def _reexported(release: Release, exported_at: datetime) -> Release:
    """A deep copy of `release` whose `vinylcat` provenance claims a later
    `exported_at` — the recipe for a second version of the same record."""
    return release.model_copy(
        deep=True,
        update={
            "provenance": [
                provenance.model_copy(update={"exported_at": exported_at})
                for provenance in release.provenance
            ]
        },
    )


def test_open_store_accepts_an_s3_uri(s3_store_uri: str) -> None:
    """§5.1: "the ambient boto3 credential chain; mediacore takes no keys and the
    browser never sees the store" — `open_store` takes only the URI."""
    assert list(inspect.signature(open_store).parameters) == ["uri"]

    store = open_store(s3_store_uri)
    assert hasattr(store, "list")
    assert hasattr(store, "open")
    assert hasattr(store, "put")
    public_attrs = [attr for attr in dir(store) if not attr.startswith("_")]
    assert set(public_attrs) == {"list", "open", "put"}


def test_put_writes_the_documented_keys(s3_store_uri: str, tmp_path: Path) -> None:
    """§5.1: the same `<root>/<record ULID>/<exported_at>/<slug>/` layout as
    `file://`, but under a key prefix."""
    import boto3

    photo_one = b"photo-one-bytes"
    photo_two = b"photo-two-bytes"
    media_one = make_media_file(photo_one, ext="png", role="label_a")
    media_two = make_media_file(photo_two, ext="jpg", role="label_b")
    release = make_release(media=[media_one, media_two])
    files = write_source_files(
        tmp_path / "sources", {"one.png": photo_one, "two.jpg": photo_two}
    )

    store = open_store(s3_store_uri)
    store.put(release, files)

    client = boto3.client("s3", region_name=S3_TEST_REGION)
    keys = {
        obj["Key"]
        for obj in client.list_objects_v2(Bucket=S3_TEST_BUCKET).get("Contents", [])
    }

    prefix = _entry_key_prefix(SAMPLE_RECORD_ID, ENTRY_TIMESTAMP_DIRNAME, bundle_slug(release))
    expected = {
        f"{prefix}{ENTRY_RELEASE_KEY_SUFFIX}",
        f"{prefix}{ENTRY_MEDIA_KEY_PART}{media_one.sha256}.png",
        f"{prefix}{ENTRY_MEDIA_KEY_PART}{media_two.sha256}.jpg",
    }
    assert keys == expected
    assert all(not key.startswith("/") for key in keys)
    assert all("//" not in key for key in keys)
    assert all(key.startswith(f"{S3_TEST_PREFIX}/") for key in keys)


def test_prefix_forms_are_equivalent(monkeypatch: pytest.MonkeyPatch) -> None:
    """§5.1: `s3://<bucket>/<prefix>` — a bare bucket, a prefix, and a prefix with a
    trailing slash all produce the same relative layout below whatever prefix they
    name, and each store's `list()` only sees what is under its own prefix."""
    import boto3
    from moto import mock_aws

    for name in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"):
        monkeypatch.setenv(name, S3_TEST_CREDENTIAL)
    monkeypatch.setenv("AWS_DEFAULT_REGION", S3_TEST_REGION)

    with mock_aws():
        boto3.client("s3", region_name=S3_TEST_REGION).create_bucket(Bucket=S3_TEST_BUCKET)

        no_prefix_store = open_store(f"s3://{S3_TEST_BUCKET}")
        bare_store = open_store(f"s3://{S3_TEST_BUCKET}/{S3_TEST_PREFIX}")
        trailing_slash_store = open_store(f"s3://{S3_TEST_BUCKET}/{S3_TEST_PREFIX}/")

        no_prefix_entry = no_prefix_store.put(make_release(), {})
        bare_entry = bare_store.put(
            make_release(
                provenance=[
                    Provenance(
                        kind="vinylcat", id=OTHER_RECORD_ID, exported_at=SAMPLE_EXPORTED_AT
                    )
                ]
            ),
            {},
        )

        client = boto3.client("s3", region_name=S3_TEST_REGION)
        all_keys = {
            obj["Key"]
            for obj in client.list_objects_v2(Bucket=S3_TEST_BUCKET).get("Contents", [])
        }
        assert all(not key.startswith("/") for key in all_keys)
        assert all("//" not in key for key in all_keys)

        assert no_prefix_store.list() == [no_prefix_entry]
        assert bare_store.list() == [bare_entry]
        assert trailing_slash_store.list() == [bare_entry]


def test_entry_matches_the_file_backend(s3_store_uri: str, file_store_uri: str) -> None:
    """§5.1: moving from `file://` to `s3://` is configuration, not code — the two
    backends produce an equal entry but for `uri`."""
    release = make_release()

    s3_entry = open_store(s3_store_uri).put(release, {})
    file_entry = open_store(file_store_uri).put(release, {})

    s3_fields = s3_entry.model_dump(mode="json")
    file_fields = file_entry.model_dump(mode="json")
    s3_fields.pop("uri")
    file_fields.pop("uri")
    assert s3_fields == file_fields

    assert s3_entry.uri == (
        f"s3://{S3_TEST_BUCKET}/"
        f"{_entry_key_prefix(SAMPLE_RECORD_ID, ENTRY_TIMESTAMP_DIRNAME, bundle_slug(release))}"
    )


def test_open_accepts_an_entry_or_its_uri(s3_store_uri: str) -> None:
    """§5.1: `uri` is "the entry's own address (what a consumer posts back to pick
    it)" — `open` accepts either the `BundleEntry` or that `uri`."""
    store = open_store(s3_store_uri)
    release = make_release()
    entry = store.put(release, {})

    assert store.open(entry) == release
    assert store.open(entry.uri) == release

    with pytest.raises(StoreError):
        store.open(f"s3://other-bucket/{S3_TEST_PREFIX}/{SAMPLE_RECORD_ID}/x/y")

    empty_prefix = _entry_key_prefix(SAMPLE_RECORD_ID, ENTRY_TIMESTAMP_DIRNAME, "no-objects-here")
    with pytest.raises(StoreError):
        store.open(f"s3://{S3_TEST_BUCKET}/{empty_prefix}")


def test_open_verifies_by_default(s3_store_uri: str, tmp_path: Path) -> None:
    """§5.1: "`open` verifies like `read_bundle`" — hashes, audio sizes, and the
    schema-version guard below, even over `s3://`."""
    import boto3

    store = open_store(s3_store_uri)
    photo_bytes = b"photo-bytes"
    media_file = make_media_file(photo_bytes)
    release = make_release(media=[media_file])
    files = write_source_files(tmp_path / "sources", {"photo.png": photo_bytes})

    entry = store.put(release, files)

    client = boto3.client("s3", region_name=S3_TEST_REGION)
    prefix = _entry_key_prefix(SAMPLE_RECORD_ID, ENTRY_TIMESTAMP_DIRNAME, bundle_slug(release))
    key = f"{prefix}{ENTRY_MEDIA_KEY_PART}{media_file.sha256}.png"
    client.put_object(Bucket=S3_TEST_BUCKET, Key=key, Body=b"tampered-bytes")

    with pytest.raises(BundleError, match=re.escape(media_file.file)):
        store.open(entry)

    assert store.open(entry, verify=False) == release


def test_schema_version_newer_than_this_install(s3_store_uri: str) -> None:
    """§5.1: "a `schema_version` newer than the running `mediacore` is refused with
    the upgrade message" — a forward-compatibility guard, not a verification step, so
    it applies with `verify=False` too, and `list()` still returns the entry."""
    import boto3

    store = open_store(s3_store_uri)
    release = make_release()
    entry = store.put(release, {})

    client = boto3.client("s3", region_name=S3_TEST_REGION)
    prefix = _entry_key_prefix(SAMPLE_RECORD_ID, ENTRY_TIMESTAMP_DIRNAME, bundle_slug(release))
    key = f"{prefix}{ENTRY_RELEASE_KEY_SUFFIX}"
    payload = json.loads(client.get_object(Bucket=S3_TEST_BUCKET, Key=key)["Body"].read())
    payload["schema_version"] = FUTURE_SCHEMA_VERSION
    client.put_object(Bucket=S3_TEST_BUCKET, Key=key, Body=json.dumps(payload).encode())

    with pytest.raises(BundleError, match="upgrade mediacore"):
        store.open(entry)
    with pytest.raises(BundleError, match="upgrade mediacore"):
        store.open(entry, verify=False)

    entries = store.list()
    assert len(entries) == 1
    assert entries[0].schema_version == FUTURE_SCHEMA_VERSION


def test_put_refuses_to_overwrite(s3_store_uri: str) -> None:
    """§5.1: "Nothing in `mediacore` overwrites or deletes an entry" — put refuses a
    duplicate outright."""
    import boto3

    store = open_store(s3_store_uri)
    release = make_release()

    first_entry = store.put(release, {})

    client = boto3.client("s3", region_name=S3_TEST_REGION)
    prefix = _entry_key_prefix(SAMPLE_RECORD_ID, ENTRY_TIMESTAMP_DIRNAME, bundle_slug(release))
    key = f"{prefix}{ENTRY_RELEASE_KEY_SUFFIX}"
    original_bytes = client.get_object(Bucket=S3_TEST_BUCKET, Key=key)["Body"].read()

    with pytest.raises(StoreError, match=re.escape(bundle_slug(release))):
        store.put(release, {})

    assert client.get_object(Bucket=S3_TEST_BUCKET, Key=key)["Body"].read() == original_bytes
    assert store.list(all_versions=True) == [first_entry]


def test_an_entry_without_release_json_is_not_listed(s3_store_uri: str) -> None:
    """`put` uploads `release.json` last for this reason: a half-uploaded entry must
    never appear in a consumer's inbox."""
    import boto3

    client = boto3.client("s3", region_name=S3_TEST_REGION)
    prefix = _entry_key_prefix(SAMPLE_RECORD_ID, ENTRY_TIMESTAMP_DIRNAME, "incomplete-slug")
    key = f"{prefix}{ENTRY_MEDIA_KEY_PART}deadbeef.png"
    client.put_object(Bucket=S3_TEST_BUCKET, Key=key, Body=b"orphaned-media")

    store = open_store(s3_store_uri)
    assert store.list(all_versions=True) == []


def test_list_spans_pages(s3_store_uri: str, monkeypatch: pytest.MonkeyPatch) -> None:
    """A real store will exceed one page; this proves the paginator is used without
    seeding a thousand objects."""
    monkeypatch.setattr(mediacore.store, "S3_LIST_PAGE_SIZE", 1)

    store = open_store(s3_store_uri)
    record_ids = [SAMPLE_RECORD_ID, OTHER_RECORD_ID, "01M08WYYQGY1S66KY425FYCBS9"]
    times = [
        datetime(2026, 1, 1, tzinfo=UTC),
        datetime(2026, 1, 2, tzinfo=UTC),
        datetime(2026, 1, 3, tzinfo=UTC),
    ]
    entries = [
        store.put(
            make_release(
                provenance=[
                    Provenance(kind="vinylcat", id=record_id, exported_at=exported_at)
                ]
            ),
            {},
        )
        for record_id, exported_at in zip(record_ids, times, strict=True)
    ]

    listed = store.list(all_versions=True)
    assert listed == sorted(entries, key=lambda entry: entry.exported_at, reverse=True)


def test_missing_boto3_names_the_extra(
    s3_store_uri: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    """§5.1 makes boto3 optional, so the failure has to say what to install."""

    def _raise_import_error() -> None:
        raise ImportError("no module named boto3")

    monkeypatch.setattr(mediacore.store, "_import_boto3", _raise_import_error)

    with pytest.raises(StoreError, match=re.escape("mediacore[s3]")):
        open_store(s3_store_uri)


def test_versions_and_latest_per_record(s3_store_uri: str) -> None:
    """§5.1: "`list()` returns the latest per record" ("`all_versions=True` for the
    rest") — the same guarantee `test_store_file.py` pins, over `s3://`."""
    store = open_store(s3_store_uri)
    sample_release = make_release()
    other_release = make_release(
        provenance=[
            Provenance(kind="vinylcat", id=OTHER_RECORD_ID, exported_at=SAMPLE_EXPORTED_AT)
        ]
    )

    sample_first = store.put(sample_release, {})
    sample_second = store.put(_reexported(sample_release, SECOND_EXPORT_AT), {})
    other_first = store.put(other_release, {})
    other_second = store.put(_reexported(other_release, SECOND_EXPORT_AT), {})

    latest = store.list()
    assert set(latest) == {sample_second, other_second}

    all_versions = store.list(all_versions=True)
    assert all_versions == sorted(
        [sample_first, sample_second, other_first, other_second],
        key=lambda entry: entry.exported_at,
        reverse=True,
    )

    assert store.open(sample_first) == sample_release
    assert store.open(other_first) == other_release
