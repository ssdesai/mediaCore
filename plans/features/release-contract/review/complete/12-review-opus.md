# Review: the release contract

Feature `release-contract` (plan 12 of 12). WP0 of `INTEGRATION.md` §12: the whole
`mediacore` package — `Release` (§3), refs and provenance (§4), the shared normalize
fold, bundle read/write (§5) — plus the *IT'S SAXY* fixture (§11) and its deterministic
generator. Nothing else: no adapter, no consumer code, no TypeScript.

Branch `releaseContract`, base `main`. **Most of the batch's output is still
uncommitted** — `plans/pr.sh` commits it after this pass — so the diff is assembled
from two places: `git diff main` for tracked files (the plan corpus and `plans/gate.sh`
were committed before the run), and `git status --porcelain` for the new, untracked
files, which you read directly. Do not commit anything yourself.

Verify already ran the work and fixed what running revealed. Do not re-run tests, build
wheels or regenerate the fixture. Read the code.

## Hold it to

- **§3, field by field.** Every model, every field, every optionality and default. A
  field missing or misnamed here is a defect in three repos that will each mirror it.
- **§4.** The ref-key grammar as stated, values non-empty strings, unknown keys
  accepted, provenance kept out of identity. The batch deliberately left `isrc` and
  `barcode` undefined because §4's own grammar cannot express them — judge whether
  that call and the way it is recorded (in `src/mediacore/README.md` and the feature
  manifest) is the right shape of unresolved.
- **§5.** `read_bundle`/`write_bundle` behaviour, including what happens to a
  destination that is not a bundle, and whether a failed `write_bundle` can leave a
  half-written directory.
- **§11.** The fixture's metadata, and whether anything in it was *invented* rather
  than transcribed. (One thing was: the two external-photo `source_url`s, which §11
  does not give. Judge whether the way that is marked in the code is honest enough for
  a fixture three repos will read as real.)
- **CONVENTIONS.md.** README Rule 1 field lists on every cross-module shape; Rule 2 on
  every contract not visible from an import line; named constants instead of inline
  literals — the fixture generator and `tests/test_fixture.py` are where that rule is
  most likely to have been skipped.
- **`plans/PROJECT_FACTS.md`.** Does it still describe this repo accurately now that
  the code exists? Fix it if not.
- **Nothing vinyl-specific in `src/`.** §2.1.

## The invariants most likely to have no test

This is the highest-value output: name the assertion, and where it belongs.
Candidates worth checking, not a checklist to confirm:

- that `read_bundle` rejects a `release.json` whose `schema_version` is from the future;
- that a bundle cannot contain two entries with the same `sha256` and different `file`
  values, or an `AudioFile` whose `track_position` matches no `Track`;
- that `write_bundle` leaves the destination untouched when it raises;
- that the fixture's twelve `AudioFile`s and twelve `Track`s agree position for
  position.

## Verdict

Write `plans/review-report.md`. It becomes the PR body verbatim, so write it for the
human approving the PR: what the batch was supposed to do, whether it does it, then two
lists — *fixed in this pass* and *escalated to the next batch* — and a one-line note on
anything a consumer repo (WP1–WP3) must know before pinning `v0.1.0`.

**"No findings" is a legitimate verdict.** Do not manufacture findings to fill the
lists; a speculative one costs the next batch turns to disprove.
