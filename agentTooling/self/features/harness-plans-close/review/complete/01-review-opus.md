# 01 — review: harness-plans-close

Review the diff against the contracts below, written from the spec before the build. "No
findings" is a legitimate verdict (AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The `plans` method (`harness/methods/plans/run.sh`) could not finish a cell. Two defects,
both fixed inside `harness/methods/plans/` (plus its tests and docs):

1. **The batch log leaves the tree.** It was `$TREE/plans/batch.log`, a tracked path, so
   `feature-close.sh`'s dirty-tree refusal fired before `pr.sh` could commit it. It is now
   written under the cell's harness log directory (`HARNESS_LOG_DIR`), still appended
   (`>>`), never truncated. Nothing the method writes may leave a dirty or unexpected path
   in the arm tree.
2. **A usage limit is detected, never assumed.** `METHOD_USAGE_LIMIT_RC` is returned only on
   positive evidence of a usage-limit or interrupt stop in the batch's output for that
   invocation. Any other non-zero batch exit (a close refusal included) is
   `METHOD_FAILED_RC` at once, with the last lines of the batch log in the warning, and no
   resume and no second `run-batch.sh` call.

Excluded: `feature-close.sh`'s rules, `direct`/`direct-bare`, anything about effort, and any
change outside `harness/methods/plans/` other than tests and docs (`harness/lib.sh`,
`harness/run.sh` and `feature-close.sh` differ in the consumer's older vendored copy, and
`run.sh` here must stay byte-compatible with it).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- The usage-limit evidence strings match what `plan-runner-lib.sh` really prints in its
  closing summary (`stopped: Claude usage limit reached on …`, `interrupted by signal …`);
  the test pins them against the library so drift fails the gate.
- Evidence is read only from output appended by the current `run-batch.sh` invocation, not
  from earlier runs' text in the appended log.
- An escalation or a `failed/` plan still fails the method at once, even with evidence.
- Exit codes: `0` PR open, `1` failure, `2` resumable — unchanged for the harness.
- A new test is registered in `self/gate.sh` and listed in `harness/tests/README.md`; it
  covers (a) a successful batch leaves the tree clean with the log outside it, (b) a
  non-zero batch with no evidence exits 1 with exactly one `run-batch.sh` call, (c) a batch
  with usage-limit evidence exits 2. It stubs `run-batch.sh` and `claude`, spending nothing.
- `harness/methods/plans/README.md`, `harness/README.md` and `harness/SPEC.md` no longer say
  the log is in the tree or that a bare non-zero exit is resumed once.

## Verdict
