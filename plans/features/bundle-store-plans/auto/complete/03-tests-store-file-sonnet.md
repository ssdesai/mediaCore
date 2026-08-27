# Tests: the `file://` backend

Feature `bundle-store-plans` (plan 3 of 12). WP7a of `INTEGRATION.md` §12: the
URI-addressed bundle store of §5.1 — `open_store(uri)` returning a `BundleStore` with
`list` / `open` / `put` over `file://` and `s3://`, the `BundleEntry` shape, the
versioned layout, and fixture seeding.

Create `tests/test_store_file.py` — the `file://` backend's behaviour: the layout it
writes, versioning, what `list` returns and refuses, and what `open` verifies.

Depends on: `01-acceptance-tests-sonnet.md` for the shared `tests/conftest.py`
builders. Level 1 of the batch; RED until plan 04.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- `INTEGRATION.md` §5.1 is the specification. Quote the bullet each test pins.
- Public surface used here, all from `from mediacore import ...`, none on disk yet:
  `open_store`, `BundleEntry`, `StoreError`, `bundle_slug`. Also `BundleError`,
  `SCHEMA_VERSION`, `read_bundle` and `write_bundle`, which are already on disk.
- Store layout: `<root>/<record ULID>/<exported_at as `%Y%m%dT%H%M%SZ`>/<slug>/`, and
  inside that leaf the §5 bundle (`release.json` + `media/<sha256>.<ext>`).
- `record_id` and `exported_at` come from the `provenance` entry whose
  `kind == "vinylcat"`; `slug` from `bundle_slug(release)`; `schema_version` from
  `release.json`'s own field.
- The failure split this batch settles, and that these tests pin:
  `StoreError` is raised for anything about the **store** — an unusable URI, a missing
  root, an entry that is not addressable, a `put` that would overwrite, a
  `release.json` the store cannot turn into an entry. `BundleError` is what
  `read_bundle` already raises and `open` passes through unchanged, for anything about
  the **bundle** — a missing or mis-hashed file, a wrong audio size, a
  `schema_version` newer than this install's.
- `put` creates the root and every intermediate directory it needs; `list` on a root
  that does not exist raises `StoreError` naming the path. A store you are writing to
  may bootstrap itself; a store you are reading that is not there is a
  misconfiguration a consumer has to see.
- `tests/conftest.py` provides `SAMPLE_EXPORTED_AT`
  (`datetime(2026, 1, 2, 3, 4, 5, tzinfo=UTC)`), `SAMPLE_RECORD_ID`
  (`"01M08WYYQGY1S66KY425FYCBS7"`), `sha256_bytes`, `make_release(**overrides)` —
  which already builds a `Provenance(kind="vinylcat", id=SAMPLE_RECORD_ID,
  exported_at=SAMPLE_EXPORTED_AT)` — `make_media_file`, `make_audio_file`,
  `write_source_files(directory, payloads) -> {sha256: Path}`, and the `file_store_uri`
  fixture. Use them; do not add builders of your own to `conftest.py`.
- To build a second version of a record, `model_copy(deep=True)` the release and
  replace its `provenance` list with one carrying a later `exported_at`. To build a
  second record, override `provenance` with a different `id`.
- `Path.as_uri()` is how a filesystem path becomes the `file://` form; `file_store_uri`
  is already in that form, so recover the root with
  `Path(urlsplit(uri).path)`.
- No bash: you cannot run pytest. Write the file and stop.

## Files

- Create `tests/test_store_file.py`
- Modify `tests/README.md`

## `tests/test_store_file.py`

Module docstring: *"The `file://` bundle store backend (INTEGRATION.md §5.1). §5's
bundle folder generalised: a directory of bundle directories, versioned by
`exported_at`, where nothing is ever overwritten or deleted."*

Constants at the top:

```python
# The layout §5.1 fixes, as this test spells it
ENTRY_TIMESTAMP_DIRNAME = "20260102T030405Z"
SECOND_EXPORT_AT = datetime(2026, 3, 4, 5, 6, 7, tzinfo=UTC)
SECOND_EXPORT_TIMESTAMP_DIRNAME = "20260304T050607Z"
OTHER_RECORD_ID = "01M08WYYQGY1S66KY425FYCBS8"
# A release.json claiming a schema this install does not know
FUTURE_SCHEMA_VERSION = SCHEMA_VERSION + 1
```

The cases:

1. `test_put_writes_the_documented_layout(file_store_uri)` — `put` a release with two
   media payloads; the bundle lands at exactly
   `<root>/<SAMPLE_RECORD_ID>/<ENTRY_TIMESTAMP_DIRNAME>/<bundle_slug(release)>/`, that
   directory holds `release.json` and a `media/` directory, `read_bundle` reads it
   back, and the returned `BundleEntry`'s `uri` is that directory's `as_uri()`. The
   root's intermediate directories were created by `put` — assert `put` also works
   against a store root that does not exist yet.
2. `test_list_on_a_missing_root_raises(tmp_path)` — `open_store` on a `file://` URI for
   a directory that does not exist succeeds, but `list()` raises `StoreError` naming
   the path.
3. `test_put_refuses_to_overwrite(file_store_uri)` — putting the same release twice
   raises `StoreError` naming the existing entry; afterwards the stored `release.json`
   bytes are byte-identical to what the first `put` wrote and
   `list(all_versions=True)` has exactly one entry. §5.1: "Nothing in `mediacore`
   overwrites or deletes an entry."
4. `test_put_requires_vinylcat_provenance(file_store_uri)` — a release whose
   `provenance` is empty, and one whose only entry has a different `kind`, each raise
   `StoreError` naming the missing `vinylcat` provenance, and nothing is written under
   the root.
5. `test_reexport_is_a_new_version(file_store_uri)` — put the release, then put a copy
   whose `exported_at` is `SECOND_EXPORT_AT`. Both directories exist side by side
   (`ENTRY_TIMESTAMP_DIRNAME` and `SECOND_EXPORT_TIMESTAMP_DIRNAME` under the same
   record directory); `list()` returns only the later one; `list(all_versions=True)`
   returns both, newest first; the earlier entry still opens.
6. `test_list_returns_the_latest_per_record(file_store_uri)` — two records
   (`SAMPLE_RECORD_ID` and `OTHER_RECORD_ID`) × two versions each; `list()` returns two
   entries, one per record, each the later version; `list(all_versions=True)` returns
   four.
7. `test_open_accepts_an_entry_or_its_uri(file_store_uri)` — `open(entry)` and
   `open(entry.uri)` return equal releases; a `file://` URI outside this store's root,
   and one under the root that has no bundle, each raise `StoreError`.
8. `test_open_verifies_by_default(file_store_uri)` — overwrite one byte of a stored
   media file; `open(entry)` raises `BundleError` naming the file, and
   `open(entry, verify=False)` still returns the `Release`.
9. `test_open_refuses_a_newer_schema_version(file_store_uri)` — rewrite the stored
   `release.json` with `schema_version` set to `FUTURE_SCHEMA_VERSION`; `open` raises
   `BundleError` **with `verify=False` as well as with `verify=True`** — §5.1 makes
   this a forward-compatibility guard, not a verification step.
10. `test_list_does_not_refuse_a_newer_schema_version(file_store_uri)` — the same
    store: `list()` still returns the entry, and its `schema_version` is
    `FUTURE_SCHEMA_VERSION`, so a consumer page can say "upgrade to import this"
    instead of hiding it. §5.1 states this exception explicitly.
11. `test_list_ignores_what_is_not_an_entry(file_store_uri)` — a loose file at the
    root, an empty record directory, and a directory at the right depth containing no
    `release.json` are all skipped; a real entry beside them is still returned.
12. `test_list_raises_on_an_unreadable_entry(file_store_uri)` — a `release.json` at the
    right depth that is not JSON, and one that is valid JSON with no `vinylcat`
    provenance, each make `list()` raise `StoreError` naming the entry's URI. An inbox
    that silently hides a broken export is worse than one that says so; the newer
    `schema_version` case in 10 is the only listing exception §5.1 grants.

## `tests/README.md`

Add one bullet, in file order among the existing `test_*` bullets:

> - `test_store_file.py` — the `file://` backend (`INTEGRATION.md` §5.1): the
>   `<root>/<record ULID>/<exported_at>/<slug>/` layout `put` writes, `put` creating
>   its own intermediates but refusing to overwrite an existing entry or to write a
>   release with no `vinylcat` provenance, re-export as a new version beside the old,
>   `list` returning the latest per record (`all_versions=True` for the rest), `open`
>   accepting an entry or its `uri` and verifying like `read_bundle`, and the split
>   between `StoreError` (the store) and `BundleError` (the bundle) — including the one
>   listing exception §5.1 grants, where an entry whose `schema_version` is newer than
>   this install is listed but refuses to open.
