# Acceptance: IT'S SAXY through a bundle store, over both backends

Feature `bundle-store-plans` (plan 1 of 12). WP7a of `INTEGRATION.md` §12: the
URI-addressed bundle store of §5.1 — `open_store(uri)` returning a `BundleStore` with
`list` / `open` / `put` over `file://` and `s3://`, the `BundleEntry` shape, the
versioned layout, and fixture seeding.

Add the store builders to `tests/conftest.py` and create `tests/test_store_fixture.py`:
the batch's black-box acceptance test, which seeds the real IT'S SAXY bundle into a
store and drives §5.1's whole story through the public API.

Independent of other plans. **This file is RED for the whole batch** — `mediacore.store`
does not exist until plan 04 and `seed_its_saxy_store` until plan 09. It goes green at
level 3's gate (`10-gate.md`), and the sentinels at `05-gate.md` and `08-gate.md` list
it as `expected-red`.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- `INTEGRATION.md` §5.1 is the specification. Quote it in docstrings the way the
  existing tests quote §3–5 and §11; do not restate it in prose.
- The public surface this file uses, all re-exported from the package root
  (`from mediacore import ...`), none of it on disk yet:
  `open_store(uri) -> BundleStore`, `BundleStore.list(*, all_versions=False)`,
  `BundleStore.open(entry, *, verify=True) -> Release`,
  `BundleStore.put(release, files) -> BundleEntry`, `BundleEntry`, `StoreError`,
  `bundle_slug(release) -> str`, `seed_its_saxy_store(store_uri) -> BundleEntry`.
- `BundleEntry { record_id, exported_at, slug, uri, schema_version }` — a frozen
  Pydantic model. `exported_at` is a `datetime`; the other four are `str`, `str`, `str`,
  `int`.
- `record_id` and `exported_at` are read from the `provenance` entry whose
  `kind == "vinylcat"` (`INTEGRATION.md` §4: "Kinds so far: `vinylcat` (id = the record
  ULID)"). They are **not** parsed out of the entry's path.
- Store layout: `<root>/<record ULID>/<exported_at as `%Y%m%dT%H%M%SZ`>/<slug>/`, and
  inside that leaf the §5 bundle (`release.json` + `media/<sha256>.<ext>`).
- Already on disk and used by this file: `mediacore.its_saxy_bundle() -> Path`,
  `mediacore.read_bundle(path, *, verify=True) -> Release`, `mediacore.BundleError`.
- `tests/conftest.py` already defines `SAMPLE_EXPORTED_AT`
  (`datetime(2026, 1, 2, 3, 4, 5, tzinfo=UTC)`), `SAMPLE_RECORD_ID`
  (`"01M08WYYQGY1S66KY425FYCBS7"`), `sha256_bytes`, `make_release(**overrides)` —
  which already builds a `Provenance(kind="vinylcat", id=SAMPLE_RECORD_ID,
  exported_at=SAMPLE_EXPORTED_AT)` — `make_media_file`, `make_audio_file`, and
  `write_source_files`.
- IT'S SAXY facts this file asserts (`INTEGRATION.md` §11 and the committed
  `fixtures/its-saxy/release.json`): record ULID `01M08WYYQGY1S66KY425FYCBS7`,
  `exported_at` `2026-08-25T00:00:00Z`, vinylcat slug
  `the-duke-s-combo--it-s-saxy--saae-1012`, `schema_version` 1, title `IT'S SAXY`,
  four `media` entries and twelve `audio` entries.
- `boto3` and `moto[s3]` reach the dev extra in plan 04. **Import them inside the
  fixture body, never at module scope**, so a missing extra fails only the s3 tests
  instead of erroring collection for the whole suite. `moto` 5 exposes `mock_aws`.
- No bash: you cannot run pytest. Write the file and stop.

## Files

- Modify `tests/conftest.py`
- Create `tests/test_store_fixture.py`
- Modify `tests/README.md`

## `tests/conftest.py`

Append the store builders below the existing ones. These are the batch's shared
fixtures — plans 02, 03 and 06 use them by name and must not redefine them.

Constants, beside the existing `SAMPLE_*` block:

```python
# Bundle store test fixtures (INTEGRATION.md §5.1)
S3_TEST_BUCKET = "mediacore-test-bundles"
S3_TEST_PREFIX = "bundles"
S3_TEST_REGION = "us-east-1"
S3_TEST_CREDENTIAL = "testing"
```

Then:

```python
@pytest.fixture
def file_store_uri(tmp_path: Path) -> str:
    """A `file://` bundle store root that already exists."""
    root = tmp_path / "store"
    root.mkdir()
    return root.as_uri()


@pytest.fixture
def s3_store_uri(monkeypatch: pytest.MonkeyPatch) -> Iterator[str]:
    """An `s3://` bundle store served by moto — no network, no real credentials."""
    import boto3
    from moto import mock_aws

    for name in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"):
        monkeypatch.setenv(name, S3_TEST_CREDENTIAL)
    monkeypatch.setenv("AWS_DEFAULT_REGION", S3_TEST_REGION)
    with mock_aws():
        boto3.client("s3", region_name=S3_TEST_REGION).create_bucket(Bucket=S3_TEST_BUCKET)
        yield f"s3://{S3_TEST_BUCKET}/{S3_TEST_PREFIX}"


@pytest.fixture(params=["file", "s3"])
def store_uri(request: pytest.FixtureRequest, file_store_uri: str, s3_store_uri: str) -> str:
    """Both backends, so a test written once runs against each (INTEGRATION.md §5.1)."""
    return {"file": file_store_uri, "s3": s3_store_uri}[request.param]


def its_saxy_source() -> tuple[Release, dict[str, Path]]:
    """The committed IT'S SAXY bundle as the `(release, files)` pair `put` takes."""
    bundle = its_saxy_bundle()
    release = read_bundle(bundle)
    files = {entry.sha256: bundle / entry.file for entry in (*release.media, *release.audio)}
    return release, files
```

`its_saxy_source` is a plain function, not a fixture, so a test may call it twice to
build two versions of the same record. Add `its_saxy_bundle` and `read_bundle` to the
existing `from mediacore import ...` line, and `Iterator` from `collections.abc`.

## `tests/test_store_fixture.py`

Module docstring: *"Acceptance test for the bundle store (INTEGRATION.md §5.1). Seeds
the committed IT'S SAXY bundle into a store and drives the whole §5.1 story through the
public API — put, list, open, re-export, seeding — against both backends, because
§5.1's claim is that the local→hosted move is configuration, not code."*

Constants at the top, from `INTEGRATION.md` §11 — no inline literals in the assertions:

```python
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
```

The cases, each quoting the §5.1 bullet it pins:

1. `test_put_lists_and_opens_the_fixture(store_uri)` — `put` the fixture; `list()`
   returns exactly one entry; its `record_id`, `exported_at`, `slug` and
   `schema_version` equal the constants above; `open(entry)` returns a `Release` whose
   `model_dump(mode="json")` equals the fixture's, with `SAXY_MEDIA_COUNT` media and
   `SAXY_AUDIO_COUNT` audio entries. The entry `put` returned equals the one `list`
   returns.
2. `test_entry_uri_addresses_the_entry(store_uri)` — `entry.uri` starts with
   `store_uri` and contains `SAXY_RECORD_ID`; `open(entry.uri)` returns the same
   `Release` as `open(entry)`. This is the call WP7c/7d make with the `entry_uri` a
   consumer posts back.
3. `test_both_backends_produce_the_same_entry(file_store_uri, s3_store_uri)` — put the
   same fixture into both; the two `BundleEntry` values are equal on every field except
   `uri`, and both `open` to the same `Release`. Assert by comparing
   `entry.model_dump(mode="json")` with `uri` popped from each.
4. `test_reexport_is_a_new_version(store_uri)` — put the fixture, then put it again
   with the vinylcat provenance's `exported_at` moved to `SECOND_EXPORT_AT` (build the
   second release with `release.model_copy(deep=True)` and a replaced `provenance`
   list). `list()` returns one entry, the `SECOND_EXPORT_AT` one;
   `list(all_versions=True)` returns both, newest first; the original entry still opens
   and still verifies.
5. `test_put_never_overwrites(store_uri)` — putting the same record with the same
   `exported_at` twice raises `StoreError`; afterwards `list(all_versions=True)` still
   has exactly one entry and it still opens.
6. `test_slug_matches_the_vinylcat_slug(store_uri)` — the entry's `slug` equals
   `SAXY_SLUG`, the slug `INTEGRATION.md` §11 records for this record in
   vinylCatalogue, and equals `bundle_slug(release)`. Nothing addresses an entry by
   slug — `record_id` and `uri` do that — so this pins agreement, not a join key.
7. `test_seed_its_saxy_store_is_idempotent(file_store_uri)` —
   `seed_its_saxy_store(file_store_uri)` returns a `BundleEntry` matching the constants
   above; `open_store(file_store_uri).list()` returns it; calling `seed_its_saxy_store`
   a second time returns an equal entry rather than raising, and leaves exactly one
   entry in the store. §5.1 → "Each dev stack seeds *IT'S SAXY* into a local `file://`
   store" — a dev stack restarts, so seeding must be repeatable.

## `tests/README.md`

Add one bullet, in file order among the existing `test_*` bullets:

> - `test_store_fixture.py` — the batch's acceptance test for the bundle store
>   (`INTEGRATION.md` §5.1): seeds the committed IT'S SAXY bundle into a store and
>   drives put / list / open / re-export / seeding through the public API, parametrized
>   over both backends by the `store_uri` fixture, because §5.1's claim is that moving
>   from `file://` to `s3://` is configuration and not code.

Extend the `conftest.py` bullet's builder list with `file_store_uri`, `s3_store_uri`,
the parametrized `store_uri`, `its_saxy_source()`, and the constants `S3_TEST_BUCKET`,
`S3_TEST_PREFIX`, `S3_TEST_REGION`, `S3_TEST_CREDENTIAL`. Say that `s3_store_uri`
imports `boto3` and `moto` inside its body so a missing `[dev]` extra fails only the s3
tests.
