"""The `file://` bundle store backend (INTEGRATION.md §5.1). §5's bundle folder
generalised: a directory of bundle directories, versioned by `exported_at`, where
nothing is ever overwritten or deleted.
"""

from __future__ import annotations

import json
import re
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlsplit

import pytest

from mediacore import (
    BUNDLE_MEDIA_DIRNAME,
    BUNDLE_RELEASE_FILENAME,
    SCHEMA_VERSION,
    BundleError,
    Provenance,
    Release,
    StoreError,
    bundle_slug,
    open_store,
    read_bundle,
    write_bundle,
)

from conftest import (
    SAMPLE_EXPORTED_AT,
    SAMPLE_RECORD_ID,
    make_media_file,
    make_release,
    write_source_files,
)

# The layout §5.1 fixes, as this test spells it
ENTRY_TIMESTAMP_DIRNAME = "20260102T030405Z"
SECOND_EXPORT_AT = datetime(2026, 3, 4, 5, 6, 7, tzinfo=UTC)
SECOND_EXPORT_TIMESTAMP_DIRNAME = "20260304T050607Z"
OTHER_RECORD_ID = "01M08WYYQGY1S66KY425FYCBS8"
# A release.json claiming a schema this install does not know
FUTURE_SCHEMA_VERSION = SCHEMA_VERSION + 1

# Record ids that are not a single path segment, and the directory the first of them
# would create beside the store root if `put` joined it unchecked.
ESCAPED_DIRNAME = "escaped-record"
ESCAPING_RECORD_IDS = (f"../{ESCAPED_DIRNAME}", "nested/record", "..")
# A sibling of the store root, addressed the way an untrusted caller would reach it:
# through the root, not around it.
SIBLING_STORE_DIRNAME = "sibling-store"
# An `exported_at` written without its `Z`, as an exporter that dropped the timezone
# leaves it, and the same instant read as UTC. Later than every other export here, so
# ordering has to place it first.
NAIVE_EXPORTED_AT_TEXT = "2026-05-06T07:08:09"
NAIVE_EXPORTED_AT_AS_UTC = datetime(2026, 5, 6, 7, 8, 9, tzinfo=UTC)


def _path_for_uri(uri: str) -> Path:
    """Recover a store root or entry directory from its `file://` form."""
    return Path(urlsplit(uri).path)


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


def _rewrite_release_json(bundle_dir: Path, **overrides: object) -> None:
    """Hand-edit a stored release.json, the way a malformed or forward-dated export
    would arrive."""
    release_path = bundle_dir / BUNDLE_RELEASE_FILENAME
    payload = json.loads(release_path.read_text())
    payload.update(overrides)
    release_path.write_text(json.dumps(payload))


def test_put_writes_the_documented_layout(file_store_uri: str, tmp_path: Path) -> None:
    """§5.1: "Layout and versions. `<root>/<record ULID>/<exported_at, ISO basic>/
    <bundle>`.\" `put` creates every intermediate directory it needs, including the
    store root itself."""
    photo_one = b"photo-one-bytes"
    photo_two = b"photo-two-bytes"
    media_one = make_media_file(photo_one, ext="png", role="label_a")
    media_two = make_media_file(photo_two, ext="jpg", role="label_b")
    release = make_release(media=[media_one, media_two])
    files = write_source_files(
        tmp_path / "sources", {"one.png": photo_one, "two.jpg": photo_two}
    )

    store = open_store(file_store_uri)
    root = _path_for_uri(file_store_uri)
    root.rmdir()
    assert not root.exists()

    entry = store.put(release, files)

    bundle_dir = root / SAMPLE_RECORD_ID / ENTRY_TIMESTAMP_DIRNAME / bundle_slug(release)
    assert bundle_dir.is_dir()
    assert (bundle_dir / BUNDLE_RELEASE_FILENAME).is_file()
    assert (bundle_dir / BUNDLE_MEDIA_DIRNAME).is_dir()
    assert entry.uri == bundle_dir.as_uri()
    assert entry.record_id == SAMPLE_RECORD_ID
    assert entry.slug == bundle_slug(release)
    assert read_bundle(bundle_dir) == release


def test_list_on_a_missing_root_raises(tmp_path: Path) -> None:
    """`open_store` never touches the filesystem, but a store you are reading that is
    not there is a misconfiguration a consumer has to see."""
    missing_root = tmp_path / "does-not-exist"
    store = open_store(missing_root.as_uri())

    with pytest.raises(StoreError, match=re.escape(str(missing_root))):
        store.list()


def test_put_refuses_to_overwrite(file_store_uri: str) -> None:
    """§5.1: "Nothing in `mediacore` overwrites or deletes an entry" — put refuses a
    duplicate outright, naming the version address it will not write twice."""
    store = open_store(file_store_uri)
    release = make_release()

    first_entry = store.put(release, {})
    bundle_dir = _path_for_uri(first_entry.uri)
    original_bytes = (bundle_dir / BUNDLE_RELEASE_FILENAME).read_bytes()

    with pytest.raises(StoreError, match=re.escape(ENTRY_TIMESTAMP_DIRNAME)):
        store.put(release, {})

    assert (bundle_dir / BUNDLE_RELEASE_FILENAME).read_bytes() == original_bytes
    assert store.list(all_versions=True) == [first_entry]


@pytest.mark.parametrize("record_id", ESCAPING_RECORD_IDS)
def test_put_refuses_a_record_id_that_is_not_one_path_segment(
    file_store_uri: str, tmp_path: Path, record_id: str
) -> None:
    """`Provenance.id` is an unconstrained `str` off a possibly hand-edited
    `release.json`, and `put` joins it onto the store root: nothing in `mediacore` can
    be made to write outside the entry it is putting."""
    root = _path_for_uri(file_store_uri)
    store = open_store(file_store_uri)
    release = make_release(
        provenance=[Provenance(kind="vinylcat", id=record_id, exported_at=SAMPLE_EXPORTED_AT)]
    )

    with pytest.raises(StoreError, match="path segment"):
        store.put(release, {})

    assert list(root.iterdir()) == []
    # The traversal's target, one level above the root, is where a joined `..` lands.
    assert not (tmp_path / ESCAPED_DIRNAME).exists()
    assert {path.name for path in tmp_path.iterdir()} == {root.name}


def test_put_requires_vinylcat_provenance(file_store_uri: str) -> None:
    """§5.1: `record_id` and `exported_at` come from the provenance entry whose
    `kind == "vinylcat"` — a release carrying none cannot be addressed."""
    root = _path_for_uri(file_store_uri)
    store = open_store(file_store_uri)

    no_provenance = make_release(provenance=[])
    with pytest.raises(StoreError, match="vinylcat"):
        store.put(no_provenance, {})

    wrong_kind = make_release(
        provenance=[
            Provenance(kind="discogs", id=SAMPLE_RECORD_ID, exported_at=SAMPLE_EXPORTED_AT)
        ]
    )
    with pytest.raises(StoreError, match="vinylcat"):
        store.put(wrong_kind, {})

    assert list(root.iterdir()) == []


def test_reexport_is_a_new_version(file_store_uri: str) -> None:
    """§5.1: "A re-export is a new version beside the old one; `list()` returns the
    latest per record (`all_versions=True` for the rest)" — and nothing in `mediacore`
    overwrites or deletes an entry."""
    root = _path_for_uri(file_store_uri)
    store = open_store(file_store_uri)
    release = make_release()

    first_entry = store.put(release, {})
    second_release = _reexported(release, SECOND_EXPORT_AT)
    second_entry = store.put(second_release, {})

    record_dir = root / SAMPLE_RECORD_ID
    assert {p.name for p in record_dir.iterdir()} == {
        ENTRY_TIMESTAMP_DIRNAME,
        SECOND_EXPORT_TIMESTAMP_DIRNAME,
    }

    assert store.list() == [second_entry]
    assert store.list(all_versions=True) == [second_entry, first_entry]
    assert store.open(first_entry) == release


def test_list_returns_the_latest_per_record(file_store_uri: str) -> None:
    """§5.1: "`list()` returns the latest per record" ("`all_versions=True` for the
    rest")."""
    store = open_store(file_store_uri)
    sample_release = make_release()
    other_release = make_release(
        provenance=[
            Provenance(kind="vinylcat", id=OTHER_RECORD_ID, exported_at=SAMPLE_EXPORTED_AT)
        ]
    )

    store.put(sample_release, {})
    sample_second = store.put(_reexported(sample_release, SECOND_EXPORT_AT), {})
    store.put(other_release, {})
    other_second = store.put(_reexported(other_release, SECOND_EXPORT_AT), {})

    latest = store.list()
    assert set(latest) == {sample_second, other_second}
    assert {entry.record_id for entry in latest} == {SAMPLE_RECORD_ID, OTHER_RECORD_ID}

    assert len(store.list(all_versions=True)) == 4


def test_open_accepts_an_entry_or_its_uri(file_store_uri: str, tmp_path: Path) -> None:
    """§5.1: `uri` is "the entry's own address (what a consumer posts back to pick
    it)" — `open` accepts either the `BundleEntry` or that `uri`."""
    store = open_store(file_store_uri)
    release = make_release()
    entry = store.put(release, {})

    assert store.open(entry) == release
    assert store.open(entry.uri) == release

    outside_root = tmp_path / "elsewhere"
    outside_root.mkdir()
    with pytest.raises(StoreError):
        store.open(outside_root.as_uri())

    root = _path_for_uri(file_store_uri)
    no_bundle = root / "not-a-bundle"
    no_bundle.mkdir()
    with pytest.raises(StoreError):
        store.open(no_bundle.as_uri())


def test_open_refuses_a_uri_that_traverses_out_of_the_root(
    file_store_uri: str, tmp_path: Path
) -> None:
    """§5.1's consumer flow posts an entry `uri` back from a browser
    (`preview-from-store {entry_uri}`), so the root is a boundary an untrusted caller
    must not step over. `<root>/../<sibling>` is the form a purely lexical containment
    check accepts: it *is* prefixed by the root, and still addresses a bundle outside
    the store."""
    store = open_store(file_store_uri)
    root = _path_for_uri(file_store_uri)

    # A real, readable bundle, so the refusal can only be about containment.
    sibling = tmp_path / SIBLING_STORE_DIRNAME
    sibling_bundle = sibling / SAMPLE_RECORD_ID / ENTRY_TIMESTAMP_DIRNAME / "a-slug"
    write_bundle(make_release(), sibling_bundle, {})
    assert (sibling_bundle / BUNDLE_RELEASE_FILENAME).is_file()

    traversal = f"{root.as_uri()}/../{sibling_bundle.relative_to(tmp_path)}"
    with pytest.raises(StoreError, match=re.escape(str(root))):
        store.open(traversal)


def test_open_verifies_by_default(file_store_uri: str, tmp_path: Path) -> None:
    """§5.1: "`open` verifies like `read_bundle`" — hashes, audio sizes, and the
    schema-version guard below."""
    store = open_store(file_store_uri)
    photo_bytes = b"photo-bytes"
    media_file = make_media_file(photo_bytes)
    release = make_release(media=[media_file])
    files = write_source_files(tmp_path / "sources", {"photo.png": photo_bytes})

    entry = store.put(release, files)
    bundle_dir = _path_for_uri(entry.uri)
    (bundle_dir / media_file.file).write_bytes(b"tampered-bytes")

    with pytest.raises(BundleError, match=re.escape(media_file.file)):
        store.open(entry)

    assert store.open(entry, verify=False) == release


def test_open_refuses_a_newer_schema_version(file_store_uri: str) -> None:
    """§5.1: "a `schema_version` newer than the running `mediacore` is refused with
    the upgrade message\" — a forward-compatibility guard, not a verification step,
    so it applies with `verify=False` too."""
    store = open_store(file_store_uri)
    release = make_release()
    entry = store.put(release, {})

    bundle_dir = _path_for_uri(entry.uri)
    _rewrite_release_json(bundle_dir, schema_version=FUTURE_SCHEMA_VERSION)

    with pytest.raises(BundleError, match="upgrade mediacore"):
        store.open(entry)
    with pytest.raises(BundleError, match="upgrade mediacore"):
        store.open(entry, verify=False)


def test_list_does_not_refuse_a_newer_schema_version(file_store_uri: str) -> None:
    """§5.1: "`list` does not refuse: such an entry is listed with its
    `schema_version` so a page can say 'upgrade to import this' instead of hiding
    it"."""
    store = open_store(file_store_uri)
    release = make_release()
    entry = store.put(release, {})

    bundle_dir = _path_for_uri(entry.uri)
    _rewrite_release_json(bundle_dir, schema_version=FUTURE_SCHEMA_VERSION)

    entries = store.list()
    assert len(entries) == 1
    assert entries[0].schema_version == FUTURE_SCHEMA_VERSION


def test_list_returns_older_entries_beside_a_newer_schema_one(file_store_uri: str) -> None:
    """The listing exception §5.1 grants is per entry, not per store: an entry this
    install cannot open must not take the entries beside it out of the inbox."""
    store = open_store(file_store_uri)
    readable_entry = store.put(make_release(), {})
    future_release = make_release(
        provenance=[
            Provenance(kind="vinylcat", id=OTHER_RECORD_ID, exported_at=SECOND_EXPORT_AT)
        ]
    )
    future_entry = store.put(future_release, {})
    _rewrite_release_json(
        _path_for_uri(future_entry.uri), schema_version=FUTURE_SCHEMA_VERSION
    )

    entries = store.list()

    assert {entry.record_id for entry in entries} == {SAMPLE_RECORD_ID, OTHER_RECORD_ID}
    by_record = {entry.record_id: entry for entry in entries}
    assert by_record[SAMPLE_RECORD_ID] == readable_entry
    assert by_record[OTHER_RECORD_ID].schema_version == FUTURE_SCHEMA_VERSION
    assert store.open(readable_entry) == make_release()


def test_list_reads_a_naive_exported_at_as_utc(file_store_uri: str) -> None:
    """A `release.json` written without the `Z` yields a naive `exported_at`, and
    Python refuses to compare a naive datetime with an aware one — so one such entry
    made `list()` raise `TypeError` while sorting, an exception that is neither
    `StoreError` nor `BundleError` and lands on a consumer as an unclassified 500."""
    store = open_store(file_store_uri)
    aware_entry = store.put(make_release(), {})
    naive_release = make_release(
        provenance=[
            Provenance(
                kind="vinylcat", id=OTHER_RECORD_ID, exported_at=NAIVE_EXPORTED_AT_AS_UTC
            )
        ]
    )
    naive_entry = store.put(naive_release, {})
    _rewrite_release_json(
        _path_for_uri(naive_entry.uri),
        provenance=[
            {"kind": "vinylcat", "id": OTHER_RECORD_ID, "exported_at": NAIVE_EXPORTED_AT_TEXT}
        ],
    )

    entries = store.list(all_versions=True)

    assert [entry.record_id for entry in entries] == [OTHER_RECORD_ID, SAMPLE_RECORD_ID]
    assert entries[0].exported_at == NAIVE_EXPORTED_AT_AS_UTC
    assert entries[0].exported_at.tzinfo is not None
    assert entries[1] == aware_entry


def test_list_ignores_what_is_not_an_entry(file_store_uri: str) -> None:
    """The `<root>/<record>/<exported_at>/<slug>/` layout, robust to noise: a loose
    file, an empty record directory, and a directory at bundle depth with no
    `release.json` are not entries."""
    root = _path_for_uri(file_store_uri)
    store = open_store(file_store_uri)
    release = make_release()
    real_entry = store.put(release, {})

    (root / "loose-file.txt").write_text("not a bundle")
    (root / "empty-record").mkdir()
    incomplete = root / "incomplete-record" / SECOND_EXPORT_TIMESTAMP_DIRNAME / "not-a-slug"
    incomplete.mkdir(parents=True)
    (incomplete / BUNDLE_MEDIA_DIRNAME).mkdir()

    assert store.list(all_versions=True) == [real_entry]


def test_list_raises_on_an_unreadable_entry(file_store_uri: str) -> None:
    """An inbox that silently hides a broken export is worse than one that says so;
    the newer `schema_version` case is the only listing exception §5.1 grants."""
    root = _path_for_uri(file_store_uri)
    store = open_store(file_store_uri)

    not_json_dir = root / SAMPLE_RECORD_ID / ENTRY_TIMESTAMP_DIRNAME / "not-json-bundle"
    not_json_dir.mkdir(parents=True)
    (not_json_dir / BUNDLE_MEDIA_DIRNAME).mkdir()
    (not_json_dir / BUNDLE_RELEASE_FILENAME).write_text("not json at all {{{")

    with pytest.raises(StoreError, match=re.escape(not_json_dir.as_uri())):
        store.list()

    not_json_dir.joinpath(BUNDLE_RELEASE_FILENAME).unlink()
    (not_json_dir / BUNDLE_MEDIA_DIRNAME).rmdir()
    not_json_dir.rmdir()

    no_provenance_dir = (
        root / OTHER_RECORD_ID / ENTRY_TIMESTAMP_DIRNAME / "no-provenance-bundle"
    )
    no_provenance_dir.mkdir(parents=True)
    (no_provenance_dir / BUNDLE_MEDIA_DIRNAME).mkdir()
    release = make_release(provenance=[])
    (no_provenance_dir / BUNDLE_RELEASE_FILENAME).write_text(
        json.dumps(release.model_dump(mode="json"))
    )

    with pytest.raises(StoreError, match=re.escape(no_provenance_dir.as_uri())):
        store.list()
