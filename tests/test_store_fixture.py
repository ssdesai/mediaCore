"""Acceptance test for the bundle store (INTEGRATION.md §5.1). Seeds the committed
IT'S SAXY bundle into a store and drives the whole §5.1 story through the public API —
put, list, open, re-export, seeding — against both backends, because §5.1's claim is
that the local→hosted move is configuration, not code.
"""

from __future__ import annotations

import re
from datetime import UTC, datetime, timedelta

import pytest

from mediacore import (
    BundleStore,
    Release,
    StoreError,
    StoreNotFound,
    bundle_slug,
    open_store,
    seed_its_saxy_store,
)
from mediacore.store import VINYLCAT_PROVENANCE_KIND

from conftest import its_saxy_source

# IT'S SAXY, as INTEGRATION.md §11 records it
SAXY_RECORD_ID = "01M08WYYQGY1S66KY425FYCBS7"
SAXY_EXPORTED_AT = datetime(2026, 8, 25, tzinfo=UTC)
SAXY_SLUG = "the-duke-s-combo--it-s-saxy--saae-1012"
SAXY_TITLE = "IT'S SAXY"
SAXY_SCHEMA_VERSION = 1
SAXY_MEDIA_COUNT = 4
SAXY_AUDIO_COUNT = 12
# A second export of the same record, one day later
SECOND_EXPORT_AT = datetime(2026, 8, 26, tzinfo=UTC)
# A re-export inside the same second: the layout formats `exported_at` to seconds, so
# this is the *same* version address however the metadata differs.
SAME_SECOND_EXPORT_AT = SAXY_EXPORTED_AT + timedelta(microseconds=1)
RETITLED_TITLE = "IT'S SAXY (Remastered)"

# Addresses that are inside a store's namespace but are not entries
FOREIGN_URI = "https://example.com/bundles"
UNUSED_TIMESTAMP_DIRNAME = "20990101T000000Z"

# Record ids that are not a single path segment (`Provenance.id` is an unconstrained
# `str` off a possibly hand-edited release.json)
ESCAPING_RECORD_IDS = ("../escaped-record", "nested/record", "..")

# A pressing whose artist and title fold to nothing under `[a-z0-9]` and which carries
# no catalogue number, and the segment the store names it with instead
UNSLUGGABLE_ARTIST = "Кино"
UNSLUGGABLE_TITLE = "Звезда"
FALLBACK_SLUG = "release"


def test_put_lists_and_opens_the_fixture(store_uri: str) -> None:
    """§5.1: `put(release, files) -> BundleEntry`; `list()` returns the stored entries;
    `open(entry) -> Release` returns the bundle back out."""
    release, files = its_saxy_source()
    assert release.title == SAXY_TITLE
    store = open_store(store_uri)

    put_entry = store.put(release, files)

    entries = store.list()
    assert len(entries) == 1
    entry = entries[0]
    assert entry == put_entry
    assert entry.record_id == SAXY_RECORD_ID
    assert entry.exported_at == SAXY_EXPORTED_AT
    assert entry.slug == SAXY_SLUG
    assert entry.schema_version == SAXY_SCHEMA_VERSION

    opened = store.open(entry)
    assert opened.model_dump(mode="json") == release.model_dump(mode="json")
    assert len(opened.media) == SAXY_MEDIA_COUNT
    assert len(opened.audio) == SAXY_AUDIO_COUNT


def test_entry_uri_addresses_the_entry(store_uri: str) -> None:
    """§5.1: entries are URI-addressed — `entry.uri` is the handle a consumer posts
    back, and `open` accepts either the entry or its `uri` (WP7c/7d's `entry_uri`)."""
    release, files = its_saxy_source()
    store = open_store(store_uri)

    entry = store.put(release, files)

    assert entry.uri.startswith(store_uri)
    assert SAXY_RECORD_ID in entry.uri
    assert store.open(entry.uri).model_dump(mode="json") == store.open(entry).model_dump(
        mode="json"
    )


def test_both_backends_produce_the_same_entry(file_store_uri: str, s3_store_uri: str) -> None:
    """§5.1: moving from `file://` to `s3://` is configuration, not code — both
    backends must produce an equivalent entry (everything but `uri`) for the same
    bundle, and both must open back to the same `Release`."""
    release, files = its_saxy_source()

    file_entry = open_store(file_store_uri).put(release, files)
    s3_entry = open_store(s3_store_uri).put(release, files)

    file_fields = file_entry.model_dump(mode="json")
    s3_fields = s3_entry.model_dump(mode="json")
    file_fields.pop("uri")
    s3_fields.pop("uri")
    assert file_fields == s3_fields

    file_release = open_store(file_store_uri).open(file_entry)
    s3_release = open_store(s3_store_uri).open(s3_entry)
    assert file_release.model_dump(mode="json") == s3_release.model_dump(mode="json")


def test_reexport_is_a_new_version(store_uri: str) -> None:
    """§5.1: re-exporting the same record creates a new version rather than
    overwriting; `list()` surfaces only the newest, `list(all_versions=True)` surfaces
    all of them newest first, and older versions remain intact."""
    store = open_store(store_uri)
    release, files = its_saxy_source()

    first_entry = store.put(release, files)

    second_release = release.model_copy(
        deep=True,
        update={
            "provenance": [
                provenance.model_copy(update={"exported_at": SECOND_EXPORT_AT})
                if provenance.kind == "vinylcat"
                else provenance
                for provenance in release.provenance
            ]
        },
    )
    second_entry = store.put(second_release, files)

    latest = store.list()
    assert len(latest) == 1
    assert latest[0].exported_at == SECOND_EXPORT_AT

    all_versions = store.list(all_versions=True)
    assert [entry.exported_at for entry in all_versions] == [
        SECOND_EXPORT_AT,
        SAXY_EXPORTED_AT,
    ]

    reopened_first = store.open(first_entry)
    assert reopened_first.model_dump(mode="json") == release.model_dump(mode="json")
    reopened_second = store.open(second_entry)
    assert reopened_second.model_dump(mode="json") == second_release.model_dump(mode="json")


def test_put_never_overwrites(store_uri: str) -> None:
    """§5.1: `put` never overwrites an existing version — putting the same record with
    the same `exported_at` twice raises `StoreError` and leaves the original intact."""
    store = open_store(store_uri)
    release, files = its_saxy_source()

    store.put(release, files)

    with pytest.raises(StoreError):
        store.put(release, files)

    entries = store.list(all_versions=True)
    assert len(entries) == 1
    assert store.open(entries[0]).model_dump(mode="json") == release.model_dump(mode="json")


def test_slug_matches_the_vinylcat_slug(store_uri: str) -> None:
    """§5.1/§11: the entry's `slug` agrees with the vinylCatalogue slug for this
    record and with `bundle_slug(release)`. Entries are addressed by `record_id` and
    `uri`, not by slug — this pins agreement, not a join key."""
    release, files = its_saxy_source()
    store = open_store(store_uri)

    entry = store.put(release, files)

    assert entry.slug == SAXY_SLUG
    assert entry.slug == bundle_slug(release)


def _reexported(release: Release, exported_at: datetime, **overrides: object) -> Release:
    """A deep copy of `release` whose `vinylcat` provenance claims `exported_at`."""
    return release.model_copy(
        deep=True,
        update={
            "provenance": [
                provenance.model_copy(update={"exported_at": exported_at})
                if provenance.kind == VINYLCAT_PROVENANCE_KIND
                else provenance
                for provenance in release.provenance
            ],
            **overrides,
        },
    )


def _raised_type(store: BundleStore, address: str) -> type[BaseException]:
    """The type of whatever `open(address)` raises — the thing being compared when the
    question is whether both backends fail the same way, not merely that both fail."""
    try:
        store.open(address)
    except BaseException as exc:  # noqa: BLE001 - the type is the assertion
        return type(exc)
    raise AssertionError(f"opening {address} did not raise")


def test_put_refuses_a_second_version_in_the_same_second(store_uri: str) -> None:
    """A version is `<record>/<exported_at to seconds>`, so two exports of one record
    in the same second are one address whatever their metadata says. Both used to
    succeed under one timestamp with different slugs, and `list()` then returned the
    older of the two — refusal is the only answer that keeps one address, one bundle."""
    store = open_store(store_uri)
    release, files = its_saxy_source()

    first_entry = store.put(release, files)

    # Differs only in microseconds, which the layout truncates away.
    with pytest.raises(StoreError, match=re.escape(SAXY_RECORD_ID)):
        store.put(_reexported(release, SAME_SECOND_EXPORT_AT), files)

    # Same instant, different metadata — a different slug is a different leaf, not a
    # different version.
    retitled = _reexported(release, SAXY_EXPORTED_AT, title=RETITLED_TITLE)
    assert bundle_slug(retitled) != bundle_slug(release)
    with pytest.raises(StoreError, match=re.escape(SAXY_RECORD_ID)):
        store.put(retitled, files)

    entries = store.list(all_versions=True)
    assert entries == [first_entry]
    assert store.open(entries[0]).title == SAXY_TITLE


@pytest.mark.parametrize("record_id", ESCAPING_RECORD_IDS)
def test_put_refuses_a_record_id_that_is_not_one_path_segment(
    store_uri: str, record_id: str
) -> None:
    """The record id becomes one path (or key) segment, and it is a string off a
    possibly hand-edited `release.json`: neither backend may be made to write outside
    the store root, and both refuse with the same exception."""
    store = open_store(store_uri)
    release, files = its_saxy_source()
    escaping = release.model_copy(
        deep=True,
        update={
            "provenance": [
                provenance.model_copy(update={"id": record_id})
                if provenance.kind == VINYLCAT_PROVENANCE_KIND
                else provenance
                for provenance in release.provenance
            ]
        },
    )

    with pytest.raises(StoreError, match="path segment"):
        store.put(escaping, files)

    assert store.list(all_versions=True) == []


def test_a_release_that_folds_to_no_slug_is_stored_and_listed(store_uri: str) -> None:
    """A pressing whose artist, title and catalogue number all fold away used to be
    written a level above where `list` looks on `file://` (an empty path component
    disappears from a join) and listed with `slug=""` on `s3://`. One named fallback
    segment, and the two backends agree again."""
    store = open_store(store_uri)
    release, files = its_saxy_source()
    unsluggable = release.model_copy(
        deep=True,
        update={
            "title": UNSLUGGABLE_TITLE,
            "artists": [
                artist.model_copy(update={"name": UNSLUGGABLE_ARTIST})
                for artist in release.artists
            ],
            "labels": [],
        },
    )

    entry = store.put(unsluggable, files)

    assert entry.slug == FALLBACK_SLUG
    assert entry.uri.endswith(f"/{FALLBACK_SLUG}")
    assert store.list() == [entry]
    assert store.open(entry).title == UNSLUGGABLE_TITLE


def test_a_missing_store_root_fails_the_same_way_on_both_backends(
    missing_file_store_uri: str, missing_s3_store_uri: str
) -> None:
    """A `file://` root that does not exist and an `s3://` bucket that does not are the
    same misconfiguration, and a consumer's `except StoreError` around `list()` has to
    catch both — botocore's `NoSuchBucket` means nothing to it."""
    file_store = open_store(missing_file_store_uri)
    s3_store = open_store(missing_s3_store_uri)

    with pytest.raises(StoreNotFound):
        file_store.list()
    with pytest.raises(StoreNotFound):
        s3_store.list()

    assert issubclass(StoreNotFound, StoreError)


def test_the_same_fault_raises_the_same_type_on_both_backends(
    file_store_uri: str, s3_store_uri: str
) -> None:
    """§5.1's claim is that the local→hosted move is configuration, not code — which
    only holds if a consumer's error handling is the same on both sides. Each backend
    is covered on its own elsewhere; this pins them to each other."""
    release, files = its_saxy_source()
    file_store = open_store(file_store_uri)
    s3_store = open_store(s3_store_uri)
    file_store.put(release, files)
    s3_store.put(release, files)

    faults = [
        FOREIGN_URI,
        # An address at entry depth that holds nothing
        f"/{SAXY_RECORD_ID}/{UNUSED_TIMESTAMP_DIRNAME}/{SAXY_SLUG}",
        # A prefix inside the store that is not an entry: the record's own directory
        f"/{SAXY_RECORD_ID}",
    ]
    for fault in faults:
        file_address = fault if fault == FOREIGN_URI else f"{file_store_uri}{fault}"
        s3_address = fault if fault == FOREIGN_URI else f"{s3_store_uri}{fault}"
        assert _raised_type(file_store, file_address) is _raised_type(s3_store, s3_address)
        assert _raised_type(file_store, file_address) is StoreError


def test_seed_creates_a_store_that_has_never_been_written_to(unseeded_store_uri: str) -> None:
    """§5.1's Fixture bullet is the first thing a dev stack runs, against a store root
    nothing has created yet. The idempotency check reads before `put` writes, so a
    `list` that refuses a missing root has to be read as "empty store" here — otherwise
    the documented first-run command exits 1 on a fresh machine."""
    entry = seed_its_saxy_store(unseeded_store_uri)

    assert entry.record_id == SAXY_RECORD_ID
    assert entry.exported_at == SAXY_EXPORTED_AT
    assert entry.slug == SAXY_SLUG

    store = open_store(unseeded_store_uri)
    assert store.list() == [entry]
    assert store.open(entry).title == SAXY_TITLE

    # And the second run, now that the store exists, is still idempotent.
    assert seed_its_saxy_store(unseeded_store_uri) == entry
    assert len(store.list(all_versions=True)) == 1


def test_seed_its_saxy_store_is_idempotent(file_store_uri: str) -> None:
    """§5.1: "Each dev stack seeds IT'S SAXY into a local `file://` store" — a dev
    stack restarts, so `seed_its_saxy_store` must be callable repeatedly without
    raising or duplicating the entry."""
    entry = seed_its_saxy_store(file_store_uri)

    assert entry.record_id == SAXY_RECORD_ID
    assert entry.exported_at == SAXY_EXPORTED_AT
    assert entry.slug == SAXY_SLUG
    assert entry.schema_version == SAXY_SCHEMA_VERSION

    store = open_store(file_store_uri)
    listed = store.list()
    assert len(listed) == 1
    assert listed[0] == entry

    second_entry = seed_its_saxy_store(file_store_uri)
    assert second_entry == entry
    assert len(store.list(all_versions=True)) == 1
