# Acceptance tests for the release contract

Feature `release-contract` (plan 1 of 12). The batch delivers the whole
`mediacore` contract package — the `Release` schema, refs, the normalize fold, the
bundle reader/writer — plus the *IT'S SAXY* fixture bundle and its generator.

Write the batch's black-box acceptance test: load `fixtures/its-saxy/` through the
package's public API and assert every fact `INTEGRATION.md` §11 states, plus the shared
test builders the other tests plans use.

Independent of other plans. **This test file is RED for the whole build and that is
expected**: the bytes under `fixtures/its-saxy/` are produced by
`scripts/make_fixture_its_saxy.py`, which build executors cannot run (no bash). The
level-2 gate and the batch's verify plan run it. Do not create any file under
`fixtures/its-saxy/`.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- Package `mediacore`, src layout (`src/mediacore/`), installed editable. Import the
  public surface from the package root: `from mediacore import Release, read_bundle, ...`
  — never from a submodule.
- Public names this file uses: `read_bundle(path, *, verify=True) -> Release`,
  `BundleError`, `its_saxy_bundle() -> Path`, and the models `Release`, `Provenance`,
  `MediaFile`, `AudioFile`. None of them exist on disk yet — plans 05–07 write them.
- A bundle directory is `release.json` + `media/<sha256>.<ext>` (INTEGRATION.md §5).
  `read_bundle` with `verify=True` (the default) hashes every referenced file.
- `its_saxy_bundle()` returns the `fixtures/its-saxy/` directory.
- Pydantic v2: dump with `model_dump(mode="json")`.
- Tests live in `tests/`, mirroring `src/`; the suite is run with
  `.venv/bin/python -m pytest -q` from the repo root.

## Files

- Create `tests/conftest.py`
- Create `tests/test_fixture.py`
- Create `tests/README.md`

## `tests/conftest.py`

Shared builders. This plan owns the file; `tests/test_release.py` and
`tests/test_bundle.py` (plan 04) import these by name and must not add their own.

```python
"""Shared builders for the mediacore test suite.

Owned by plan 01 of the release-contract batch: tests/test_release.py and
tests/test_bundle.py use these by name rather than defining their own.
"""

from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from mediacore import AudioFile, MediaFile, Provenance, Release

# A fixed instant, so nothing in the suite depends on the clock.
SAMPLE_EXPORTED_AT = datetime(2026, 1, 2, 3, 4, 5, tzinfo=timezone.utc)
SAMPLE_RECORD_ID = "01M08WYYQGY1S66KY425FYCBS7"
SAMPLE_RELEASE_REFS = {"discogs:release": "16853262"}
SAMPLE_ARTIST_REFS = {"discogs:artist": "5682050"}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def make_release(**overrides: Any) -> Release:
    """A minimal valid Release — one artist, no files — with any field overridden."""
    fields: dict[str, Any] = {
        "refs": dict(SAMPLE_RELEASE_REFS),
        "provenance": [
            Provenance(
                kind="vinylcat",
                id=SAMPLE_RECORD_ID,
                label="Test",
                exported_at=SAMPLE_EXPORTED_AT,
            )
        ],
        "title": "IT'S SAXY",
        "artists": [{"name": "The Duke's Combo", "refs": dict(SAMPLE_ARTIST_REFS)}],
        "medium": "vinyl",
    }
    fields.update(overrides)
    return Release(**fields)


def make_media_file(data: bytes, *, ext: str = "png", **overrides: Any) -> MediaFile:
    digest = sha256_bytes(data)
    fields: dict[str, Any] = {
        "kind": "photo",
        "role": "label_a",
        "sha256": digest,
        "file": f"media/{digest}.{ext}",
        "mime": "image/png",
    }
    fields.update(overrides)
    return MediaFile(**fields)


def make_audio_file(
    data: bytes, *, position: str = "A1", fmt: str = "wav", **overrides: Any
) -> AudioFile:
    digest = sha256_bytes(data)
    fields: dict[str, Any] = {
        "track_position": position,
        "sha256": digest,
        "file": f"media/{digest}.{fmt}",
        "format": fmt,
        "size_bytes": len(data),
    }
    fields.update(overrides)
    return AudioFile(**fields)


def write_source_files(directory: Path, payloads: dict[str, bytes]) -> dict[str, Path]:
    """Write each payload under `directory`; return the {sha256: path} mapping
    `write_bundle` takes as its `files` argument."""
    directory.mkdir(parents=True, exist_ok=True)
    mapping: dict[str, Path] = {}
    for name, data in payloads.items():
        path = directory / name
        path.write_bytes(data)
        mapping[sha256_bytes(data)] = path
    return mapping
```

## `tests/test_fixture.py`

The acceptance test. Structure: a module-scoped `bundle_dir` fixture returning
`its_saxy_bundle()`, and a module-scoped `release` fixture returning
`read_bundle(bundle_dir)` — the default `verify=True` is itself the "every file hashes"
assertion. Do **not** `pytest.skip` when the bundle is absent; a missing fixture must
fail, because generating it is the batch's deliverable.

Every expected value below is a module-level named constant (CONVENTIONS.md → named
constants), taken verbatim from `INTEGRATION.md` §11. Use exactly these:

```python
DISCOGS_RELEASE_ID = "16853262"
DISCOGS_ARTIST_ID = "5682050"
DISCOGS_LABEL_ID = "1504762"
VINYLCAT_RECORD_ID = "01M08WYYQGY1S66KY425FYCBS7"
FIXTURE_EXPORTED_AT = datetime(2026, 8, 25, 0, 0, 0, tzinfo=timezone.utc)
RELEASE_FILENAME = "release.json"
MEDIA_DIRNAME = "media"
EXPECTED_TITLE = "IT'S SAXY"
EXPECTED_ARTIST_NAME = "The Duke's Combo"
EXPECTED_ARTIST_SORT_NAME = "Duke's Combo, The"
EXPECTED_LABEL_NAME = "A. A. E."
EXPECTED_CATALOGUE_NUMBER = "SAAE 1012"
EXPECTED_COUNTRY = "South Africa"
EXPECTED_MEDIUM = "vinyl"
EXPECTED_FORMAT = "Vinyl, LP, Album"
EXPECTED_GENRES = [
    "Jazz",
    "Rock",
    "Funk / Soul",
    "Blues",
    "Folk, World, & Country",
    "Stage & Screen",
]
EXPECTED_TRACKS = [
    ("A1", "LOVE GROWS"),
    ("A2", "ALL I HAVE TO DO IS DREAM"),
    ("A3", "JY IS MY LIEFLING"),
    ("A4", "I'LL NEVER FALL IN LOVE AGAIN"),
    ("A5", "DOMINIQUE"),
    ("A6", "THERESA"),
    ("B1", "SUGAR SUGAR"),
    ("B2", "Love Theme From Romeo And Juliet"),
    ("B3", "SEEMAN"),
    ("B4", "MAKE ME AN ISLAND"),
    ("B5", "MA BELLE AMIE"),
    ("B6", "LOVE IS A BEAUTIFUL SONG"),
]
EXPECTED_TRACK_CREDITS = {
    "B5": ("Written-By", "peter tetteroo", "282874"),
    "B6": ("Written-By", "Terry Dempsey", "1033325"),
}
EXPECTED_PHOTO_ROLES = ["label_a", "label_b"]
EXPECTED_EXTERNAL_PHOTO_COUNT = 2
EXPECTED_AUDIO_FORMAT = "wav"
EXPECTED_LINKS = [
    ("Discogs: IT'S SAXY",
     "https://www.discogs.com/release/16853262-The-Dukes-Combo-Its-Saxy",
     {"discogs:release": "16853262"}),
    ("Discogs: The Duke's Combo",
     "https://www.discogs.com/artist/5682050",
     {"discogs:artist": "5682050"}),
    ("Discogs: A. A. E.",
     "https://www.discogs.com/label/1504762",
     {"discogs:label": "1504762"}),
    ("Discogs: peter tetteroo",
     "https://www.discogs.com/artist/282874",
     {"discogs:artist": "282874"}),
    ("Discogs: Terry Dempsey",
     "https://www.discogs.com/artist/1033325",
     {"discogs:artist": "1033325"}),
]
```

Write these tests, one per bullet:

1. `test_bundle_path_exists` — `its_saxy_bundle()` is an existing directory holding
   `release.json` and a `media/` directory.
2. `test_bundle_reads_and_verifies` — `read_bundle(bundle_dir)` returns a `Release`
   with `schema_version == 1`. (The default `verify=True` hashes every file, so this
   also proves the bundle is internally consistent.)
3. `test_every_bundle_file_hashes_to_its_name` — for every entry in
   `release.media + release.audio`: `entry.file` equals `f"media/{entry.sha256}.<ext>"`
   for its own extension, the file exists under the bundle root, and
   `hashlib.sha256(path.read_bytes()).hexdigest() == entry.sha256`.
4. `test_media_directory_has_no_orphans` — the set of filenames in `media/` equals the
   set of basenames of the `file` fields, so nothing extra ships in the bundle.
5. `test_release_json_round_trips` — `json.loads((bundle_dir / RELEASE_FILENAME).read_text())`
   equals `release.model_dump(mode="json")`.
6. `test_identity_matches_integration_md` — `refs == {"discogs:release": DISCOGS_RELEASE_ID}`
   (no `discogs:master` key at all); exactly one `Provenance`, `kind == "vinylcat"`,
   `id == VINYLCAT_RECORD_ID`, `label == "Test"`, `exported_at == FIXTURE_EXPORTED_AT`;
   title, country, medium, format as above; `year is None`; `released is None`; one
   artist with the expected name, sort name and `{"discogs:artist": DISCOGS_ARTIST_ID}`;
   one label with the expected name, `catalogue_number`, and
   `{"discogs:label": DISCOGS_LABEL_ID}`.
7. `test_genres_and_styles` — `genres == EXPECTED_GENRES` and `styles == []`.
8. `test_tracks_match_integration_md` — `[(t.position, t.title) for t in release.tracks]
   == EXPECTED_TRACKS`; every track has `duration is None`; only B5 and B6 carry
   credits, each exactly one, matching `EXPECTED_TRACK_CREDITS` on role, name and
   `refs["discogs:artist"]`.
9. `test_media_matches_integration_md` — four entries: two `kind == "photo"` whose
   `role`s are `EXPECTED_PHOTO_ROLES` in order, each with `mime == "image/png"`,
   `source_url is None` and `refs == {}`; two `kind == "external_photo"`, each with a
   non-empty `source_url` and `refs == {"discogs:release": DISCOGS_RELEASE_ID}`.
10. `test_audio_matches_integration_md` — twelve entries whose `track_position`s are the
    twelve track positions in order, every `format == EXPECTED_AUDIO_FORMAT`, and every
    `size_bytes` equal to the real size of its file on disk. Every audio sha256 is
    distinct.
11. `test_links_match_integration_md` — `[(link.label, link.url, link.refs) for link in
    release.links] == EXPECTED_LINKS`.
12. `test_release_level_credits_notes_and_tags_are_empty` — `credits == []`,
    `notes is None`, `tags == []`.
13. `test_verify_rejects_a_corrupted_bundle` — copy the bundle into `tmp_path` with
    `shutil.copytree`, overwrite one file under `media/` with different bytes, and assert
    `read_bundle(copy)` raises `BundleError` whose message contains that filename; then
    assert `read_bundle(copy, verify=False)` returns a `Release` without raising.

## `tests/README.md`

New folder — create its README. It must describe all five test files the batch
produces, even though the other four are written by plans 02 and 03:

```markdown
# tests

pytest suite for `mediacore`, mirroring `src/mediacore/`. Run from the repo root with
`.venv/bin/python -m pytest -q`. There is no behavioural spec file in this repo:
`INTEGRATION.md` §3–5 and §11 are the contract, and each test quotes the section it
pins.

- `conftest.py` — shared builders: `sha256_bytes`, `make_release(**overrides)` (a
  minimal valid `Release`), `make_media_file(data, *, ext, **overrides)`,
  `make_audio_file(data, *, position, fmt, **overrides)`, and
  `write_source_files(directory, payloads) -> {sha256: Path}` for `write_bundle`'s
  `files` argument. Constants: `SAMPLE_EXPORTED_AT`, `SAMPLE_RECORD_ID`,
  `SAMPLE_RELEASE_REFS`, `SAMPLE_ARTIST_REFS`.
- `test_fixture.py` — the batch's acceptance test: loads `fixtures/its-saxy/` through
  `its_saxy_bundle()` / `read_bundle()` and asserts every fact in `INTEGRATION.md` §11
  plus every file hash. Depends on `fixtures/its-saxy/` having been generated by
  `scripts/make_fixture_its_saxy.py` — it is red on a checkout where that has not run.
- `test_normalize.py` — sample-based pins for `normalize_text` / `normalize_catno`,
  including the accent and whitespace cases they must fold identically to
  `vinylcat.normalize` in the vinylCatalogue repo.
- `test_refs.py` — the ref-key grammar, ref values, `ref_uri` / `parse_ref_uri`, and
  `KNOWN_REF_KEYS`.
- `test_release.py` — the §3 models: JSON round-trip, `extra="forbid"`, closed
  vocabularies, defaults, and ref validation on nested models.
- `test_bundle.py` — `read_bundle` / `write_bundle` including every failure case
  (missing `release.json`, missing media file, hash mismatch, an unmapped sha256, a
  source file whose bytes do not hash to its key).
```
