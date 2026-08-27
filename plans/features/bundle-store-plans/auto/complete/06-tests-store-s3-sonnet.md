# Tests: the `s3://` backend, against moto

Feature `bundle-store-plans` (plan 6 of 12). WP7a of `INTEGRATION.md` §12: the
URI-addressed bundle store of §5.1 — `open_store(uri)` returning a `BundleStore` with
`list` / `open` / `put` over `file://` and `s3://`, the `BundleEntry` shape, the
versioned layout, and fixture seeding.

Create `tests/test_store_s3.py` — the same §5.1 behaviour over `s3://`, plus the key
layout, listing across pages, and the optional-extra guard.

Depends on: `01-acceptance-tests-sonnet.md` for the `s3_store_uri` fixture, and on
level 1 being on disk. **The contract for this file is
`src/mediacore/store.py` and `tests/test_store_file.py`, both already written — read
them before writing, and take every name and message shape from them rather than
guessing.** Level 2 of the batch; RED until plan 07.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- `INTEGRATION.md` §5.1 is the specification: "`s3://<bucket>/<prefix>` — hosted: the
  same layout under a key prefix", using "the ambient boto3 credential chain;
  `mediacore` takes no keys and the browser never sees the store. `boto3` is the
  optional extra `mediacore[s3]`."
- `tests/conftest.py` provides the `s3_store_uri` fixture — a moto-backed bucket
  `mediacore-test-bundles` with prefix `bundles`, fake credentials set in the
  environment, no network — plus `file_store_uri`, `SAMPLE_RECORD_ID`,
  `SAMPLE_EXPORTED_AT`, `make_release`, `make_media_file`, `write_source_files` and
  `its_saxy_source()`. Use them; do not add builders of your own to `conftest.py`.
- `moto` 5's entry point is `from moto import mock_aws`; the fixture already holds it
  open for the test body, so a test only needs `boto3.client("s3")` to look at the
  bucket directly. Import `boto3` and `moto` inside test bodies or fixtures, never at
  module scope.
- Store layout, identical to the `file://` one:
  `<prefix>/<record ULID>/<exported_at as `%Y%m%dT%H%M%SZ`>/<slug>/release.json` and
  `.../<slug>/media/<sha256>.<ext>`. Keys never contain a doubled `/`.
- `mediacore.store` exposes `S3_LIST_PAGE_SIZE` and `_import_boto3` for exactly two of
  these tests to monkeypatch. Read `src/mediacore/store.py` for their real names before
  using them.
- No bash: you cannot run pytest. Write the file and stop.

## Files

- Create `tests/test_store_s3.py`
- Modify `tests/README.md`

## `tests/test_store_s3.py`

Module docstring: *"The `s3://` bundle store backend (INTEGRATION.md §5.1) — the same
layout under a key prefix. Run against moto, which intercepts botocore below the HTTP
layer, so this suite needs no network and no real credentials."*

Constants at the top: the bucket and prefix names imported from `conftest`, plus

```python
# Objects an entry is made of
ENTRY_RELEASE_KEY_SUFFIX = "/release.json"
ENTRY_MEDIA_KEY_PART = "/media/"
# A release.json claiming a schema this install does not know
FUTURE_SCHEMA_VERSION = SCHEMA_VERSION + 1
```

The cases:

1. `test_open_store_accepts_an_s3_uri(s3_store_uri)` — `open_store` returns a store
   with `list`, `open` and `put`. Constructing it neither reads a credential argument
   nor takes one: `open_store`'s only parameter is the URI.
2. `test_put_writes_the_documented_keys(s3_store_uri)` — `put` a release with two media
   payloads, then list the bucket with `list_objects_v2`: the key set is exactly the
   `release.json` and one `media/<sha256>.<ext>` per file, all under
   `<prefix>/<SAMPLE_RECORD_ID>/<timestamp>/<slug>/`, with no doubled `/` and no key
   above the prefix.
3. `test_prefix_forms_are_equivalent` — `s3://<bucket>` (no prefix),
   `s3://<bucket>/bundles` and `s3://<bucket>/bundles/` each produce the same relative
   layout below whatever prefix they name, and `list()` on each sees its own entries
   only.
4. `test_entry_matches_the_file_backend(s3_store_uri, file_store_uri)` — put the same
   release into both; the two entries are equal on every field but `uri`, and the s3
   entry's `uri` is `s3://<bucket>/<prefix>/<record>/<timestamp>/<slug>`.
5. `test_open_accepts_an_entry_or_its_uri(s3_store_uri)` — `open(entry)` and
   `open(entry.uri)` return equal releases; an `s3://` URI in another bucket, and one
   under this prefix with no objects, each raise `StoreError`.
6. `test_open_verifies_by_default(s3_store_uri)` — `put_object` different bytes over
   one stored media key; `open(entry)` raises `BundleError` naming the file, and
   `open(entry, verify=False)` still returns the `Release`.
7. `test_schema_version_newer_than_this_install(s3_store_uri)` — `put_object` a
   `release.json` with `schema_version` `FUTURE_SCHEMA_VERSION` over the stored one:
   `open` raises `BundleError` with `verify=False` as well as `verify=True`, and
   `list()` still returns the entry carrying `FUTURE_SCHEMA_VERSION`. §5.1 grants this
   listing exception explicitly.
8. `test_put_refuses_to_overwrite(s3_store_uri)` — putting the same release twice
   raises `StoreError`; afterwards the stored `release.json` bytes are unchanged and
   `list(all_versions=True)` has one entry.
9. `test_an_entry_without_release_json_is_not_listed(s3_store_uri)` — `put_object` a
   media object under a well-formed entry prefix and nothing else; `list()` does not
   return it. `put` uploads `release.json` last for this reason: a half-uploaded entry
   must never appear in a consumer's inbox.
10. `test_list_spans_pages(s3_store_uri, monkeypatch)` — monkeypatch
    `mediacore.store.S3_LIST_PAGE_SIZE` to 1, put three records, and assert
    `list(all_versions=True)` still returns all three in the right order. A real store
    will exceed one page; this proves the paginator is used without seeding a thousand
    objects.
11. `test_missing_boto3_names_the_extra(s3_store_uri, monkeypatch)` — monkeypatch
    `mediacore.store._import_boto3` to raise `ImportError`; `open_store("s3://…")`
    raises `StoreError` whose message names `mediacore[s3]`. §5.1 makes boto3 optional,
    so the failure has to say what to install.
12. `test_versions_and_latest_per_record(s3_store_uri)` — two records × two
    `exported_at` values; `list()` returns the later of each, `list(all_versions=True)`
    all four newest-first, and every earlier entry still opens. The same assertion
    `tests/test_store_file.py` makes, repeated here because §5.1's promise is that the
    two backends behave identically.

## `tests/README.md`

Add one bullet, in file order among the existing `test_*` bullets:

> - `test_store_s3.py` — the `s3://` backend (`INTEGRATION.md` §5.1) against `moto`,
>   which intercepts botocore below the HTTP layer, so the suite needs no network and
>   no credentials: the key layout under a prefix (and that the three prefix forms are
>   equivalent), an entry identical to the `file://` backend's but for its `uri`,
>   `open` verifying and refusing a newer `schema_version` that `list` still returns,
>   `put` refusing to overwrite, a half-uploaded entry with no `release.json` staying
>   unlisted, listing across pages (via `S3_LIST_PAGE_SIZE`), and a missing `boto3`
>   raising `StoreError` naming the `mediacore[s3]` extra.
