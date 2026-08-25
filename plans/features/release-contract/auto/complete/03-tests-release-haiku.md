# Tests: the `Release` schema

Feature `release-contract` (plan 3 of 12). The batch delivers the whole `mediacore`
contract package — the `Release` schema, refs, the normalize fold, the bundle
reader/writer — plus the *IT'S SAXY* fixture bundle and its generator.

Write `tests/test_release.py`, the level-1 unit tests for `src/mediacore/release.py`
(written by plan 06).

Depends on: `01-acceptance-tests-sonnet.md` — it owns `tests/conftest.py` and this file
uses its builders by name. Do not add anything to `conftest.py`.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below (none —
`tests/README.md` is written by plan 01 and already describes this file).

## Pinned facts

- Package `mediacore`, src layout. Import from the package root:
  `from mediacore import ArtistRef, AudioFile, Credit, LabelRef, Link, MediaFile,
  Provenance, Release, Track`. Never import from a submodule. The module does not exist
  yet — plan 06 writes it; write the tests against the shapes below.
- `tests/conftest.py` (plan 01) provides `sha256_bytes(data)`, `make_release(**overrides)`,
  `make_media_file(data, *, ext="png", **overrides)`,
  `make_audio_file(data, *, position="A1", fmt="wav", **overrides)`, and the constants
  `SAMPLE_EXPORTED_AT`, `SAMPLE_RECORD_ID`, `SAMPLE_RELEASE_REFS`, `SAMPLE_ARTIST_REFS`.
  Import them as `from conftest import ...` is **not** needed — they are module-level
  functions in `conftest.py`, so import them with `from conftest import make_release, ...`
  (pytest puts `tests/` on `sys.path` via rootdir conftest collection).
- The §3 shapes, verbatim:

```
Release     { schema_version: int = 1, refs, provenance: list[Provenance], title: str,
              artists: list[ArtistRef] (>= 1), labels: list[LabelRef], year: int | None,
              released: str | None, country: str | None, medium: Medium,
              format: str | None, genres: list[str], styles: list[str],
              tracks: list[Track], credits: list[Credit], notes: str | None,
              tags: list[str], media: list[MediaFile], audio: list[AudioFile],
              links: list[Link] }
ArtistRef   { name: str, sort_name: str | None, refs }
LabelRef    { name: str, catalogue_number: str | None, refs }
Track       { position: str, title: str, duration: str | None, credits: list[Credit] }
Credit      { role: str, name: str, refs }
MediaFile   { kind: "photo" | "external_photo", role: str | None, sha256: str,
              file: str, mime: str, source_url: str | None, refs }
AudioFile   { track_position: str, sha256: str, file: str, format: str, size_bytes: int }
Link        { label: str, url: str, refs }
Provenance  { kind: str, id: str, label: str | None, exported_at: datetime }
Medium      = "vinyl" | "cd" | "cassette" | "digital" | "other"
refs        = dict[str, str], keys matching ^[a-z][a-z0-9]*:[a-z][a-z0-9-]*$, values
              non-empty strings; defaults to {} everywhere it appears
```

- Every model is `extra="forbid"`. Every list field defaults to `[]`; every `| None`
  field defaults to `None`; `schema_version` defaults to `1`.
- Pydantic v2: construction failures raise `pydantic.ValidationError`; dump with
  `model_dump(mode="json")`, load with `Release.model_validate(...)`.

## Files

- Create `tests/test_release.py`

## `tests/test_release.py`

Module docstring: *"Pins the `Release` contract (INTEGRATION.md §3). Every field a
consumer repo reads is asserted here; a field that round-trips wrong here is a bug in
three repos."*

Give the module a `full_release()` helper (or module-scoped fixture) that builds a
`Release` exercising **every** field: two provenance entries, two artists (one with a
`sort_name`), one label with a `catalogue_number`, `year=1974`, `released="1974-06"`,
`country`, `medium="vinyl"`, `format`, two genres, one style, two tracks (one with a
`Credit`), one release-level `Credit`, `notes`, two tags, one `MediaFile` of each
`kind` (build via `make_media_file`), one `AudioFile` (via `make_audio_file`), and two
`Link`s. Use `make_release(**...)` for it so the shared defaults stay in one place.

Tests:

- `test_release_round_trips` — `Release.model_validate(full.model_dump(mode="json"))
  == full`, and `json.dumps(full.model_dump(mode="json"))` succeeds (the dump is plain
  JSON, no `datetime` objects left).
- `test_schema_version_defaults_to_one` — `make_release().schema_version == 1`, and it
  survives the round-trip.
- `test_provenance_datetime_round_trips` — after a JSON round-trip the `exported_at` is
  still `SAMPLE_EXPORTED_AT` and is timezone-aware; in the dumped JSON it is a string.
- `test_optional_fields_default` — on `make_release()`: `year`, `released`, `country`,
  `format`, `notes` are all `None`, and `labels`, `genres`, `styles`, `tracks`,
  `credits`, `tags`, `media`, `audio`, `links` are all `[]`. Also `refs == {}` on an
  `ArtistRef` built with only a `name`, and `sort_name is None`.
- `test_extra_fields_forbidden_on_release` — `make_release(surprise="x")` raises
  `ValidationError`.
- `test_extra_fields_forbidden_on_nested_models` — parametrized over the nested models:
  `Track(position="A1", title="t", surprise="x")`, `Credit(role="r", name="n",
  surprise="x")`, `ArtistRef(name="n", surprise="x")`, `LabelRef(name="n",
  surprise="x")`, `Link(label="l", url="u", surprise="x")`, `Provenance(kind="k",
  id="i", exported_at=SAMPLE_EXPORTED_AT, surprise="x")` — each raises
  `ValidationError`.
- `test_at_least_one_artist_required` — `make_release(artists=[])` raises
  `ValidationError`.
- `test_medium_vocabulary_is_closed` — each of `"vinyl"`, `"cd"`, `"cassette"`,
  `"digital"`, `"other"` is accepted; `"8-track"` and `"Vinyl"` each raise.
- `test_media_kind_vocabulary_is_closed` — `"photo"` and `"external_photo"` are
  accepted; `"scan"` raises.
- `test_nested_refs_are_validated` — parametrized: an invalid ref key
  (`{"Discogs:artist": "1"}`) raises `ValidationError` when passed to `ArtistRef`,
  `LabelRef`, `Credit`, `MediaFile`, `Link`, and `Release` itself; an empty ref value
  (`{"discogs:artist": ""}`) likewise on `Credit`.
- `test_track_credits_are_nested_models` — a `Track` built from a plain dict for its
  credit yields a `Credit` instance, and the credit's `refs` survive the round-trip.
- `test_required_fields_are_required` — parametrized: `AudioFile` without `format`,
  `MediaFile` without `mime`, `Track` without `title`, `Link` without `url`, and
  `Release` without `title` each raise `ValidationError`.
