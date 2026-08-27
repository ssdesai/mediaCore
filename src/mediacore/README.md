# mediacore

The contract package: the neutral `Release` schema, refs (evidence recorded by external
sources), the shared name-matching fold, bundle I/O, and the path to the committed test
fixture.
`INTEGRATION.md` §3–5 is the specification; this folder is its implementation, and
nothing medium-specific belongs here.

Consumers import the public surface from the package root — `from mediacore import
Release, read_bundle, normalize_text` — never from a submodule.

- `__init__.py` — re-exports every public name and sets `__version__`. The submodule
  layout is an implementation detail; this is the surface `INTEGRATION.md` pins.
- `release.py` — the wire models (§3), all `extra="forbid"` and all round-tripping
  through `model_dump(mode="json")` / `model_validate` without loss:
  - `Release { schema_version, refs, provenance, title, artists, labels, year,
    released, country, medium, format, genres, styles, tracks, credits, notes, tags,
    media, audio, links }` — the on-disk `release.json` shape.
  - `ArtistRef { name, sort_name, refs }`
  - `LabelRef { name, catalogue_number, refs }`
  - `Track { position, title, duration, credits }`
  - `Credit { role, name, refs }`
  - `MediaFile { kind, role, sha256, file, mime, source_url, refs }` — `kind` is
    `"photo" | "external_photo"`; `sha256` is a lowercase 64-character hex digest
    (`Sha256Hex`), and `file` is **validated** to be exactly
    `media/<that same digest>.<ext>` with `<ext>` matching `[a-z0-9]{1,8}`
    (`validate_bundle_file`, `BUNDLE_FILE_RE`). A mismatched pair raises
    `ValidationError`, so a consumer may join `file` onto the bundle root safely — the
    shape admits no path separator, no `..`, and no absolute path. Both consumers take
    bundles from untrusted browser uploads, which is why this is enforced rather than
    merely documented.
  - `AudioFile { track_position, sha256, file, format, size_bytes }` — joined to its
    `Track` by `track_position`; `sha256` and `file` are validated exactly as
    `MediaFile`'s are; `size_bytes` requires `>= 0`.
  - `Link { label, url, refs }` — `refs` is the evidence saying which entity the link
    is *about*.
  - `Provenance { kind, id, label, exported_at }` — where this copy came from:
    evidence of a different kind, carrying no more authority than any other ref.
  - `Medium` = `"vinyl" | "cd" | "cassette" | "digital" | "other"`; `MediaKind` =
    `"photo" | "external_photo"`; `SCHEMA_VERSION` = 1; `ContractModel` is the shared
    `extra="forbid"` base; `MIN_ARTISTS` = 1. Also `BUNDLE_MEDIA_DIRNAME` (`"media"` —
    defined here and imported by `bundle.py`, so the directory name has one
    definition), `SHA256_HEX_PATTERN`, `BUNDLE_FILE_EXTENSION_PATTERN`,
    `BUNDLE_FILE_PATTERN`, `BUNDLE_FILE_RE`, `Sha256Hex`, and
    `validate_bundle_file(sha256, file)`.
  - `Release` also carries two cross-entry `model_validator`s the single-entry checks
    above can't express, since each needs the whole `media`/`audio`/`tracks` lists:
    (1) every `sha256` shared by two or more `media`/`audio` entries must name the
    *same* `file` — content addressing means one digest, one file, checked across
    both lists together; (2) every `AudioFile.track_position` must equal some
    `Track.position` — an audio file matching no track is rejected as an orphan
    rather than silently passed through. Both raise `ValidationError` on
    `Release(...)` and on `Release.model_validate(...)` alike.
- `refs.py` — the evidence grammar (§4). A ref records what some external source calls
  an entity; **it is never that entity's identity.** Every `refs` field is optional and
  defaults to `{}`, no ref is required, no source is privileged, and nothing here
  enforces uniqueness — two entities may legitimately carry the same ref, and a consumer
  uses refs only to *propose* candidates and to *retain evidence* on the row it links or
  creates. `Refs` is
  `Annotated[dict[str, str], AfterValidator(validate_refs)]`: keys match
  `REF_KEY_PATTERN` (`^[a-z][a-z0-9]*:[a-z][a-z0-9-]*$`), values are non-empty strings.
  Exports `validate_ref_key`, `validate_ref_value`, `validate_refs`, `ref_uri(key,
  value) -> "<key>:<value>"`, `parse_ref_uri(uri) -> (key, value)`, `KNOWN_REF_KEYS`,
  and one constant per known key: `DISCOGS_RELEASE`, `DISCOGS_MASTER`, `DISCOGS_ARTIST`,
  `DISCOGS_LABEL`, `MUSICBRAINZ_RELEASE`, `MUSICBRAINZ_RELEASE_GROUP`,
  `MUSICBRAINZ_ARTIST`, `MUSICBRAINZ_LABEL`, `MUSICBRAINZ_RECORDING`, `ISRC_RECORDING`,
  `BARCODE_RELEASE` — eleven in all. An unknown but well-formed key is accepted on
  purpose — that is the extension point. `isrc:recording` and `barcode:release` are
  reserved: nothing produces them yet. They carry entity segments because the grammar
  requires one; an earlier draft of §4 listed them as bare `isrc` / `barcode`, which
  the grammar cannot express, and the grammar won.
- `normalize.py` — `normalize_text(value) -> str` (NFKD, drop combining marks,
  uppercase, collapse whitespace, strip) and `normalize_catno(value) -> str`
  (`normalize_text` then strip every non-`[A-Z0-9]` character). Must stay byte-for-byte
  equivalent to `vinylcat.normalize` in the vinylCatalogue repo — every consumer's
  no-refs fallback matches on it, so a divergence silently stops matching entities the
  source repo considers identical. `tests/test_normalize.py` pins the shared samples.
- `bundle.py` — the on-disk format (§5). `read_bundle(path, *, verify=True) -> Release`
  parses `release.json`, rejects a `schema_version` newer than this install's
  `SCHEMA_VERSION` (naming both versions and telling the caller to upgrade
  `mediacore` — a forward-compatibility guard, not a `verify` check, so it runs even
  with `verify=False`) and, when `verify`, checks every referenced file exists,
  hashes to its `sha256`, and — for each `AudioFile` — that its actual byte size on
  disk equals `size_bytes`; every path is resolved under `<bundle>/media/` and one
  that escapes raises `BundleError`. That containment check is unreachable through the
  models — `MediaFile`/`AudioFile` already forbid such a `file` — and exists for the
  one case the contract cannot cover: a hand-edited `release.json` arriving as an
  untrusted upload.
  `write_bundle(release, dest, files) -> Path` takes a `{sha256: source path}` mapping,
  validates the whole mapping before touching `dest`, then **stages into a sibling
  temporary directory and swaps it into place**, so an interrupted export leaves either
  the previous bundle intact or nothing — never a half-written directory that the
  bundle guard would then refuse to overwrite. It refuses a non-empty destination
  holding no `release.json` without mutating it, so a mistyped path is never deleted.
  Also `sha256_file(path)`, `bundle_entries(release)` (the single walk both directions
  share), `BUNDLE_RELEASE_FILENAME`, `BUNDLE_MEDIA_DIRNAME` (re-exported from
  `release.py`), and `BundleError`.
- `store.py` — the URI-addressed bundle store (§5.1). `open_store(uri) -> BundleStore`
  picks the backend from the scheme (`file`, `s3`); anything else raises `StoreError`.
  A `BundleStore` has three methods and nothing else:
  `list(*, all_versions=False) -> list[BundleEntry]`,
  `open(entry, *, verify=True) -> Release` — `entry` is a `BundleEntry` **or its own
  `uri` string**, which is what a consumer posts back — and
  `put(release, files) -> BundleEntry`, `files` being the same `{sha256: Path}`
  mapping `write_bundle` takes.
  - `BundleEntry { record_id, exported_at, slug, uri, schema_version }` — frozen,
    `extra="forbid"`. `record_id` and `exported_at` are read from the entry's own
    `release.json`, from the `provenance` entry whose `kind` is `"vinylcat"` (§4),
    never parsed out of its path; `slug` is `bundle_slug(release)`; `uri` is the
    entry's address.
  - Layout `<root>/<record ULID>/<exported_at as `%Y%m%dT%H%M%SZ`>/<slug>/`, holding
    a §5 bundle. A re-export is a new version beside the old one; `list()` returns the
    latest per record, newest first, `all_versions=True` the rest. **Nothing here
    overwrites or deletes an entry** — `put` on an existing address raises
    `StoreError`.
  - `open` verifies exactly as `read_bundle` does and lets `BundleError` through:
    hashes, audio sizes, and a `schema_version` newer than this install's, the last
    of those even with `verify=False`. `list` does **not** refuse such an entry — it
    is returned with its own `schema_version` so a consumer page can offer an upgrade
    instead of hiding it — which is why `list` builds entries from the raw
    `release.json` payload and never validates a `Release`.
  - `StoreError` is the store's own failure (unusable URI, missing root, an entry
    that is not addressable, a `put` that would overwrite, a `release.json` that
    cannot become an entry). `BundleError` stays the bundle's.
  - The store root is a containment boundary, because §5.1's consumer flow posts an
    entry `uri` back from a browser (`preview-from-store {entry_uri}`): `open` resolves
    the URI before checking it against the root, so neither a `..` segment nor a
    symlinked entry can address anything outside the store, and `put` refuses a
    `record_id` that is not a single path segment. On `s3://`, a key that would land
    outside the temp directory it downloads into is refused the same way, and a prefix
    holding objects but no `release.json` raises `StoreError` — the same exception the
    `file://` backend raises for the same fault.
  - Also `bundle_slug(release) -> str` — `<artist>--<title>--<catalogue number>`,
    each segment folded through `normalize_text`, lowercased, and every run outside
    `[a-z0-9]` collapsed to `-`. It reproduces the slug vinylCatalogue records for a
    record (§11), but nothing addresses an entry by slug: `record_id` and `uri` do
    that, so a divergence is cosmetic.
  - Depends on two contracts no import reveals: a bundle's `release.json` carrying a
    `provenance` entry with `kind == "vinylcat"` (written by vinylCatalogue's adapter,
    §6), and — for `s3://` — `boto3` from the optional extra `mediacore[s3]` plus the
    ambient boto3 credential chain. `mediacore` itself takes no keys.
  - `s3://` is the same layout under a key prefix, over a `boto3` client built from the
    ambient credential chain with no key, region or endpoint argument of its own.
    `boto3` is imported lazily through one seam, so `import mediacore` works without the
    optional `mediacore[s3]` extra and asking for an `s3://` store without it raises
    `StoreError` naming the extra. `open` downloads an entry into a temporary directory
    and reads it with `read_bundle`, so every §5 check has one implementation; `put`
    stages with `write_bundle` and uploads `release.json` **last**, which is the
    `s3://` substitute for the `file://` atomic swap — an interrupted upload leaves
    objects that `list` never matches instead of a listable entry with missing media.
    `S3_LIST_PAGE_SIZE` bounds the `list_objects_v2` pagination.
- `fixtures.py` — `its_saxy_bundle() -> Path`, the directory of the committed IT'S SAXY
  bundle, so consumer suites never hard-code a path. Depends on two things no import
  reveals: the repo-root `fixtures/its-saxy/` directory produced by
  `scripts/make_fixture_its_saxy.py`, and `pyproject.toml`'s
  `[tool.hatch.build.targets.wheel.force-include]` mapping `fixtures` to
  `mediacore/_fixtures` — the checkout copy wins, the packaged copy is the fallback for
  an installed wheel. Raises `FileNotFoundError` when neither is present.
  `seed_its_saxy_store(store_uri) -> BundleEntry` is the §5.1 "Fixture" bullet's
  implementation ("Each dev stack seeds *IT'S SAXY* into a local `file://` store, so
  the store path is exercised by tests and not only by upload") — it reads the
  committed bundle and `put`s it into `open_store(store_uri)`. Idempotent: before
  putting, it checks `list(all_versions=True)` for an entry already carrying this
  record's `record_id` and `exported_at`, and returns that instead of putting again, so
  a dev stack can reseed on every restart without error. A `StoreError` from an
  unusable `store_uri` or a `BundleError` from a damaged checkout propagates
  unchanged.
