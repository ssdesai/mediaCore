# 03 — review (round 3): pull-agenttooling-pr173

A hand build: the coordinator built this feature itself, so there is no build plan and no
builder's brief. Review the diff against the spec below — never against the builder's
account of it — and say "no findings" when there are none: that is a legitimate verdict
(AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The spec is the manifest, `plans/features/pull-agenttooling-pr173/README.md`: its opening
paragraph and its "Deliberately excluded" list. Read it before the diff.

## Round 3 notes

Rounds 1 and 2 escalated on the security audit only (round 2's review was clean). The
agentTooling fix `orchestrator-move-length-cap` has since merged upstream (agentTooling
main `b9b7f2d4`): the record-move length cap is enforced first, and `roots.py`
start-refusal/self-write need the `ok` token and fail closed. This round re-pulled it:
`agentTooling/` is now upstream's tree at `b9b7f2d4`, with no local edit. The owner's
round-1 ruling (the earlier length-check ordering accepted for the pull it came in) is
superseded by the upstream fix. The owner approved running round 3 past the audit cap.
The two earlier non-blocking audit findings and the duplicate-stem `run-review.sh` finding
are for agentTooling's backlog, in the report only.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff.

## Contracts to hold it to

- Every behaviour the spec names is implemented, and nothing the spec excludes is.
- `agentTooling/` is upstream's tree at `b9b7f2d4` with no local edit; `src/`, `tests/` and
  the fixtures are untouched.
- The gate (`plans/gate.sh`) is green on this tree: its report says so, and the review does
  not re-run it.
- Every folder the diff touches has a README that still describes it; a generated README is
  changed only through the file its header names.
- The manifest's `plans` list has each stem once.

## Verdict
