# tests/assets

Frozen inputs for the suite. Unlike `fixtures/`, nothing here is generated: each file is
a byte-for-byte copy of something that once shipped, kept so a test can prove the code
still reads it. **Never regenerate, reformat, or "update" one** — an asset that follows
the current code proves nothing.

- `its-saxy-schema-1/release.json` — the IT'S SAXY bundle's `release.json` exactly as
  `mediacore` 0.2.0 wrote it (`schema_version` 1, no `artist` key on any track), copied
  from the commit before `Track.artist` landed. `tests/test_bundle.py` reads it through
  `read_bundle(..., verify=False)` to pin that a 0.3.0 reader still reads a schema-1
  bundle and defaults every `Track.artist` to `None`, and writes it back out to pin that
  the writer **stamps** `schema_version` — the re-written bundle is labelled 2, the
  release the reader returned still says 1 (`INTEGRATION.md` §12, §13 2026-09-06). It is
  the `release.json` alone: `verify=False` touches no media, so the bundle's `media/`
  files are deliberately not duplicated under `tests/`, and the re-write empties `media`
  and `audio` because there are no bytes to hand `write_bundle`.
