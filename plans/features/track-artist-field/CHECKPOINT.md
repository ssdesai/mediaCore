# Checkpoint: track-artist-field

status: gating
updated: 2026-09-06T22:58:27Z
gate: all checks passed (5 checks: install, lint, fixture idempotent,
      wheel contains fixture, tests — 286 passed; 0 skipped)

## Rework slices (review escalations, PR #13)
- [x] 1. `write_bundle` stamps `schema_version`: `release_payload(release)` in
      `src/mediacore/bundle.py` dumps the model and overwrites the key with
      `SCHEMA_VERSION`; `_populate` serialises that, so the label always describes the
      bytes. Reading still preserves the file's version on the model.
- [x] 2. `SCHEMA_VERSION_FIELD` defined in `bundle.py` (the serialiser) and imported by
      `store.py`; `store._release_payload` delegates to `release_payload`, so
      `BundleStore.put`'s entry, `list` and the file on disk cannot disagree.
- [x] 3. Tests: the frozen schema-1 asset written and re-read
      (`tests/test_bundle.py`), `put` on both store backends
      (`tests/test_store.py`, parametrized `harness` — no skip), and
      `mediacore.__version__ == importlib.metadata.version("mediacore")`
      (`tests/test_release.py`). 282 -> 286 tests.
- [x] 4. Docs: `INTEGRATION.md` §12 (beside the 0.3.0 paragraph) and §13 (a second
      2026-09-06 entry); `plans/PROJECT_FACTS.md`; `src/mediacore/`, `tests/` and
      `tests/assets/` READMEs.
- [x] 5. `plans/BACKLOG.md` deleted — the review created it for exactly these two
      entries and both close here (ruling in NOTES.md → Rework).
- [x] 6. NOTES.md "Rework" rulings; gate green.
- [ ] 7. commit, push, PR comment on #13.

## Learned
- The fixture is untouched by the stamp: `make_fixture_its_saxy.py` builds a `Release`
  at the default `schema_version`, so stamping is a no-op there and the gate's
  byte-for-byte fixture step stays clean.
- The frozen asset carries 4 media and 12 audio entries, and its bytes are deliberately
  not copied under `tests/` — so the re-write test writes it with `media` and `audio`
  emptied (`model_copy`), which is all the stamp needs.
- `put` derives its `BundleEntry` from a payload of its own, so stamping only inside
  `write_bundle` would have left the entry (and `list`) reporting the stale version:
  the escalation needed both call paths, not just the writer.

## Resume
- Nothing to resume once the commit is pushed: branch `track-artist-field`, PR #13,
  gate green. The `v0.3.0` tag is still the human's, after the merge.
