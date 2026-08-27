# `mediacore.store`: the seam and the `file://` backend

Feature `bundle-store-plans` (plan 4 of 12). WP7a of `INTEGRATION.md` §12: the
URI-addressed bundle store of §5.1 — `open_store(uri)` returning a `BundleStore` with
`list` / `open` / `put` over `file://` and `s3://`, the `BundleEntry` shape, the
versioned layout, and fixture seeding.

Create `src/mediacore/store.py` with everything both backends share plus the `file://`
one, re-export it from the package root, and take `mediacore` to 0.2.0 with a `s3`
optional extra.

Depends on: `02-tests-store-core-haiku.md` and `03-tests-store-file-sonnet.md` — read
`tests/test_store.py` and `tests/test_store_file.py` before writing; they are this
level's contract. Closes level 1. The `s3` backend is plan 07 at level 2.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- `INTEGRATION.md` §5.1 is the specification. Its text is the module docstring's
  source; do not invent behaviour it does not state.
- Inside the package, import by submodule (`from mediacore.release import Release`);
  only `__init__.py` re-exports. Already on disk:
  - `mediacore/release.py` — `SCHEMA_VERSION`, `ContractModel` (the shared
    `extra="forbid"` base), `Release`, `Provenance { kind, id, label, exported_at }`,
    `ArtistRef { name, sort_name, refs }`, `LabelRef { name, catalogue_number, refs }`,
    `BUNDLE_MEDIA_DIRNAME`.
  - `mediacore/bundle.py` — `read_bundle(path, *, verify=True) -> Release`,
    `write_bundle(release, dest, files) -> Path` (`files` is a `{sha256: Path}`
    mapping; the write is atomic — it stages into a sibling temp directory and swaps),
    `sha256_file(path)`, `BUNDLE_RELEASE_FILENAME`, `BUNDLE_MEDIA_DIRNAME`,
    `BundleError`.
  - `mediacore/normalize.py` — `normalize_text(value) -> str` (NFKD, drop combining
    marks, uppercase, collapse whitespace, strip).
- `record_id` and `exported_at` are read from the `provenance` entry whose
  `kind == "vinylcat"` (§4: "Kinds so far: `vinylcat` (id = the record ULID)"). §5.1's
  `vinylcat:record` is the *ref key consumers store it under* (§8); nothing in
  `release.json` carries it, and the fixture's own `refs` bag holds only
  `discogs:release`.
- Failure split: `StoreError` for anything about the store (unusable URI, missing root,
  an entry that is not addressable, a `put` that would overwrite, a `release.json` that
  cannot become an entry); `BundleError`, raised by `read_bundle` and passed through
  unchanged, for anything about the bundle.
- CONVENTIONS.md: every literal that carries meaning is a named constant at the top of
  the file, grouped under a short label comment.
- Ruff (`E, F, I, B, UP`, line length 100) orders imported names as constants
  (UPPER_CASE), then classes (CamelCase), then functions, ASCII order within each
  group. `known-first-party = ["mediacore"]`.
- No bash: you cannot run pytest, ruff or pip. Write the files and stop.

## Files

- Create `src/mediacore/store.py`
- Modify `src/mediacore/__init__.py`
- Modify `pyproject.toml`
- Modify `src/mediacore/README.md`

## `pyproject.toml`

Three edits, nothing else:

```toml
version = "0.2.0"
```

```toml
[project.optional-dependencies]
dev = ["pytest>=8.0", "ruff>=0.6", "boto3>=1.34", "moto[s3]>=5.0"]
s3 = ["boto3>=1.34"]
```

`boto3` is named in both rather than `dev` depending on `mediacore[s3]`: a
self-referential extra resolves differently across pip versions, and this is a
two-word duplication. `moto[s3]` is the s3 test double — it intercepts botocore below
the HTTP layer, so the suite needs no network and no credentials.

## `src/mediacore/store.py`

Module docstring: *"URI-addressed bundle store (INTEGRATION.md §5.1). Where bundles sit
between the source and the consumers, addressed by a URI so the local→hosted move is
configuration and not code. `file://` is §5's bundle folder generalised to a directory
of bundle directories; `s3://` is the same layout under a key prefix. Entries are
versioned by `exported_at` and are never overwritten or deleted."*

Constants at the top:

```python
# Store URI schemes
STORE_SCHEME_FILE = "file"
STORE_SCHEME_S3 = "s3"
FILE_SCHEME_LOCAL_HOSTS = ("", "localhost")

# Entry layout: <root>/<record ULID>/<exported_at, ISO basic>/<slug>/
ENTRY_TIMESTAMP_FORMAT = "%Y%m%dT%H%M%SZ"
ENTRY_DEPTH = 3

# Provenance carrying the record identity (INTEGRATION.md §4)
VINYLCAT_PROVENANCE_KIND = "vinylcat"

# Slug: <artist>--<title>--<catalogue number>
SLUG_SEPARATOR = "--"
SLUG_WORD_SEPARATOR = "-"
SLUG_INVALID_PATTERN = r"[^a-z0-9]+"
```

`StoreError` — `class StoreError(Exception)`, docstring *"A problem with the store
itself, as distinct from `BundleError`, which is a problem with a bundle."*

`BundleEntry` — subclass `ContractModel` and add `model_config = ConfigDict(frozen=True)`
(pydantic merges it with the base's `extra="forbid"`):

```python
class BundleEntry(ContractModel):
    """One bundle in a store (INTEGRATION.md §5.1). Every field but `uri` is read from
    the entry's own release.json; `uri` is the address a consumer posts back."""

    model_config = ConfigDict(frozen=True)

    record_id: str
    exported_at: datetime
    slug: str
    uri: str
    schema_version: int
```

The slug, shared by the validated and the raw path — `list` must build an entry from a
`release.json` it has deliberately *not* validated (see `_entry_from_payload` below),
so both callers go through one derivation:

```python
def _slug_segment(value: str) -> str:
    folded = normalize_text(value).lower()
    return re.sub(SLUG_INVALID_PATTERN, SLUG_WORD_SEPARATOR, folded).strip(SLUG_WORD_SEPARATOR)


def _slug(artist: str, title: str, catalogue_number: str | None) -> str:
    parts = [artist, title, *( [catalogue_number] if catalogue_number else [] )]
    segments = [segment for segment in (_slug_segment(part) for part in parts) if segment]
    return SLUG_SEPARATOR.join(segments)


def bundle_slug(release: Release) -> str:
    """The directory (or key segment) name for a release's bundle."""
    catalogue_number = next(
        (label.catalogue_number for label in release.labels if label.catalogue_number), None
    )
    return _slug(release.artists[0].name, release.title, catalogue_number)
```

The rest of the module is prose — the executor writes it against the two test files
this level's plans 02 and 03 already put on disk.

**`_entry_from_payload(payload, uri) -> BundleEntry`.** Takes the raw `json.loads`
result of a `release.json`, never a validated `Release`: §5.1 requires `list` to return
an entry whose `schema_version` is newer than this install's, and `Release` is
`extra="forbid"`, so validating would refuse exactly the entry the spec says to list.
Pull `schema_version`, the `vinylcat` provenance entry's `id` and `exported_at`, and
the slug via `_slug` on `artists[0]["name"]`, `title` and the first non-empty
`labels[].catalogue_number`. Anything missing or the wrong type raises `StoreError`
naming `uri` and what was missing. Guard every lookup — this parses a file that may
have been hand-edited.

**`_entry_from_release(release, uri) -> BundleEntry`.** The `put` side: the same five
values off a validated `Release`, using `bundle_slug`. A release with no `vinylcat`
provenance raises `StoreError`.

**`_layout_parts(entry) -> tuple[str, str, str]`.** `(record_id, exported_at formatted
with ENTRY_TIMESTAMP_FORMAT after conversion to UTC, slug)` — the three path or key
segments below the root. A naive `exported_at` is treated as UTC. Both backends use
this, so the two layouts cannot drift.

**`_selected(entries, *, all_versions) -> list[BundleEntry]`.** Sort by `exported_at`
descending, then `record_id`, and when `all_versions` is false keep only the first
entry seen per `record_id`. Both backends use it.

**`_import_boto3()`.** Imports and returns the `boto3` module, raising `StoreError`
telling the caller to install `mediacore[s3]` when it is not present. It exists as its
own function so the s3 backend never imports boto3 at module scope — `mediacore` must
import cleanly without the extra — and so a test can monkeypatch it. Plan 07's backend
calls it; write the function now and leave it unused.

**`BundleStore`.** An `abc.ABC` with exactly the three abstract methods §5.1 names:

```python
class BundleStore(ABC):
    @abstractmethod
    def list(self, *, all_versions: bool = False) -> list[BundleEntry]: ...

    @abstractmethod
    def open(self, entry: BundleEntry | str, *, verify: bool = True) -> Release: ...

    @abstractmethod
    def put(self, release: Release, files: Mapping[str, Path]) -> BundleEntry: ...
```

`open` takes a `BundleEntry` **or its `uri` string**: §5.1's consumer flow posts
`{entry_uri}` to `preview-from-store`, so a consumer holds the address and not the
object. That is one argument type, not a fourth method.

**`FileBundleStore(BundleStore)`.** Constructed from a root `Path` and the store URI.

- `list` — raise `StoreError` naming the path when the root is not a directory.
  Otherwise take `sorted(root.glob("*/*/*/" + BUNDLE_RELEASE_FILENAME))`, read each
  with `json.loads`, build an entry with `_entry_from_payload` and the bundle
  directory's `as_uri()`, and return `_selected(...)`. Anything at the root that is not
  an entry at that depth is simply not matched by the glob.
- `open` — resolve the argument to a directory (an entry's `uri`, or the string form),
  raise `StoreError` if the URI is not a `file://` URI under this root or the directory
  holds no bundle, then `return read_bundle(path, verify=verify)`. Let `BundleError`
  through unchanged.
- `put` — build the entry with `_entry_from_release`, join `_layout_parts` onto the
  root, raise `StoreError` naming the existing entry if the destination already exists,
  `mkdir(parents=True, exist_ok=True)` the parent, call `write_bundle(release, dest,
  files)`, and return the entry with `uri` set to `dest.as_uri()`. Nothing here deletes
  or overwrites; `write_bundle`'s own atomicity covers a failure mid-write.

**`open_store(uri) -> BundleStore`.** Split with `urllib.parse.urlsplit`. `file` with a
netloc in `FILE_SCHEME_LOCAL_HOSTS` gives a `FileBundleStore` over
`Path(unquote(parts.path))`; a foreign netloc raises `StoreError`. Every other scheme,
including an empty one, raises `StoreError` naming what was given — and for the empty
case the message says to write a `file://` URI. Plan 07 adds the `STORE_SCHEME_S3`
branch; write the dispatch so adding it is one more branch.

## `src/mediacore/__init__.py`

Set `__version__ = "0.2.0"` and re-export `BundleEntry`, `BundleStore`, `StoreError`,
`bundle_slug` and `open_store` from `.store`, adding each to `__all__` in the order
that file already uses.

## `src/mediacore/README.md`

Add a `store.py` bullet after the `bundle.py` one:

> - `store.py` — the URI-addressed bundle store (§5.1). `open_store(uri) -> BundleStore`
>   picks the backend from the scheme (`file`, `s3`); anything else raises `StoreError`.
>   A `BundleStore` has three methods and nothing else:
>   `list(*, all_versions=False) -> list[BundleEntry]`,
>   `open(entry, *, verify=True) -> Release` — `entry` is a `BundleEntry` **or its own
>   `uri` string**, which is what a consumer posts back — and
>   `put(release, files) -> BundleEntry`, `files` being the same `{sha256: Path}`
>   mapping `write_bundle` takes.
>   - `BundleEntry { record_id, exported_at, slug, uri, schema_version }` — frozen,
>     `extra="forbid"`. `record_id` and `exported_at` are read from the entry's own
>     `release.json`, from the `provenance` entry whose `kind` is `"vinylcat"` (§4),
>     never parsed out of its path; `slug` is `bundle_slug(release)`; `uri` is the
>     entry's address.
>   - Layout `<root>/<record ULID>/<exported_at as `%Y%m%dT%H%M%SZ`>/<slug>/`, holding
>     a §5 bundle. A re-export is a new version beside the old one; `list()` returns the
>     latest per record, newest first, `all_versions=True` the rest. **Nothing here
>     overwrites or deletes an entry** — `put` on an existing address raises
>     `StoreError`.
>   - `open` verifies exactly as `read_bundle` does and lets `BundleError` through:
>     hashes, audio sizes, and a `schema_version` newer than this install's, the last
>     of those even with `verify=False`. `list` does **not** refuse such an entry — it
>     is returned with its own `schema_version` so a consumer page can offer an upgrade
>     instead of hiding it — which is why `list` builds entries from the raw
>     `release.json` payload and never validates a `Release`.
>   - `StoreError` is the store's own failure (unusable URI, missing root, an entry
>     that is not addressable, a `put` that would overwrite, a `release.json` that
>     cannot become an entry). `BundleError` stays the bundle's.
>   - Also `bundle_slug(release) -> str` — `<artist>--<title>--<catalogue number>`,
>     each segment folded through `normalize_text`, lowercased, and every run outside
>     `[a-z0-9]` collapsed to `-`. It reproduces the slug vinylCatalogue records for a
>     record (§11), but nothing addresses an entry by slug: `record_id` and `uri` do
>     that, so a divergence is cosmetic.
>   - Depends on two contracts no import reveals: a bundle's `release.json` carrying a
>     `provenance` entry with `kind == "vinylcat"` (written by vinylCatalogue's adapter,
>     §6), and — for `s3://` — `boto3` from the optional extra `mediacore[s3]` plus the
>     ambient boto3 credential chain. `mediacore` itself takes no keys.
