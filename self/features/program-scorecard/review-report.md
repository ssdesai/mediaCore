Verdict: clean

# Review — program-scorecard

## What the batch was supposed to do

Settle the contract for a program-level A/B, where an orchestrator runs an ordered list of features and the two arms are compared as one feature set, before any driver produces such runs. The contract has five parts:

- a documented `kind: "program"` ledger row (`harness/README.md`);
- `scorecard.py` support: `split_rows`, a `## Programs` section, a program comparison line under the band heading, and program notes and gate counts folded into the existing sections;
- a hand-built-ledger test, `harness/tests/scorecard-programs.sh`, that includes a byte-identity check for a ledger with only ordinary cells;
- registration of that test in `self/gate.sh`;
- doc updates ("two tests" becomes "three").

## Does it do it

Yes.

- **Byte-identity holds.** I read every changed line of `render()`. When there are no program rows:
  - the header suffix is empty;
  - `if rows:` is equivalent to the old unconditional block;
  - `program_comparisons` and `render_programs` both return `[]`;
  - the program note and gate loops never run.

  I also rendered the test's cell-only ledger with `origin/main`'s `scorecard.py` (extracted with `git show`). The output matches `harness/tests/scorecard-programs.cells.md` byte for byte. The test compares against that file with `cmp -s`.
- **Program rows and cell rows stay apart.** `split_rows` runs first. Cell sections iterate only `rows`, and program sections iterate only `programs`.
- **The arithmetic matches the docs.** Dollar figures are read from the row, never recomputed. `overhead_pct` follows the formula `report.py --orchestration` uses.
- **The documented row lists every field in the brief.** `scorecard.py` reads no field the README omits.
- **The gate registration is in place,** with a comment like its neighbours. No "two tests" wording remains outside historical records.

## Fixed in this pass

1. **Crash on a null summary field** (`harness/scorecard.py`, `program_counts`). The fallback checked whether `features_pr_open` / `features_green` was present, not whether it was null. So `"features_pr_open": null` raised `TypeError: float() argument must be ... not 'NoneType'` and stopped the whole scorecard from rendering. A null `features_count` silently became 0 instead of `len(features)`.
   - All three fields now fall back to counting `features[]` when they are absent or null.
   - I reproduced the crash on a programs-only ledger before fixing it.
2. **Missing assertion for the fix** (`harness/tests/scorecard-programs.sh`). Added a fourth case: the two program rows alone, with `features_count`, `features_pr_open`, `features_green` and `overhead_pct` nulled. It asserts that the scorecard:
   - renders;
   - has no `## Runs` section;
   - falls back to `1/2`, `1/2` and `20.5%`.

   The case also covers "no cells, only programs", which nothing tested before. `harness/tests/README.md` now describes it.
3. **README fallback sentence was incomplete** (`harness/README.md` → "The program row"). It said only `features_pr_open` and `features_green` fall back. The code also falls back for `features_count` (from `features[]`) and for `overhead_pct` (computed from cost, 0 for a zero group cost). The sentence now says all of that, plus "every dollar figure is read from the row".
4. **`record_report` cross-check was described as like for like** (`harness/README.md`). `report.py --orchestration` sums each priced feature's whole `report.json` total, which includes review and rework and leaves unpriced features out. The harness's `cost_group_usd` sums `cost_method_usd` only. So the "Record says" figure is systematically closer to `cost_group_green_usd`, and its `overhead_pct` is over a larger denominator. The README now says so, so a reader does not mistake that gap for a bug.
5. **Inline literals** (`harness/scorecard.py`). Three new literals in the program code are now named constants at the top of the file (CONVENTIONS.md → Named constants):
   - the program-failed note → `PROGRAM_FAILED_NOTE`;
   - the `unpriced — ` prefix → `UNPRICED_NOTE_PREFIX`;
   - `100.0` → `PERCENT_SCALE`.

After these edits, `harness/tests/scorecard-programs.sh` and `harness/tests/scorecard-arms.sh` both pass.

## Escalated to the next round

None.

## Note (not a defect against the brief)

A feature with `depends_on_previous: true` whose `dependency_ok` is null or absent renders `✓`. That is what the brief specifies (✗ only when `dependency_ok` is false), but `✓` then claims something the row does not. When the driver is built, it should always set `dependency_ok` to a boolean for a dependent feature. Alternatively, a later change could render `?` for an unknown value. Either is a design choice, not something for this pass.
