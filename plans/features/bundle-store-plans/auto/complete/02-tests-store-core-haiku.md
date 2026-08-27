# Tests: URI dispatch, `BundleEntry`, and the slug

Feature `bundle-store-plans` (plan 2 of 12). WP7a of `INTEGRATION.md` §12: the
URI-addressed bundle store of §5.1 — `open_store(uri)` returning a `BundleStore` with
`list` / `open` / `put` over `file://` and `s3://`, the `BundleEntry` shape, the
versioned layout, and fixture seeding.

Create `tests/test_store.py` — the backend-independent half of `mediacore.store`:
scheme dispatch, the `BundleEntry` shape, the slug derivation, and the rule that an
entry's fields come from its `release.json` and never from its path.

Depends on: `01-acceptance-tests-sonnet.md` for the shared `tests/conftest.py`
builders. Level 1 of the batch; RED until plan 04.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- `INTEGRATION.md` §5.1 is the specification. Quote the bullet each test pins, the way
  the existing tests quote §3–5.
- Public surface used here, all from `from mediacore import ...`, none on disk yet:
  `open_store`, `BundleEntry`, `StoreError`, `bundle_slug`.
- `BundleEntry { record_id: str, exported_at: datetime, slug: str, uri: str,
  schema_version: int }` — a frozen Pydantic model with `extra="forbid"`.
- `record_id` and `exported_at` are read from the `provenance` entry whose
  `kind == "vinylcat"` (§4: "Kinds so far: `vinylcat` (id = the record ULID)"), never
  parsed out of the entry's path.
- Store layout: `<root>/<record ULID>/<exported_at as `%Y%m%dT%H%M%SZ`>/<slug>/`, and
  inside that leaf the §5 bundle (`release.json` + `media/<sha256>.<ext>`).
- `bundle_slug(release)` joins with `--`: the first artist's name, the title, and the
  first non-empty `labels[].catalogue_number` when there is one. Each segment is folded
  through `normalize_text`, lowercased, and every run of characters outside `[a-z0-9]`
  replaced with a single `-`, then stripped of leading/trailing `-`.
- **Do not test `s3://` here.** `open_store` learns the `s3` scheme in plan 07 at level
  2; at level 1 it raises `StoreError` for it, and a test either way would be wrong at
  one of the two gates. `tests/test_store_s3.py` (plan 06) owns every s3 assertion.
- `tests/conftest.py` provides `SAMPLE_EXPORTED_AT`
  (`datetime(2026, 1, 2, 3, 4, 5, tzinfo=UTC)`), `SAMPLE_RECORD_ID`
  (`"01M08WYYQGY1S66KY425FYCBS7"`), `make_release(**overrides)` — which already builds
  a `Provenance(kind="vinylcat", id=SAMPLE_RECORD_ID, exported_at=SAMPLE_EXPORTED_AT)` —
  `make_media_file`, `write_source_files`, and the `file_store_uri` fixture. Use them;
  do not add builders of your own to `conftest.py`.
- `mediacore.write_bundle(release, dest, files) -> Path` writes a §5 bundle at `dest`;
  use it directly to build the hand-made store trees two of these cases need.
- No bash: you cannot run pytest. Write the file and stop.

## Files

- Create `tests/test_store.py`
- Modify `tests/README.md`

## `tests/test_store.py`

Module docstring: *"The backend-independent half of `mediacore.store`
(INTEGRATION.md §5.1): which URIs `open_store` accepts, what a `BundleEntry` is, how a
bundle's directory name is derived, and the rule that an entry's fields are read from
its `release.json` and never parsed out of its key."*

Constants at the top:

```python
# The §11 record, and the slug vinylCatalogue records for it
SAXY_SLUG = "the-duke-s-combo--it-s-saxy--saae-1012"
SAXY_ARTIST = "The Duke's Combo"
SAXY_TITLE = "IT'S SAXY"
SAXY_CATALOGUE_NUMBER = "SAAE 1012"
# A store tree whose directory names disagree with its release.json
MISLEADING_RECORD_DIR = "01ZZZZZZZZZZZZZZZZZZZZZZZZ"
MISLEADING_TIMESTAMP_DIR = "19990101T000000Z"
MISLEADING_SLUG_DIR = "not-the-slug"
```

The cases:

1. `test_open_store_accepts_a_file_uri(file_store_uri)` — returns an object with
   `list`, `open` and `put`, and nothing else public on it beyond those three
   (`INTEGRATION.md` §5.1: "three methods and nothing else").
2. `test_open_store_rejects_an_unknown_scheme` — parametrized over
   `"https://example.com/bundles"`, `"ftp://example.com/bundles"` and
   `"gs://bucket/bundles"`; each raises `StoreError` whose message names the scheme.
3. `test_open_store_rejects_a_uri_with_no_scheme` — parametrized over an absolute path
   (`"/tmp/bundles"`) and a relative one (`"bundles"`); `StoreError`, and the message
   mentions `file://` so the caller knows what to write instead.
4. `test_open_store_rejects_a_foreign_file_host` — `"file://example.com/bundles"`
   raises `StoreError`; `"file://localhost/tmp"` is accepted, since that is the same
   machine.
5. `test_bundle_entry_fields` — construct one directly; the five fields hold what was
   passed, `exported_at` is a `datetime`, an unknown keyword raises `ValidationError`
   (`extra="forbid"`), and assigning to a field raises `ValidationError` (frozen).
6. `test_bundle_entry_serializes_for_a_consumer` — `model_dump(mode="json")` has
   exactly the five keys and an ISO-8601 string for `exported_at`. §5.1's consumer
   endpoints return `InboxEntryOut` built from these values, so they have to survive
   JSON.
7. `test_bundle_slug_matches_the_vinylcat_slug` — `bundle_slug` of a release built with
   `SAXY_ARTIST`, `SAXY_TITLE` and a label carrying `SAXY_CATALOGUE_NUMBER` equals
   `SAXY_SLUG`, the slug `INTEGRATION.md` §11 records for this record in
   vinylCatalogue.
8. `test_bundle_slug_without_a_catalogue_number` — a release whose labels are empty, and
   one whose only label has `catalogue_number=None`, both give the two-segment
   `<artist>--<title>` form.
9. `test_bundle_slug_folds_accents_and_punctuation` — an artist like `"Édith Piaf"` and
   a title with punctuation and doubled spaces produce a slug of only `[a-z0-9-]`, with
   no leading, trailing or doubled `-` inside a segment.
10. `test_entry_fields_come_from_release_json_not_the_path(file_store_uri)` — write a
    bundle with `write_bundle` into
    `<root>/<MISLEADING_RECORD_DIR>/<MISLEADING_TIMESTAMP_DIR>/<MISLEADING_SLUG_DIR>/`,
    then `list()`: the entry's `record_id` is `SAMPLE_RECORD_ID`, its `exported_at` is
    `SAMPLE_EXPORTED_AT` and its `slug` is `bundle_slug(release)` — none of the three
    misleading directory names. `uri` is the one field that *is* the path, and it ends
    with `MISLEADING_SLUG_DIR`.
11. `test_list_returns_newest_first(file_store_uri)` — `put` three releases whose
    `exported_at` values are deliberately out of directory order across two record ids;
    `list(all_versions=True)` comes back sorted by `exported_at`, newest first.
12. `test_package_version_matches_distribution_metadata` —
    `mediacore.__version__ == importlib.metadata.version("mediacore")`. WP7b/7c/7d pin
    a tag cut from this branch, and the two version strings drifting apart is invisible
    from either one alone.

## `tests/README.md`

Add one bullet, in file order among the existing `test_*` bullets:

> - `test_store.py` — the backend-independent half of `mediacore.store`
>   (`INTEGRATION.md` §5.1): `open_store` scheme dispatch and its refusals, the
>   `BundleEntry` shape and its JSON form, `bundle_slug` (pinned against the vinylcat
>   slug §11 records), the rule that an entry's fields are read from its `release.json`
>   and never from its path, `list` ordering, and that `__version__` matches the
>   installed distribution's metadata. Every `s3://` assertion lives in
>   `test_store_s3.py` instead.
