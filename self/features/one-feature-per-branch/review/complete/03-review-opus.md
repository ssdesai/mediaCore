# 03 — review: one-feature-per-branch, round 3

## What the feature was supposed to do

The spec in round 1's brief (`review/complete/01-review-opus.md`) and round 2's rework
stand. Round 2 escalated one finding, test-only (`escalations/02-review-opus.md`): nothing
covered looking for a session's subagents beside every copy of its id. The rework adds
cases 19j and 19k to `self/tests/capture-guard.sh` (a subagent filed beside the later copy
only; `--last-branch-instant` must print one second past its last instant, and the capture
must price it) and updates the phase-19 entry in `self/tests/README.md`. No production
code changed this round.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Round 1 and 2's contracts. This round's diff over round 2 is the test and its README
  line, nothing else under `analysis/`.
- 19j and 19k would fail if either reader went back to looking for subagents only under
  the walked directory.
- "No findings" is a legitimate verdict.

## Verdict

First line of the report: `Verdict: clean` or `Verdict: escalated`.
