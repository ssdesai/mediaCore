# Notes: track-artist-field

Implementer's rulings, in the order they were made. Every one the manifest settled is
*applied*, not re-decided, and is not repeated here; what follows is what the manifest
left open, plus where each ruling is recorded for a reader who never sees this file.

## Rulings

- **An absent track artist is written as `"artist": null`, never omitted.** Manifest
  point 4 says to follow `write_bundle`: it serialises
  `release.model_dump(mode="json")` with no `exclude_none`, so every optional field is
  already a present key (`duration`, `notes`, `year` are all `null` in the committed
  fixture). `artist` does the same, with no special case anywhere. Recorded in
  `INTEGRATION.md` §13 (2026-09-06), pinned by
  `tests/test_bundle.py::test_release_json_writes_an_absent_track_artist_as_null`, and
  visible in `fixtures/its-saxy/release.json`, where all twelve tracks carry
  `"artist": null`.
- **The frozen schema-1 asset is `release.json` alone, read in place.**
  `tests/assets/its-saxy-schema-1/release.json` is `git show
  main:fixtures/its-saxy/release.json` byte-for-byte. `read_bundle(..., verify=False)`
  touches no media, so copying the bundle's sixteen media files under `tests/` would
  add nothing the asset has to prove — and a copy whose hashes had to keep matching a
  regenerated fixture would break on an unrelated change to the placeholder bytes.
  Recorded in the new `tests/assets/README.md` (which also says *never regenerate*) and
  in the `tests/README.md` row.
- **A second test guards the asset itself**
  (`test_the_frozen_schema_1_asset_carries_no_artist_key`). A frozen artefact silently
  refreshed under today's writer would still pass the backward-read test while proving
  nothing; this one fails the moment the asset gains an `artist` key.
- **`schema_version` 3 gets its own named test** even though
  `test_read_bundle_rejects_release_json_with_a_newer_schema_version` already covers
  `SCHEMA_VERSION + 1`, which is 3 today. Manifest point 5 names the case; a test that
  only tracks the constant would stop asserting *3* the next time the constant moves.
- **`Track.artist` sits after `title`** (manifest point 1), so the on-disk key order
  inside each track object changed to `position, title, artist, duration, credits` —
  Pydantic dumps in field order. Nothing reads `release.json` positionally, and the
  gate's byte-for-byte fixture check passes on the regenerated file, but the diff to
  `fixtures/its-saxy/release.json` is larger than "one key added at the end" for that
  reason.
- **Two `schema_version` literals outside the `Track` line were updated too** —
  `INTEGRATION.md` §3's `schema_version: int = 1` and §5's `release.json # one Release,
  schema_version 1`. Point 3 lists the docs to change and does not name these, but a
  stale version literal in the shape block *is* the doc bug this feature exists to
  correct, and leaving them would contradict §12's new paragraph two sections later.
- **`test_schema_version_defaults_to_one` was renamed**, not merely retargeted, to
  `test_schema_version_defaults_to_the_installed_version`; it asserts the constant *and*
  the literal 2 through `CURRENT_SCHEMA_VERSION`, so the next bump is a deliberate edit
  in the test rather than a green suite that silently follows the source.
- **Consumer notes (§8, §9) say the field may be ignored, and say why for each.** hNM
  has no node for a track-level artist; musicMap has one `artist_id` per song, which
  §9 already refuses to widen. Neither note prescribes an import — that is each
  consumer's re-pin, which the manifest excludes.
- **`Credit` is untouched, and that is now pinned**
  (`test_credit_has_no_artist_field`): `artist` on a `Credit` is an extra and a
  `ValidationError`. The generic extras test covers `surprise`; this one covers the
  specific confusion the feature invites.

## Deviations from the spec

None. Every one of the five decision points is implemented as written: the field after
`title`, `SCHEMA_VERSION` 2 with package 0.3.0, the doc set of point 3, the regenerated
fixture, and the tests of point 5.

## Left unbuilt

Nothing in scope. The manifest's "Deliberately excluded" items (every consumer's re-pin,
per-track `refs`, creating the tag) are out of scope by the spec's own decision and are
recorded there, so no `plans/BACKLOG.md` was created — this repo still has none.

## Rework (review escalations 1 and 2)

The review pass (`plans/review-report.md`) escalated two invariants nothing asserted.
Both are closed here, not deferred; the rulings the brief left to this pass:

- **The writer stamps, the reader does not.** `write_bundle` labels every file it
  writes with this install's `SCHEMA_VERSION`, whatever version the `Release` carries,
  so a schema-1 bundle re-written by 0.3.0 comes out labelled 2 — which is what its
  bytes are, since the writer dumps today's model and every track carries `artist`. The
  alternative the backlog named (the reader refusing to hand back a stale-versioned
  model) was refused: it would break §12's one-way promise that a 0.3.0 reader *does*
  read a schema-1 bundle, and would punish a consumer that only wanted to look at an old
  export. Reading is untouched — the file's own version stays on the in-memory object,
  which is what keeps the frozen schema-1 asset and its backward-read test meaningful.
  Recorded in `INTEGRATION.md` §12 (beside the 0.3.0 paragraph) and §13 (a second
  2026-09-06 entry).
- **The stamp lives in the payload, not in the model.** `release_payload(release)` in
  `bundle.py` dumps the release and overwrites `schema_version`; `_populate` serialises
  that. The `Release` handed to `write_bundle` is never mutated, so a caller's object
  still says what it was read with. `store.py`'s `_release_payload` now delegates to it
  rather than calling `model_dump` itself: `put` derives the returned `BundleEntry` from
  the same payload the file gets, so entry, listing and file can never disagree about a
  version — which was half the escalation (a store listing 1 for a payload only a 0.3.0
  reader can parse).
- **`SCHEMA_VERSION_FIELD` moved to `bundle.py`.** The key name was a literal in
  `store.py` only; the writer now needs it too, and duplicating the string is what
  `CONVENTIONS.md` forbids. It is defined where the payload is serialised and imported
  by `store.py`, exactly as `BUNDLE_MEDIA_DIRNAME` is defined in `release.py` and
  imported by `bundle.py`. `tests/test_store.py` still imports it from
  `mediacore.store`, which is unchanged as an import path.
- **The fixture did not move.** The generator builds a `Release` at the default
  `schema_version` (2), so stamping is a no-op for it and
  `fixtures/its-saxy/release.json` is byte-identical; the gate's idempotency step
  confirms it.
- **The version assertion went into `tests/test_release.py`.** The tests README names no
  file covering the package surface — `test_release.py` is the §3 models,
  `test_fixture.py` the fixture — and `plans/PROJECT_FACTS.md` pins the suite as
  mirroring `src/`, so a new `tests/test_package.py` would have been a sixth file
  outside that mirror for one assertion. It sits beside
  `test_schema_version_defaults_to_the_installed_version`, the other test about what
  this install *is*, and the README entry says so.
- **`plans/BACKLOG.md` is deleted, not emptied.** The review created it for exactly
  these two entries (its report says so) and both close here, so the file has no content
  left; the brief's instruction on that case is to delete it and say which. This repo
  therefore still has no backlog, as the "Left unbuilt" line above says — that line
  predates the review's file and is true again.

### Deviations

None. Both escalations are implemented as the brief settled them, with the tests it
named: the frozen asset written and re-read in `tests/test_bundle.py`, `BundleStore.put`
through the parametrized `harness` fixture in `tests/test_store.py` (both backends, no
skip), and the `__version__` assertion in `tests/test_release.py`.
