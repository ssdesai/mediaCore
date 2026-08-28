"""The backend-independent half of `mediacore.store` (INTEGRATION.md §5.1): which URIs
`open_store` accepts, what a `BundleEntry` is, how a bundle's directory name is
derived, and the rule that an entry's fields are read from its `release.json` and never
parsed out of its key.
"""

from __future__ import annotations

import importlib.metadata
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.parse import urlsplit

import pytest
from pydantic import ValidationError

from mediacore import (
    BundleEntry,
    StoreError,
    bundle_slug,
    open_store,
    write_bundle,
)

from conftest import (
    SAMPLE_EXPORTED_AT,
    SAMPLE_RECORD_ID,
    make_release,
    write_source_files,
)

# The §11 record, and the slug vinylCatalogue records for it
SAXY_SLUG = "the-duke-s-combo--it-s-saxy--saae-1012"
SAXY_ARTIST = "The Duke's Combo"
SAXY_TITLE = "IT'S SAXY"
SAXY_CATALOGUE_NUMBER = "SAAE 1012"

# A store tree whose directory names disagree with its release.json
MISLEADING_RECORD_DIR = "01ZZZZZZZZZZZZZZZZZZZZZZZZ"
MISLEADING_TIMESTAMP_DIR = "19990101T000000Z"
MISLEADING_SLUG_DIR = "not-the-slug"

# `file://` hosts: another machine's disk, and this one's
FOREIGN_FILE_HOST = "example.com"
LOCAL_FILE_HOST = "localhost"

# A pressing whose every slug segment folds away under `[a-z0-9]`, and the segment the
# store names it with instead (mirrored by vinylCatalogue's slugify, INTEGRATION.md §13)
UNSLUGGABLE_ARTIST = "Кино"
UNSLUGGABLE_TITLE = "Звезда"
FALLBACK_SLUG = "release"


def test_open_store_accepts_a_file_uri(file_store_uri: str) -> None:
    """INTEGRATION.md §5.1: "three methods and nothing else"."""
    store = open_store(file_store_uri)
    assert hasattr(store, "list")
    assert hasattr(store, "open")
    assert hasattr(store, "put")
    # No other public attributes
    public_attrs = [attr for attr in dir(store) if not attr.startswith("_")]
    assert set(public_attrs) == {"list", "open", "put"}


@pytest.mark.parametrize(
    "uri",
    [
        "https://example.com/bundles",
        "ftp://example.com/bundles",
        "gs://bucket/bundles",
    ],
)
def test_open_store_rejects_an_unknown_scheme(uri: str) -> None:
    """Unknown schemes raise StoreError with the scheme in the message."""
    with pytest.raises(StoreError) as exc_info:
        open_store(uri)
    scheme = uri.split("://")[0]
    assert scheme in str(exc_info.value)


@pytest.mark.parametrize(
    "uri",
    [
        "/tmp/bundles",  # absolute path
        "bundles",  # relative path
    ],
)
def test_open_store_rejects_a_uri_with_no_scheme(uri: str) -> None:
    """URIs without a scheme raise StoreError mentioning file:// as the solution."""
    with pytest.raises(StoreError) as exc_info:
        open_store(uri)
    assert "file://" in str(exc_info.value)


def test_open_store_rejects_a_foreign_file_host(file_store_uri: str) -> None:
    """`file://example.com` is another machine's disk and raises; `file://localhost` is
    this one, so it addresses the same store an empty host does — asserted by listing
    the store the `file:///…` form just created, not by a try/except that passes
    whether or not the URI was accepted."""
    with pytest.raises(StoreError, match="host"):
        open_store(f"file://{FOREIGN_FILE_HOST}/bundles")

    root_path = urlsplit(file_store_uri).path
    localhost_store = open_store(f"file://{LOCAL_FILE_HOST}{root_path}")

    assert localhost_store.list() == []


def test_bundle_entry_reads_a_naive_exported_at_as_utc() -> None:
    """`Provenance.exported_at` is a plain `datetime`, so a `release.json` written
    without the `Z` produces a naive one. `BundleEntry` reads it as UTC, because a
    naive datetime cannot be compared with an aware one at all and `list` sorts every
    entry in the store against every other."""
    naive = BundleEntry(
        record_id=SAMPLE_RECORD_ID,
        exported_at=SAMPLE_EXPORTED_AT.replace(tzinfo=None),
        slug="test-slug",
        uri="file://store/test",
        schema_version=1,
    )

    assert naive.exported_at.tzinfo is not None
    assert naive.exported_at == SAMPLE_EXPORTED_AT
    assert naive.exported_at.utcoffset() == timedelta(0)


def test_bundle_slug_falls_back_when_every_segment_folds_away() -> None:
    """A non-Latin-script pressing with no catalogue number folds to nothing under
    `[a-z0-9]`. An empty leaf is not a directory — on `file://` it would vanish from
    the path and put the bundle a level above where `list` looks — so the slug is a
    named segment instead."""
    release = make_release(
        title=UNSLUGGABLE_TITLE,
        artists=[{"name": UNSLUGGABLE_ARTIST}],
        labels=[],
    )

    assert bundle_slug(release) == FALLBACK_SLUG


def test_bundle_entry_fields() -> None:
    """BundleEntry has five fields, is frozen, and rejects unknown keywords."""
    entry = BundleEntry(
        record_id=SAMPLE_RECORD_ID,
        exported_at=SAMPLE_EXPORTED_AT,
        slug="test-slug",
        uri="file://store/test",
        schema_version=1,
    )
    assert entry.record_id == SAMPLE_RECORD_ID
    assert entry.exported_at == SAMPLE_EXPORTED_AT
    assert entry.slug == "test-slug"
    assert entry.uri == "file://store/test"
    assert entry.schema_version == 1

    # Test frozen (immutable)
    with pytest.raises(ValidationError):
        entry.slug = "new-slug"  # type: ignore

    # Test extra="forbid"
    with pytest.raises(ValidationError):
        BundleEntry(
            record_id=SAMPLE_RECORD_ID,
            exported_at=SAMPLE_EXPORTED_AT,
            slug="test-slug",
            uri="file://store/test",
            schema_version=1,
            unknown_field="should fail",  # type: ignore
        )


def test_bundle_entry_serializes_for_a_consumer() -> None:
    """model_dump(mode="json") returns exactly five keys with ISO-8601 datetime."""
    entry = BundleEntry(
        record_id=SAMPLE_RECORD_ID,
        exported_at=SAMPLE_EXPORTED_AT,
        slug="test-slug",
        uri="file://store/test",
        schema_version=1,
    )
    dumped = entry.model_dump(mode="json")
    assert set(dumped.keys()) == {
        "record_id",
        "exported_at",
        "slug",
        "uri",
        "schema_version",
    }
    # exported_at should be ISO-8601 string
    assert isinstance(dumped["exported_at"], str)
    assert dumped["exported_at"] == "2026-01-02T03:04:05Z"


def test_bundle_slug_matches_the_vinylcat_slug() -> None:
    """bundle_slug matches the slug INTEGRATION.md §11 records for IT'S SAXY."""
    release = make_release(
        title=SAXY_TITLE,
        artists=[
            {
                "name": SAXY_ARTIST,
                "refs": {"discogs:artist": "5682050"},
            }
        ],
        labels=[
            {
                "name": "Sonora Records",
                "catalogue_number": SAXY_CATALOGUE_NUMBER,
            }
        ],
    )
    assert bundle_slug(release) == SAXY_SLUG


def test_bundle_slug_without_a_catalogue_number() -> None:
    """Without a catalogue number, slug is two-segment: <artist>--<title>."""
    # Case 1: empty labels
    release_no_labels = make_release(
        title=SAXY_TITLE,
        artists=[{"name": SAXY_ARTIST, "refs": {"discogs:artist": "5682050"}}],
        labels=[],
    )
    slug_no_labels = bundle_slug(release_no_labels)
    assert slug_no_labels == "the-duke-s-combo--it-s-saxy"

    # Case 2: label with catalogue_number=None
    release_no_catno = make_release(
        title=SAXY_TITLE,
        artists=[{"name": SAXY_ARTIST, "refs": {"discogs:artist": "5682050"}}],
        labels=[{"name": "Sonora Records", "catalogue_number": None}],
    )
    slug_no_catno = bundle_slug(release_no_catno)
    assert slug_no_catno == "the-duke-s-combo--it-s-saxy"


def test_bundle_slug_folds_accents_and_punctuation() -> None:
    """Accents and punctuation are folded to [a-z0-9-], with no leading/trailing/-."""
    release = make_release(
        title="La Vie en Rosé!!!",
        artists=[
            {
                "name": "Édith Piaf",
                "refs": {"discogs:artist": "5682050"},
            }
        ],
        labels=[{"name": "Pathé", "catalogue_number": "X Y  Z"}],
    )
    slug = bundle_slug(release)
    # Should only contain [a-z0-9-], no leading/trailing dash, and no dash runs beyond
    # the intentional "--" segment separator (SLUG_SEPARATOR)
    assert all(c in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in slug)
    assert not slug.startswith("-")
    assert not slug.endswith("-")
    assert "---" not in slug


def test_entry_fields_come_from_release_json_not_the_path(
    file_store_uri: str, tmp_path: Path
) -> None:
    """Entry fields are read from release.json, never parsed from the directory path."""
    # Create a release with known values
    release = make_release(
        title=SAXY_TITLE,
        artists=[{"name": SAXY_ARTIST, "refs": {"discogs:artist": "5682050"}}],
        labels=[
            {
                "name": "Sonora Records",
                "catalogue_number": SAXY_CATALOGUE_NUMBER,
            }
        ],
    )

    # Write it to a misleading directory structure
    store_root = Path(file_store_uri.replace("file://", ""))
    misleading_path = (
        store_root
        / MISLEADING_RECORD_DIR
        / MISLEADING_TIMESTAMP_DIR
        / MISLEADING_SLUG_DIR
    )

    # Source files live outside the destination: write_bundle refuses to overwrite a
    # non-empty directory that isn't already a bundle, so they can't be staged inside it.
    files_dir = tmp_path / "sources"
    files = write_source_files(files_dir, {})

    # Write the bundle
    write_bundle(release, misleading_path, files)

    # List and verify the entry has the correct values from release.json
    store = open_store(file_store_uri)
    entries = store.list()
    assert len(entries) > 0

    entry = entries[0]
    assert entry.record_id == SAMPLE_RECORD_ID
    assert entry.exported_at == SAMPLE_EXPORTED_AT
    assert entry.slug == SAXY_SLUG
    # uri should end with the misleading slug dir
    assert entry.uri.endswith(MISLEADING_SLUG_DIR)


def test_list_returns_newest_first(file_store_uri: str) -> None:
    """list(all_versions=True) returns entries sorted by exported_at, newest first."""
    # Create three releases with different exported_at times
    # Put them in deliberately out-of-order directory structure
    time1 = datetime(2026, 1, 1, 12, 0, 0, tzinfo=UTC)
    time2 = datetime(2026, 1, 2, 12, 0, 0, tzinfo=UTC)  # newest
    time3 = datetime(2026, 1, 3, 12, 0, 0, tzinfo=UTC)  # even newer

    store = open_store(file_store_uri)

    # Create three releases with different times
    release1 = make_release(
        title="Release 1",
        provenance=[
            {
                "kind": "vinylcat",
                "id": "01M08WYYQGY1S66KY425FYCBS7",
                "exported_at": time1,
            }
        ],
    )
    release2 = make_release(
        title="Release 2",
        provenance=[
            {
                "kind": "vinylcat",
                "id": "01M08WYYQGY1S66KY425FYCBS8",
                "exported_at": time3,
            }
        ],
    )
    release3 = make_release(
        title="Release 3",
        provenance=[
            {
                "kind": "vinylcat",
                "id": "01M08WYYQGY1S66KY425FYCBS9",
                "exported_at": time2,
            }
        ],
    )

    # Put them in a mixed order
    store.put(release1, {})
    store.put(release2, {})
    store.put(release3, {})

    # List with all_versions=True
    entries = store.list(all_versions=True)

    # Should be sorted by exported_at, newest first
    exported_times = [entry.exported_at for entry in entries]
    assert exported_times == sorted(exported_times, reverse=True)
    # Verify time3 comes first (newest)
    assert entries[0].exported_at == time3


def test_package_version_matches_distribution_metadata() -> None:
    """mediacore.__version__ must match the installed distribution metadata."""
    from mediacore import __version__

    dist_version = importlib.metadata.version("mediacore")
    assert __version__ == dist_version
