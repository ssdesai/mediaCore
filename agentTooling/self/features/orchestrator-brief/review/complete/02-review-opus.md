# 02 — review: orchestrator-brief (round 2)

Read-only review of the rework against round 1's escalation. "No findings" is a legitimate
verdict. First line of your report: `Verdict: clean` or `Verdict: escalated`.

## What the rework was supposed to do

Round 1 (`self/features/orchestrator-brief/escalations/01-review-opus.md`) escalated two
items; the rest of the feature (see `review/complete/01-review-opus.md` for the original
spec) was found sound:

1. The brief hardcoded `./feature-start.sh` and bare `CONVENTIONS.md`/`LIFECYCLE.md`, wrong
   in a consuming repo (`./agentTooling/feature-start.sh`). Now every such path carries a
   `<tooling>` placeholder, explained in the authoring note (`.` in agentTooling,
   `./agentTooling` in a consumer); `self/tests/orchestrator-brief.sh` B3 asserts the new
   start shape and B10 that no bare path can return.
2. The generated-stub list is mirrored by hand; B11–B13 now parse `GENERATED` in
   `sync-plans.sh` and assert each name is in the `templates/README.md` table and in
   `sync-check.sh` 1b's loop.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. The rework is the commits after
`orchestrator-brief: review round 1`.

## Contracts to hold it to

- The brief is still under about 80 lines, still has the literal `--branch claude/<slug>`
  and never "assigned branch"; `<tooling>` is explained and used on every path into the
  tooling directory; `CLAUDE.md` and the repo's own `PROJECT_FACTS` stay unprefixed.
- B10–B13 can actually fail (check the commands, not only that they pass); bash 3.2, no
  `set -e`, named constants.
- `self/tests/README.md` describes the new checks; nothing under `.claude/`,
  `self/orchestrations/` or another feature's folder changed.

## Verdict
