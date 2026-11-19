# 04 — review: own-push-credential-keys

Re-review this feature against its spec, which is the coordinator's rulings in
`self/features/own-push-credential-keys/NOTES.md` → "Coordinator rulings", rulings 1-9.
Do not use the builder's report as the spec. "No findings" is a legitimate verdict.

## What the feature was supposed to do

The spec is unchanged from round 3 (`review/complete/03-review-opus.md`). Round 3 came back
clean on both the review and the audit.

Round 4 exists only because one commit landed after round 3's judged head (26d962b).
That commit is 7b47b85, "BACKLOG: round-3 audit's two non-blocking pre-existing silent
allows". It touches `self/BACKLOG.md` only and adds two entries:
- `GIT_EXEC_PATH` in the hook's environment;
- the own-branch push chained with an approved read.

There is no code, test or hook change.

Excluded: as in round 3. The BACKLOG entries record follow-ups. They are not fixes, and
their absence of a fix is not a finding.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every contract in `review/complete/03-review-opus.md` still holds.
- `git diff 26d962b..HEAD` touches only `self/BACKLOG.md`, plus this round's own review
  files.
- The two new BACKLOG entries match the round-3 audit's non-blocking items 1 and 2 in
  `audit-report.md`. Each is marked as a pre-existing silent allow.
- `./self/gate.sh` is green.

## Verdict
