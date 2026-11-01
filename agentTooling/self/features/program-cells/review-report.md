Verdict: clean

# Review: program-cells (round 2)

## What this round was supposed to do

The feature adds the driver for `kind: "program"` ledger rows: a headless orchestrator
session, one implementer `claude -p` per feature in its own worktree, dependent features cut
at the previous feature's tip, `cost_overhead_usd` priced with the driver's analysis copy, a
version floor, and `orchestrator` reserved as a method name. Round 1 judged the whole design
and escalated three items. This round was to fix those three without breaking anything else.

The gate is green, and it skipped no checks.

## Does it do it

Yes. All three escalations are fixed.

1. **`unpriced_reason` is produced.** `program_note_unpriced` (`harness/program-stages.sh`)
   runs after each feature's `do_capture`. It writes a string when either:
   - the feature has no manifest directory; or
   - the captured cost is below 0.9 × what `claude` reported in
     `<logs>/<featureBranch>-method-result.json` (the same file `HARNESS_METHOD_RESULT`
     names). This also covers zero against a non-zero report.

   Otherwise it writes `null`. Because it is re-written on every capture, a `--from capture`
   re-run cannot leave an old reason in place. The `harness/README.md` row text, the
   README's state-key list, SPEC §13 and `EXPERIMENTS.md` assumption 3 all say what the code
   does.

   A new smoke section runs a real program:
   - feature 1 never gets a brief, and the test asserts "no implementer ran";
   - feature 2's implementer reports $0.75 that the capture cannot find, and the test
     asserts the string names both figures.

   The full run also asserts that priced features carry `null`.
2. **The row arithmetic is tested on non-zero figures.** The full run now runs under its own
   `HOME`. The fake `claude` writes one billed transcript per orchestrator and implementer
   call there, so `program_cost.py` and `capture_planning.py` price real non-zero figures.
   - One smoke check asserts that the overhead and every feature's `cost_method_usd` are
     above 0.
   - Further checks cover `cost_group_usd`, `cost_group_green_usd`, each feature's
     `cost_green_usd` and `overhead_pct`, within 0.0002.

   One limit: review and rework still run the plain fake, so `cost_review_usd` and
   `cost_rework_usd` are 0. The `cost_group_green_usd` and `cost_green_usd` checks therefore
   prove the method and overhead terms, but not the review and rework terms. The
   `cost_group_usd` and `overhead_pct` checks run on fully non-zero inputs.
3. **A killed first orchestrator call can be resumed.**
   - `orch_invoke` saves `orchestrator_first_call_started` before the first `--session-id`
     call.
   - On re-entry with `orchestrator_calls == 0` and that marker set,
     `orch_replace_killed_session` mints a fresh id and stores it as `session_id`.
   - The old id stays in `orchestrator_sessions[]`, with the marker's instant as its start.
     `program_cost.py` prices a session with no transcript at 0 rather than failing.
   - An intervention is recorded that names both ids.
   - The behaviour is assumption 4 in `EXPERIMENTS.md` and a SPEC §13 assumption to
     rehearse. SPEC also notes that the orchestration record keeps the first minted id.

   Smoke covers it directly: a fresh distinct id, the old id with its start, an
   intervention, and three distinct ids after a second kill. It also checks that the full
   run's state carries the marker with all 4 calls counted.

**Other contracts:**
- **Ordinary cells:** round 2 did not change `run.sh` or `lib.sh`.
- **Tests:** round 2 added smoke checks and weakened or removed none. In the fake `claude`,
  `total_cost_usd` still defaults to 0, and the new `sleep`s only run under
  `SMOKE_PRICED_TRANSCRIPTS=1`.
- **Style:** the new code holds to bash 3.2 and `set -e` is absent. The new strings and the
  threshold are named constants.

## Fixed in this pass

1. `harness/README.md` → "The program row": the `unpriced_reason` sentence says a feature
   with no manifest directory gets a string. That is not true for a feature with no worktree
   at `capture`, which `do_program_capture` skips before `program_note_unpriced` runs, so it
   keeps `null`. That is the "loop never reached it" case, which the same section already
   marks with `method_failed: true`. Added one sentence saying so.

   I did not change the code. Writing a reason there would create a state file for a
   feature that has none, and the row derives "never reached" from the state file being
   absent.

## Escalated to the next round

None.

## Notes (not escalated)

- **Other failures also mint a fresh id.** `orch_replace_killed_session` fires for any first
  call that never counted, not only a killed one. That includes a call that exits non-zero
  before reporting a session, such as a startup failure. In a program whose brief call fails
  that way, each later orchestrator call mints another id and records another intervention.
  The program is already `method_failed`, the extra ids price at 0, and the function's
  comment states this scope. It only inflates `orchestrator_sessions[]` and
  `interventions[]` on a run that has already failed.
- **The 0.9 threshold is in two places.** `PROGRAM_UNPRICED_FLOOR_PCT=0.9` repeats the
  inline `0.9` in `run.sh`'s `do_capture` warning, which was already on `main`. Making
  `run.sh` use one shared constant would be a small cleanup that touches the ordinary-cell
  path, so I left it. Also, the name `_PCT` holds a fraction, not a percentage.
