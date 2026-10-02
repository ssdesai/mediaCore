Verdict: escalated

# Review: prune-fresh-branch

## What the batch was supposed to do

Stop two concurrent `feature-start.sh` runs from pruning each other's new worktree. The old
step-3 prune called a worktree merged if its branch was an ancestor of `origin/main`. That is
also true of a branch another start has just created with `git worktree add -b`, until that
start's `S: start` commit lands. The new rule counts a branch as merged only when it is an
ancestor of `origin/main` **and** its tip is no longer its creation point, which is the oldest
entry in its reflog. A branch with no reflog is kept, with a line saying why.

## Does it do it

Yes. `prune_one` in `feature-start.sh` reads
`git reflog show --format=%H refs/heads/<branch> | tail -n 1`, which is the oldest entry. It
then does one of three things:
- **No entry:** keeps the worktree and prints the `kept` line.
- **Tip equals the oldest entry:** keeps it without a message.
- **Otherwise:** falls through to the existing dirty-worktree and removal paths, which are unchanged.

The contracts hold:
- **Fresh branch:** a brand-new branch is kept silently, whatever `origin/main` has moved to since, because its tip is still its creation point.
- **Real feature branches:** these always carry `S: start`, so they still differ from their creation point. S4a, S4i–S4k and M1 still pass (the gate is green).
- **Reused slug:** `git branch -D` removes the branch's reflog, so a reused slug starts a record of its own.
- **Nothing written:** the prune still commits and pushes nothing.
- **Style:** the code is bash 3.2-safe and doesn't rely on `set -e`.
- **Docs:** the header step 3, the "Merged" comment, the root `README.md` row and `self/tests/README.md` all describe the new rule accurately. No other doc (`LIFECYCLE.md`, `RUNNER.md`, `self/PROJECT_FACTS.md`) describes the old rule.

The new check, S4g2, builds the concurrent-start branch the same way step 4 does. It checks three things: the worktree survives, the branch survives, and the output does not mention the branch. That matches the plan.

## Fixed in this pass

Nothing.

## Escalated to the next round

Two of the contracts depend on behaviour that no test checks. If either behaviour broke, every test would still pass. Both are small checks to add to `self/tests/feature-lifecycle.sh` next to S4g2:

1. **A branch with no reflog is kept, never deleted, and the run says so.** This is the "nothing is deleted that cannot be proven" contract. Nothing currently exercises the `[[ -z "$created" ]]` branch of `prune_one` (`feature-start.sh:266-269`). It is exactly the kind of guard a later refactor could turn into a fall-through, for example by changing the test to `[[ "$tip" != "$created" ]]` alone. An empty `created` then differs from any tip, so the worktree would be pruned. Suggested check (S4g3):
   - In the fixture `$AT`, create a branch that has moved: `worktree add -b` from `origin/main`, then one commit.
   - Make that commit an ancestor of `origin/main` by pushing it to the bare remote's `main` and fetching.
   - Delete its reflog file: `.git/logs/refs/heads/<branch>` under the primary's common git dir.
   - Run `start`, then assert that the worktree and the branch both still exist and that the output has a `kept` line naming the branch.
2. **A fresh branch created from an older `origin/main` is kept after `origin/main` moves on.** The plan names this case explicitly. S4g2 only creates the branch from the current `origin/main`, so it never covers it. Suggested check (S4g4):
   - `worktree add -b <b> origin/main`.
   - Advance the bare remote's `main` by one commit.
   - Run `start`, which fetches.
   - Assert the worktree and branch survive and the output does not mention `<b>`.

## Notes, not escalated

- **Reflog expiry can hide a merged worktree.** The rule assumes the oldest reflog entry is the branch's creation. `git gc` expires reachable reflog entries after `gc.reflogExpire` (90 days by default). That breaks the assumption for branches whose first commits are more than 90 days old. Sequence:
   - A feature branch's commits span more than 90 days.
   - `gc` expires every entry but the newest.
   - The PR merges.
   - The next start finds the tip equal to the oldest remaining entry and keeps the merged worktree **silently**.
   - Once that last entry expires too, the worktree is kept with the `no reflog` line instead.

  Nothing is ever deleted wrongly, so this fits the contract, and features in this workflow last days rather than months. If it ever matters, one way to close it is to treat the oldest entry as a creation point only when its reflog message (`%gs`) starts with `branch: Created from`, and otherwise take the loud `kept` path.
