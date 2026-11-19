Verdict: clean

# Review — harness-review-effort, round 4

## What the batch was supposed to do

`HARNESS_REVIEW_EFFORT` sets the `--effort` of the harness review stage and its
usage-limit retry. When it is unset it falls back to `HARNESS_EFFORT`. Ledger rows (cell
and program) gain `review_effort`, the dry run prints every stage's effort, and rework
stays on `HARNESS_EFFORT`. Rounds 1–3 judged the feature as built. This round checks only
the merge of `origin/main` (PR 128, `harness-scorecard-time`) into the branch at `c4ac39b`,
whose one conflict, in `harness/tests/README.md`, was resolved by hand.

## Whether it does it

Yes.

- **The conflict resolution in `harness/tests/README.md` keeps both sides.** Its gate-step
  list names main's `harness scorecard time self-test` and this feature's
  `harness review effort self-test`. The README says "all eleven", and `self/gate.sh`
  registers exactly eleven steps under "experiment harness": scorecard arms, scorecard
  programs, scorecard time, arm base, arm spec, reading metrics, plans method, long-runs,
  review model, review effort and smoke. The `scorecard-time.sh` table row and its
  run-alone line are present, as are the `review-effort.sh` row, its run-alone line and
  the smoke-test paragraph.
- **The other three shared files kept both sides.**
  - `harness/README.md` keeps main's `tests/scorecard-time.sh` entry and this feature's
    `tests/review-effort.sh` entry.
  - `harness/SPEC.md` still carries `review_effort` in the cell-row field list and in the
    program rulings.
  - `self/gate.sh` keeps main's scorecard-time step and this feature's review-effort step.
  - `review_effort` sits beside `effort` in both row field lists in `harness/README.md`,
    the cell row and the program row.
- **Scope.** `git diff origin/main...HEAD` touches only `harness/` (`lib.sh`, `run.sh`,
  `program-stages.sh`, the docs, `tests/review-effort.sh`, `tests/smoke.sh`),
  `self/gate.sh` and the feature folder. Between round 3 (`92a8a45`) and HEAD the
  branch's own commits changed only the feature folder: `04` was added to `plans[]` in
  the feature README and the round-4 plan was queued. Everything else in that range came
  in from main. The feature's code is unchanged since round 3.
- **Gate.** `self/gate-report.txt` is green and skips no harness check. Both
  `harness scorecard time self-test` and `harness review effort self-test` ran and
  passed.

## Fixed in this pass

None.

## Escalated to the next round

None.
