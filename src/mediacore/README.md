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
    `MediaFile`'s are.
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
  parses `release.json` and, when `verify`, checks every referenced file exists and
  hashes to its `sha256`; every path is resolved under `<bundle>/media/` and one that
  escapes raises `BundleError`. That containment check is unreachable through the
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
- `fixtures.py` — `its_saxy_bundle() -> Path`, the directory of the committed IT'S SAXY
  bundle, so consumer suites never hard-code a path. Depends on two things no import
  reveals: the repo-root `fixtures/its-saxy/` directory produced by
  `scripts/make_fixture_its_saxy.py`, and `pyproject.toml`'s
  `[tool.hatch.build.targets.wheel.force-include]` mapping `fixtures` to
  `mediacore/_fixtures` — the checkout copy wins, the packaged copy is the fallback for
  an installed wheel. Raises `FileNotFoundError` when neither is present.
