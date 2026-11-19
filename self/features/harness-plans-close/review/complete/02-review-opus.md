# 02 — review: harness-plans-close (round 2)

Round 1 (`escalations/01-review-opus.md`) escalated two findings, both fixed by hand in
`harness/methods/plans/run.sh` and `harness/tests/plans-method.sh`. Re-review the whole
diff; "no findings" is a legitimate verdict (AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The `plans` method (`harness/methods/plans/run.sh`) could not finish a cell. Fixed inside
`harness/methods/plans/` (plus its tests and docs):

1. The batch log is written under `HARNESS_LOG_DIR`, appended, never into the arm tree.
2. `METHOD_USAGE_LIMIT_RC` only on positive evidence (the runners' usage-limit or interrupt
   summary) in the output of the current `run-batch.sh` invocation. Any other non-zero exit
   is `METHOD_FAILED_RC` at once, last lines of this run's output in the warning, no resume.
3. (round 1) The harness re-runs the whole method script after exit 2, so a script entered
   with the batch already started (plans in any `inprogress/` or `complete/`) must skip the
   architect and the incomplete-queue assertions and go straight to the batch.
4. (round 1) The failure warning's tail comes from the same offset as the evidence check.

Excluded: `feature-close.sh`, `direct`/`direct-bare`, effort, anything outside
`harness/methods/plans/`, its tests and docs. `run.sh` must stay compatible with an older
vendored `harness/lib.sh`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`.

## Contracts to hold it to

- Everything in round 1's list still holds (evidence strings pinned to `plan-runner-lib.sh`,
  escalation beats evidence, exit codes 0/1/2, test registered in `self/gate.sh` and
  `harness/tests/README.md`).
- A first call (queues full, nothing started) still runs the architect and asserts the
  queues; a call with the batch started never calls `claude` (test 8).
- READMEs and SPEC match the code, including "that call resumes the batch".

## Verdict
