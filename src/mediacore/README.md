# mediacore

The contract package: the neutral `Release` schema, refs (evidence recorded by external
sources), the shared name-matching fold, bundle I/O, the URI-addressed bundle store, and
the path to the committed test fixture.
`INTEGRATION.md` §3–5.1 is the specification; this folder is its implementation, and
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
- `store.py` — the bundle store (§5.1): where bundles sit between the source and its
  consumers, addressed by a URI so the local→hosted move is configuration, not code.
  - `open_store(uri, *, s3_client=None) -> BundleStore` dispatches on the URI *scheme* —
    `file` → `FileBundleStore`, `s3` → `S3BundleStore`, anything else (including a bare
    path, which has no scheme) raises `StoreError`. That dispatch is the contract every
    consumer's `BUNDLE_STORE_URI` is read through; no caller names a backend class.
    `s3_client` injects a boto3-compatible client and exists so the `s3` backend can be
    tested offline; the `file` backend ignores it.
  - `BundleEntry { record_id, exported_at, slug, uri, schema_version }` — one bundle in a
    store, returned by `list` and `put` and accepted by `open`, and the shape both
    consumers' `InboxEntryOut` is built from. A `ContractModel`, so it round-trips through
    `model_dump(mode="json")`. **Every field is read from the entry's own `release.json`,
    never parsed out of its key**: `record_id` and `exported_at` are the *first*
    `provenance` entry's `id` and `exported_at` (not a `kind`-matched one — nothing
    vinyl-specific lives here), `slug` is derived by `release_slug`, `schema_version` is
    the bundle's own and may be *newer* than this install understands, and `uri` is the
    entry's own address — what a consumer posts back to pick it.
  - `BundleStore` — the three public methods of §5.1 and nothing else. `list(*,
    all_versions=False)` returns the latest version per record, newest export first
    (`all_versions=True` for every version); it reads the four entry fields out of the
    raw JSON *without* model validation, so an entry written by a newer `mediacore` is
    listed with its `schema_version` rather than hidden. `open(entry, *, verify=True,
    dest=None)` goes through `read_bundle` instead — hashes, audio sizes, and a refusal
    naming the upgrade when `schema_version` is newer — and with `dest` materialises the
    whole bundle into that (absent or empty) directory. `put(release, files)` writes a
    new entry through `write_bundle` and returns it. There is no delete: nothing here
    overwrites or removes an entry.
  - The key layout is `<root>/<record ULID>/<exported_at, ISO basic>/<slug>/` — a
    re-export is a new version *beside* the old one, and `put` refuses a version key that
    already exists (`StoreError`) rather than replacing it. `release_slug(release)`
    derives `<artist>--<title>--<catalogue number>` over `normalize_text`. The record id
    is the one key segment that comes out of `release.json` unfiltered (`Provenance.id`
    is an unconstrained `str`), so `put` refuses one that is not a single segment — a
    `/`, `\`, `.` or `..` would otherwise walk `write_bundle` out of the store root.
  - `S3BundleStore` depends on two things no import shows: `boto3` is **not** a runtime
    dependency but the optional extra `mediacore[s3]` (a missing one raises `StoreError`
    naming the extra), and its client comes from the **ambient boto3 credential chain** —
    environment, shared config, or instance role. `mediacore` accepts no keys, holds
    none, and the browser never talks to the bucket. `release.json` is uploaded last, so
    an interrupted `put` leaves an entry `list` does not see.
  - Faults *inside* a bundle stay `BundleError` (hash, size, schema upgrade);
    `StoreError` covers store-level faults — an unusable URI, a malformed entry, an
    attempted overwrite, a record id that is not one key segment, and an `entry.uri` that
    is not an entry key of this store. Those last two are boundaries, not niceties: §5.1's
    `preview-from-store` posts the URI back from a browser, and a bundle reaching `put`
    may have arrived as an upload.
- `fixtures.py` — `its_saxy_bundle() -> Path`, the directory of the committed IT'S SAXY
  bundle, so consumer suites never hard-code a path. Depends on two things no import
  reveals: the repo-root `fixtures/its-saxy/` directory produced by
  `scripts/make_fixture_its_saxy.py`, and `pyproject.toml`'s
  `[tool.hatch.build.targets.wheel.force-include]` mapping `fixtures` to
  `mediacore/_fixtures` — the checkout copy wins, the packaged copy is the fallback for
  an installed wheel. Raises `FileNotFoundError` when neither is present.
  `seed_its_saxy_store(store_uri) -> BundleEntry` puts that bundle into the store at
  `store_uri` (§5.1, "Fixture") and is idempotent — a stack re-running its seed gets the
  entry that is already there, which is what keeps seeding compatible with the
  no-overwrite rule. It lives in the package, not in `scripts/`, because the dev stacks
  that call it (vinylCatalogue, humanNetworkMap, musicMap) install `mediacore` as a wheel
  and have no access to this repo's scripts.
