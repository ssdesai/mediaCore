# 02 — review: harness-same-repo (round 2)

Written from the spec and the round-1 escalation (`escalations/01-review-opus.md`), not
from the builder's report. "No findings" is a legitimate verdict.

## What the feature was supposed to do

Read `review/complete/01-review-opus.md` → "What the feature was supposed to do" and hold
the whole diff to it again: the owner's rule is that every experiment runs from, and lives
on, the repository it measures. A fixture's or program's `repo` block is optional and must
be the consumer; the spec defaults to the consumer; the five scripts refuse a harness that
is not the consumer's own vendored copy (test seam only); the arm's agentTooling pin and an
external `spec.url` stay read-only; the smoke test and docs match.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff.

## Contracts to hold it to

- Round 1 escalated two items. Check each is closed:
  1. the `repo.path` branch of `harness_measured_repo_problem` has smoke assertions:
     a path equal to the consumer's directory passes; a checkout of another repository is
     refused naming its owner/repo; a nonexistent path is refused naming the path;
  2. the owner-level decision taken: `repo.url` and `repo.path` are each checked, so a
     matching `repo.url` with a `repo.path` that is not the consumer is refused. Confirm
     it is asserted in smoke and stated once in `harness/README.md` (fixture shape) and
     `harness/SPEC.md` §14, and that the new smoke cases do not weaken any old assertion.
- Everything round 1 held it to still holds (no fixture-path resolution of another
  repository; driver check in all five scripts; bash 3.2, no `set -e`, named constants;
  READMEs accurate; the seam documented only in `harness/tests/README.md`).
- Do not demand work outside scope: consumer-side moves, propagation, experiments.

## Verdict

First line of the report: `Verdict: clean` or `Verdict: escalated`.
