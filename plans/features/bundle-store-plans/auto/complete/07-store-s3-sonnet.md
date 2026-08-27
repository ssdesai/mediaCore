# The `s3://` backend

Feature `bundle-store-plans` (plan 7 of 12). WP7a of `INTEGRATION.md` §12: the
URI-addressed bundle store of §5.1 — `open_store(uri)` returning a `BundleStore` with
`list` / `open` / `put` over `file://` and `s3://`, the `BundleEntry` shape, the
versioned layout, and fixture seeding.

Add `S3BundleStore` to `src/mediacore/store.py` and the `s3` branch to `open_store`.

Depends on: level 1 (`04-store-core-file-sonnet.md`) and
`06-tests-store-s3-sonnet.md`. Closes level 2.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- `INTEGRATION.md` §5.1: "`s3://<bucket>/<prefix>` — hosted: the same layout under a key
  prefix", using "the ambient boto3 credential chain; `mediacore` takes no keys and the
  browser never sees the store. `boto3` is the optional extra `mediacore[s3]`."
- **The contract is already on disk: read `src/mediacore/store.py` and
  `tests/test_store_s3.py` before writing a line.** `store.py` holds the shared
  helpers this backend must reuse rather than re-derive — the entry model, the layout
  segments, the raw-payload parse, the latest-per-record selection, the boto3 import
  seam, `StoreError` — and `tests/test_store_s3.py` names each one it monkeypatches.
  Take every name, signature and message shape from those two files; do not invent a
  parallel set.
- `mediacore.bundle` provides `read_bundle(path, *, verify=True)`,
  `write_bundle(release, dest, files) -> Path`, `BUNDLE_RELEASE_FILENAME`,
  `BUNDLE_MEDIA_DIRNAME` and `BundleError`. This backend does its bundle work through
  them against a temporary directory, so every §5 check happens in exactly one
  implementation.
- CONVENTIONS.md: named constants at the top of the file, grouped under a label
  comment. `S3_LIST_PAGE_SIZE` is one of them and `tests/test_store_s3.py`
  monkeypatches it.
- No bash: you cannot run pytest, ruff or pip. Write the files and stop.

## Files

- Modify `src/mediacore/store.py`
- Modify `src/mediacore/README.md`

## `src/mediacore/store.py`

Add a constants group beside the existing ones — the client's service name, the listing
page size (`S3_LIST_PAGE_SIZE`), the key separator, and the `list_objects_v2` paginator
name — then `S3BundleStore(BundleStore)`, constructed from a bucket, a key prefix
(possibly empty) and the store URI, holding a client built once from
`_import_boto3().client(...)` with no credential, region or endpoint argument: §5.1
says `mediacore` takes no keys, so the ambient chain is the whole configuration story.

Three methods, mirroring `FileBundleStore` exactly — the promise §5.1 makes is that the
two behave identically, so anything that differs beyond "keys instead of paths" is a
defect:

- **`list`** — paginate `list_objects_v2` under the prefix with `S3_LIST_PAGE_SIZE` as
  the page size, keep the keys ending in `BUNDLE_RELEASE_FILENAME` at exactly the
  layout's depth below the prefix, `get_object` each one, and build the entry with the
  shared raw-payload parse and the `s3://` URI of its `<slug>` prefix. A key with no
  `release.json` beside it is simply never matched, which is what keeps a half-uploaded
  entry out of a consumer's inbox. Return the shared latest-per-record selection.
- **`open`** — resolve the argument (a `BundleEntry` or its `uri` string) to a key
  prefix, raise `StoreError` when it is not under this store, download every object
  under it into a `tempfile.TemporaryDirectory()` laid out as a §5 bundle, and
  `return read_bundle(tmp, verify=verify)`. An empty prefix — nothing there — is
  `StoreError`; a bad bundle is `BundleError` from `read_bundle`. Reusing `read_bundle`
  is what makes "open verifies like `read_bundle`" true by construction rather than by
  a second implementation.
- **`put`** — build the entry from the release, refuse with `StoreError` when the
  entry's `release.json` key already exists (`head_object`), stage the bundle into a
  `tempfile.TemporaryDirectory()` with `write_bundle` — which validates the whole
  `{sha256: Path}` mapping and hashes every file on the way — then upload. **Upload
  every `media/` object first and `release.json` last.** That ordering is this
  backend's substitute for the `file://` atomic swap: an interrupted `put` leaves
  objects that `list` does not match, never a listable entry with missing media.
  Nothing here deletes an object.

Then add the `STORE_SCHEME_S3` branch to `open_store`: bucket from the netloc, prefix
from the path with leading and trailing `/` stripped (so `s3://b`, `s3://b/p` and
`s3://b/p/` all work), and `StoreError` when the bucket is empty.

## `src/mediacore/README.md`

Extend the `store.py` entry written by plan 04 with a sub-bullet for the backend —
keep the existing bullets, do not rewrite them:

> - `s3://` is the same layout under a key prefix, over a `boto3` client built from the
>   ambient credential chain with no key, region or endpoint argument of its own.
>   `boto3` is imported lazily through one seam, so `import mediacore` works without the
>   optional `mediacore[s3]` extra and asking for an `s3://` store without it raises
>   `StoreError` naming the extra. `open` downloads an entry into a temporary directory
>   and reads it with `read_bundle`, so every §5 check has one implementation; `put`
>   stages with `write_bundle` and uploads `release.json` **last**, which is the
>   `s3://` substitute for the `file://` atomic swap — an interrupted upload leaves
>   objects that `list` never matches instead of a listable entry with missing media.
>   `S3_LIST_PAGE_SIZE` bounds the `list_objects_v2` pagination.
