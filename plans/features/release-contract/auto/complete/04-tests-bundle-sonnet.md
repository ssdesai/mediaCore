# Tests: the bundle reader and writer

Feature `release-contract` (plan 4 of 12). The batch delivers the whole `mediacore`
contract package — the `Release` schema, refs, the normalize fold, the bundle
reader/writer — plus the *IT'S SAXY* fixture bundle and its generator.

Write `tests/test_bundle.py`, the level-1 unit tests for `src/mediacore/bundle.py`
(written by plan 07), covering the happy path and every failure case `INTEGRATION.md`
§5 names.

Depends on: `01-acceptance-tests-sonnet.md` — it owns `tests/conftest.py` and this file
uses its builders by name. Do not add anything to `conftest.py`.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below (none —
`tests/README.md` is written by plan 01 and already describes this file).

## Pinned facts

- Package `mediacore`, src layout. Import from the package root:
  `from mediacore import BundleError, read_bundle, sha256_file, write_bundle` and the
  models as needed. Never import from a submodule. `src/mediacore/bundle.py` does not
  exist yet — plan 07 writes it; write the tests against the signatures below.
- `read_bundle(path: Path | str, *, verify: bool = True) -> Release` — parses
  `<path>/release.json`; when `verify`, checks every `MediaFile`/`AudioFile` exists at
  `<path>/<entry.file>` and hashes to `entry.sha256`. Anything wrong raises
  `BundleError` whose message names the offending file.
- `write_bundle(release: Release, dest: Path | str, files: Mapping[str, Path]) -> Path`
  — `files` maps **sha256 → source path**. Writes `<dest>/release.json` and copies each
  referenced file to `<dest>/<entry.file>`, verifying the source hash on the way.
  Returns `dest` as a `Path`. A bundle is written wholesale: an existing bundle
  directory at `dest` is replaced. A `dest` that exists, is non-empty, and is **not** a
  bundle (no `release.json`) raises `BundleError` rather than being deleted.
- `sha256_file(path) -> str` — the hex digest of a file's bytes.
- `BundleError` derives from `Exception`.
- Bundle layout: `release.json` at the root, every file at `media/<sha256>.<ext>`
  (INTEGRATION.md §5).
- `tests/conftest.py` (plan 01) provides `sha256_bytes(data)`, `make_release(**overrides)`,
  `make_media_file(data, *, ext="png", **overrides)`,
  `make_audio_file(data, *, position="A1", fmt="wav", **overrides)`, and
  `write_source_files(directory, payloads) -> {sha256: Path}`. Import them with
  `from conftest import make_release, ...` — pytest puts `tests/` on `sys.path`.
- Pydantic v2: `Release.model_validate(...)`, `model_dump(mode="json")`.

## Files

- Create `tests/test_bundle.py`

## `tests/test_bundle.py`

Module docstring: *"Pins the bundle format and its failure modes (INTEGRATION.md §5)."*

Module-level named constants for the payload bytes and filenames (CONVENTIONS.md →
named constants), e.g. `PHOTO_BYTES = b"fake-png-bytes"`, `AUDIO_BYTES = b"fake-wav-bytes"`,
`RELEASE_FILENAME = "release.json"`, `MEDIA_DIRNAME = "media"`.

Give the module one helper that builds a release with one photo and one audio file
plus the matching `{sha256: Path}` mapping — something like
`def built(tmp_path) -> tuple[Release, dict[str, Path]]` using `make_media_file`,
`make_audio_file` and `write_source_files(tmp_path / "sources", {...})`. Every test
below starts from it; a bundle is written to `tmp_path / "bundle"`.

Tests:

- `test_write_then_read_round_trips` — `write_bundle(...)` then
  `read_bundle(dest) == release`.
- `test_write_bundle_returns_the_destination` — the return value is a `Path` equal to
  `dest`.
- `test_write_bundle_creates_the_documented_layout` — `dest/release.json` exists and
  parses as JSON equal to `release.model_dump(mode="json")`; `dest/media/` contains
  exactly two files, named `<sha256>.png` and `<sha256>.wav` for the two entries; each
  file's bytes equal the source payload.
- `test_read_bundle_missing_release_json_raises` — an empty directory raises
  `BundleError` mentioning `release.json`.
- `test_read_bundle_on_a_missing_directory_raises` — a path that does not exist raises
  `BundleError`.
- `test_read_bundle_on_a_file_raises` — a path that is a regular file raises
  `BundleError`.
- `test_read_bundle_missing_media_file_raises_naming_it` — delete one file under
  `media/` after writing; the raised `BundleError`'s message contains that filename.
- `test_read_bundle_hash_mismatch_raises_naming_it` — overwrite one file under `media/`
  with different bytes; the message contains that filename.
- `test_read_bundle_verify_false_skips_file_checks` — with a media file deleted,
  `read_bundle(dest, verify=False)` returns the `Release` without raising.
- `test_read_bundle_rejects_invalid_release_json` — write `{"nonsense": true}` (and,
  as a second case, text that is not JSON at all) into `dest/release.json`; each raises
  `BundleError`.
- `test_write_bundle_requires_every_sha256_in_files` — drop the audio entry's sha256
  from the mapping; `write_bundle` raises `BundleError` naming that sha256.
- `test_write_bundle_rejects_a_source_whose_bytes_do_not_hash_to_its_key` — point one
  mapping key at a file holding different bytes; `write_bundle` raises `BundleError`
  naming the file or the sha256.
- `test_write_bundle_replaces_an_existing_bundle` — write a two-file bundle, then write
  a different release with only the photo to the same `dest`; afterwards `media/`
  holds exactly one file (the stale audio file is gone) and `read_bundle` returns the
  second release.
- `test_write_bundle_refuses_a_non_bundle_destination` — create `dest` containing an
  unrelated file and no `release.json`; `write_bundle` raises `BundleError` and the
  unrelated file is still there afterwards. (This is the guard that keeps "written
  wholesale, never edited" from deleting a mistyped directory.)
- `test_write_bundle_accepts_an_empty_existing_destination` — an existing empty
  directory is written into without complaint.
- `test_sha256_file_matches_hashlib` — for a file of known bytes, `sha256_file(path)
  == sha256_bytes(data)`.
- `test_release_with_no_files_round_trips` — `make_release()` (no media, no audio) and
  an empty `files` mapping write and read back cleanly, and `dest/media/` exists but is
  empty.
