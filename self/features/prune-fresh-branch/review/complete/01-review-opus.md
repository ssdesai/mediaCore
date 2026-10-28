# 01 — review: prune-fresh-branch

## What the feature was supposed to do

Stop two concurrent `feature-start.sh` runs from deleting each other's new worktree.
The prune (step 3) called a worktree merged when its branch was an ancestor of
`origin/main`. A branch that another start has just created with `git worktree add -b`
has no commits of its own until that start's `S: start` commit lands, which happens after
the hook and the gate. During that window the branch is trivially an ancestor, so the
prune removed it. This cost a user three attempts on 2026-09-22.

The fix changes what "merged" means rather than adding a lock: a branch has merged only
when it is an ancestor of `origin/main` **and** it has moved since it was created. Its
creation point is the oldest entry in its own reflog. A branch still at that commit has
merged nothing and is left alone without a message. A branch with no reflog cannot be
proven either way, so it is kept, with one line saying why.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect
`feature-start.sh` (header step 3, the prune comment, `prune_one`),
`self/tests/feature-lifecycle.sh` (new check S4g2), `README.md` and `self/tests/README.md`
(the prune's description).

## Contracts to hold it to

- Every merged-and-clean worktree the old rule pruned is still pruned: S4a, S4i–S4k and
  M1 in `self/tests/feature-lifecycle.sh` must still pass. A feature branch always carries
  `S: start`, so its tip differs from its creation point.
- A branch with no commits of its own is never pruned, whatever `origin/main` is. That
  includes a branch created from an older `origin/main` that has since moved on.
- Nothing is deleted that cannot be proven. A missing or unreadable reflog means the
  worktree is kept, never removed.
- A reused slug is judged on its own reflog: `git branch -D` deletes a branch's reflog
  with it, so the history of an earlier branch with the same name cannot count.
- The dirty-worktree and unmerged paths are unchanged, and the prune still pushes and
  commits nothing.
- The code reads like the rest of the file: named constants where a literal carries
  meaning, bash 3.2, and no `set -e` assumptions.
- The READMEs describe the new predicate accurately (CONVENTIONS.md → "Keeping READMEs up
  to date").

Out of scope: the `info/exclude` append is also unsynchronised between two starts, but it
is idempotent in effect (the worst case is a duplicate line). The known stderr line from
the T5 fixture in `feature-lifecycle.sh` predates this feature.

## Verdict

"No findings" is a legitimate verdict. Report only defects against the contracts above,
each one with the concrete sequence of events that triggers it.
