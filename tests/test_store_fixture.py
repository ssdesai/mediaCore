"""Acceptance test for the bundle store (INTEGRATION.md §5.1). Seeds the committed
IT'S SAXY bundle into a store and drives the whole §5.1 story through the public API —
put, list, open, re-export, seeding — against both backends, because §5.1's claim is
that the local→hosted move is configuration, not code.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from mediacore import (
    StoreError,
    bundle_slug,
    open_store,
    seed_its_saxy_store,
)

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
