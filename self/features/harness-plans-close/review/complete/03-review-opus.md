# 03 — review: harness-plans-close (round 3)

Round 2 came back clean on the code. After it, one commit landed — `harness-plans-close:
fill the feature README` — which `feature-close.sh` will not close over unread. Review the
whole diff again, but the new thing is that commit; "no findings" is a legitimate verdict
(AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The `plans` method (`harness/methods/plans/run.sh`) could not finish a cell. Fixed inside
`harness/methods/plans/`, its tests and docs:

1. The batch log is written under `HARNESS_LOG_DIR`, appended, never into the arm tree.
2. `METHOD_USAGE_LIMIT_RC` only on positive usage-limit or interrupt evidence in the current
   `run-batch.sh` invocation's output; any other non-zero exit is `METHOD_FAILED_RC` at once
   with this run's last lines in the warning, no resume.
3. A re-entered method (plans already in any `inprogress/` or `complete/`) resumes the batch
   without the architect.

Excluded: `feature-close.sh`, `direct`/`direct-bare`, effort, anything outside
`harness/methods/plans/`, its tests and docs.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff, and
`git show 8b0d4b1` for the commit that landed after round 2.

## Contracts to hold it to

- Round 1 and 2's contracts still hold; the code is unchanged since round 2 (check).
- `self/features/harness-plans-close/README.md` is filled, accurate about the plans listed
  and about what was excluded, and carries no template text.

## Verdict
