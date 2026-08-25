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
    `"photo" | "external_photo"`; `file` is `media/<sha256>.<ext>`. That naming is a
    **producer obligation, not a validated one**: no model or `bundle.py` check ties
    `file` to `sha256`, so a producer that emits a mismatched pair is accepted here and
    only `tests/test_fixture.py::test_every_bundle_file_hashes_to_its_name` catches it,
    for the fixture alone. A consumer must not derive the path from `sha256` (or the
    hash from the path) without checking both.
  - `AudioFile { track_position, sha256, file, format, size_bytes }` — joined to its
    `Track` by `track_position`.
  - `Link { label, url, refs }` — `refs` is the evidence saying which entity the link
    is *about*.
  - `Provenance { kind, id, label, exported_at }` — where this copy came from:
    evidence of a different kind, carrying no more authority than any other ref.
  - `Medium` = `"vinyl" | "cd" | "cassette" | "digital" | "other"`; `MediaKind` =
    `"photo" | "external_photo"`; `SCHEMA_VERSION` = 1; `ContractModel` is the shared
    `extra="forbid"` base; `MIN_ARTISTS` = 1.
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
  `MUSICBRAINZ_ARTIST`, `MUSICBRAINZ_LABEL`, `MUSICBRAINZ_RECORDING`. An unknown but
  well-formed key is accepted on purpose — that is the extension point.
  **Open contradiction in the spec:** §4's table also lists `isrc` and `barcode` as
  reserved keys, but neither matches the grammar the same section states (no
  `<entity>` segment). The grammar is implemented as written and the two keys are left
  undefined rather than invented as `isrc:recording` / `barcode:release`. Settling this
  means either widening `REF_KEY_PATTERN` or giving them entity segments; do it before
  anything reserves them for real.
- `normalize.py` — `normalize_text(value) -> str` (NFKD, drop combining marks,
  uppercase, collapse whitespace, strip) and `normalize_catno(value) -> str`
  (`normalize_text` then strip every non-`[A-Z0-9]` character). Must stay byte-for-byte
  equivalent to `vinylcat.normalize` in the vinylCatalogue repo — every consumer's
  no-refs fallback matches on it, so a divergence silently stops matching entities the
  source repo considers identical. `tests/test_normalize.py` pins the shared samples.
- `bundle.py` — the on-disk format (§5). `read_bundle(path, *, verify=True) -> Release`
  parses `release.json` and, when `verify`, checks every referenced file exists and
  hashes to its `sha256`. `write_bundle(release, dest, files) -> Path` takes a
  `{sha256: source path}` mapping, validates the whole mapping before touching `dest`,
  then replaces `dest` wholesale — it refuses a non-empty destination that holds no
  `release.json`, so a mistyped path is never deleted. Also `sha256_file(path)`,
  `bundle_entries(release)` (the single walk both directions share),
  `BUNDLE_RELEASE_FILENAME`, `BUNDLE_MEDIA_DIRNAME`, and `BundleError`.
- `fixtures.py` — `its_saxy_bundle() -> Path`, the directory of the committed IT'S SAXY
  bundle, so consumer suites never hard-code a path. Depends on two things no import
  reveals: the repo-root `fixtures/its-saxy/` directory produced by
  `scripts/make_fixture_its_saxy.py`, and `pyproject.toml`'s
  `[tool.hatch.build.targets.wheel.force-include]` mapping `fixtures` to
  `mediacore/_fixtures` — the checkout copy wins, the packaged copy is the fallback for
  an installed wheel. Raises `FileNotFoundError` when neither is present.
