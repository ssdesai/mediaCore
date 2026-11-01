# 02 — review: one-feature-per-branch, round 2

## What the feature was supposed to do

The spec in round 1's brief (`review/complete/01-review-opus.md`) stands. Round 1 escalated
one finding (`escalations/01-review-opus.md`): `last_branch_instant` in
`analysis/capture_planning.py` read only the walked copy of a session id, so the
`session_window.to` stamped from its evidence could end with the shorter copy while the
capture priced the longer one, cutting a pinned session short. The rework gives
`last_branch_instant` the same per-id dedupe as `capture_feature`'s walk: one read per
session id from the copy that ends latest, subagents looked for beside every copy.
`self/tests/capture-guard.sh` cases 19h and 19i cover it.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Round 1's contracts, and that round 1's own in-review edits (single-copy sessions not
  re-read; `find_session_elsewhere` removed) left nothing calling a removed name.
- `last_branch_instant` and `capture_feature` agree on which copy of a session id is
  read, and on which directories a session's subagents are looked for.
- The test asserts the stamped bound and the priced total, not only that the code runs.
- "No findings" is a legitimate verdict.

## Verdict

First line of the report: `Verdict: clean` or `Verdict: escalated`.
