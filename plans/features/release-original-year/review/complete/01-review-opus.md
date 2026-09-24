# 01 — review: release-original-year

feature: mediaCore/release-original-year

## What the feature was supposed to do

Add one field to the `Release` contract — `original_year: int | None = None`, after
`released` — so a bundle can carry the year the work was first released when this release
is a reissue. Because every model is `extra="forbid"`, this is a shape change:
`SCHEMA_VERSION` 3, package 0.4.0. The binding decisions are in
`plans/features/release-original-year/README.md` → "Decisions"; the contract text is
`INTEGRATION.md` §3, §12, §13, which the diff amends.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Read the INTEGRATION.md
hunks first.

## Contracts to hold it to

1. **Shape.** Exactly one new field on `Release`, named `original_year`, `int | None`,
   default `None`, placed after `released`. No `kind`/`issue` enum, no field on `Track`, no
   `in_collection`. `extra="forbid"` still on every model.
2. **Validation.** `1877 <= original_year <= current year`; refused when `year` is present and
   `original_year > year`. Equal is allowed. `None` never fails. Bounds are named constants,
   not literals in the validator. A test covers each edge (1876, 1877, this year, next year,
   equal to `year`, one more than `year`).
3. **Versioning.** `SCHEMA_VERSION == 3`; `pyproject.toml` version `0.4.0`; `INTEGRATION.md`
   §3's shape block says `schema_version: int = 3`; §12 has a dated paragraph in the shape of
   the `Track.artist` one; §13 has a decisions-log entry. `read_bundle` still reads a
   schema-1 and a schema-2 `release.json` (field reads `None`) and still refuses a newer
   version; `write_bundle` stamps 3. Tests exist for both readers and for the stamp — check
   `tests/test_bundle.py` and `tests/test_store.py` no longer hard-code `2` anywhere a
   `SCHEMA_VERSION` should be read.
4. **Fixture.** `fixtures/its-saxy/release.json` (and the packaged copy the wheel check
   asserts) carries `"schema_version": 3` and `"original_year": null` (unless §11 says the
   release is a reissue, in which case the value §11 states), regenerated through
   `scripts/make_fixture_its_saxy.py`, not hand-edited; the gate's fixture-idempotence check
   is green. `tests/test_fixture.py` still passes against the model.
5. **Consumer neutrality.** Nothing vinyl-specific enters `src/` (PROJECT_FACTS →
   Conventions). §6's new sentence describes the adapter's job without adding code here.
6. **READMEs.** `src/mediacore/README.md`'s `Release` field list (CONVENTIONS.md Rule 1)
   names `original_year`; `plans/PROJECT_FACTS.md` → Types says 3 / 0.4.0 and names the field;
   `tests/README.md` has a row for any new test file.
7. **Nothing else moved.** The diff touches the release model, bundle/version constants,
   the fixture and its generator, the docs and the tests. Any change to `store.py`, `refs.py`
   or `normalize.py` needs a reason in `NOTES.md`.

"No findings" is a legitimate verdict. Fix local defects in place; escalate only what needs a
design decision.

## Verdict

Write `plans/review-report.md` with first line `Verdict: clean` or `Verdict: escalated`, then
the findings.
