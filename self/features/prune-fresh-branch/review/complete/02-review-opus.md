# 02 — review: prune-fresh-branch, round 2

## What the feature was supposed to do

The feature and its contracts are as described in `review/complete/01-review-opus.md`:
the prune in `feature-start.sh` must never delete a concurrent start's brand-new branch.
It counts a branch as merged only when the branch is an ancestor of `origin/main` **and**
has moved since it was created.

Round 1 escalated two missing tests (`escalations/01-review-opus.md`). This round adds
them, and also closes the reflog-expiry note from round 1. The oldest reflog entry now
counts as the creation point only if its message starts with
`BRANCH_CREATED_REFLOG_PREFIX` (`branch: Created from`). Any other oldest entry, an empty
reflog included, takes the loud `kept` path. This covers a reflog that gc has expired
past its start: before, the prune kept that merged worktree without saying anything, and
now it prints a `kept` line.

## The diff

Base is `main`. Read the round-2 diff: `git diff <round 1 head>..HEAD`, where round 1's
head is the `head` in its `plan_end` stamp in `timing.jsonl`. Then skim
`git diff main...HEAD` for the whole feature.

## Contracts to hold it to

- Everything in round 1's contracts still holds.
- S4g3 covers a fresh branch left behind after `origin/main` moves on. S4g4–S4g6 cover a
  merged branch with an expired first entry and one with no reflog: both are kept, each
  is named on a `kept` line, and neither is deleted.
- Each new check would fail if the behaviour it guards were removed. Say so if one could
  pass vacuously.
- Each new test cleans up its fixtures, so no later check in the file sees them.
- The subject the prune matches is the one git actually writes for
  `git worktree add -b <branch> <start>`.
- The READMEs match the code.

## Verdict

"No findings" is a legitimate verdict.
