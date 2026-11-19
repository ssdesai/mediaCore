# 03 — review: orchestration-start-branch-v2 (round 3)

Review the whole diff against the spec in `02-review-opus.md` (beside this file, under
`review/`), and in particular the round-3 rework of round 2's audit escalation
(`../../escalations/02-audit-opus.md`): a `--branch` beginning with `+` became a force-push
refspec of `main`. "No findings" is a legitimate verdict. A finding blocks only when an item
is not closed or the diff introduces a regression; anything else is filed in
`self/BACKLOG.md` as non-blocking.

## What the feature was supposed to do

As `02-review-opus.md` states, plus: `orchestration-start.sh` refuses, before any write, a
`--branch` that is not a plain branch name (`BRANCH_NAME_PATTERN`; no `refs/` or `heads/`
lead, no `..`), and `plan-runner-roots.sh`'s `push_feature_branch` pushes the explicit
refspec `refs/heads/<branch>:refs/heads/<branch>`, so no branch name can be read as another
ref by any caller.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Rounds 1 and 2's contracts (`01-review-opus.md`, `02-review-opus.md`).
- `self/tests/orchestrator-role.sh` B7: `+main`, `+refs/heads/main`, `refs/heads/…`,
  `heads/…` and a name holding `..` are refused, nothing written, origin's `main` unchanged;
  B2d: the explicit-refspec push still pushes and sets the upstream.
- `push_feature_branch`'s callers (`feature-capture.sh`, `feature-start.sh`, `run-review.sh`)
  behave as before for an ordinary branch; `self/PROJECT_FACTS.md` states the new push form.
- `./self/gate.sh` green.

## Verdict
