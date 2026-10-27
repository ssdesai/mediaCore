# 01 — review: pull-agenttooling-pr97

@@TODO@@ — write this brief BEFORE the build, from the spec, never from the builder's
report: what the feature was supposed to do, the diff to read, the contracts to hold it
to, and that "no findings" is a legitimate verdict (AGENT_PLANS.md → "Review plans").
run-review.sh refuses to run a brief that still contains the marker above.

## What the feature was supposed to do

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

## Verdict
