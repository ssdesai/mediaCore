Verdict: clean

# Review — start-tree-guard

## What the batch was supposed to do

Fix two defects in `feature-start.sh`'s cloud start:

1. **The start commit took the whole index.** It now commits with the feature directory as its pathspec, so anything else staged or modified is left untouched.
2. **Nothing noticed the tree changing while the base gate ran.** The start now records `git status --porcelain` before the setup hook and compares it after the gate, ignoring the feature directory and the gate report. A difference is refused, on a fresh start and on a resumed one.

The batch also adds a test (`self/tests/start-tree-guard.sh`) and updates the orchestrator brief and lifecycle docs to say: run the start in the background and wait for it to finish.

## Does it do it

Yes.

- **Pathspec commit** (`feature-start.sh:1051`). It runs `git add <dir>` then `git commit -q -m "<slug>: start" -- <dir>`. That works when the feature directory holds only new files, because the `add` puts them in the index before the `--only` commit. Paths are given relative to `$WORKTREE`, and the commit runs inside it, so the local worktree profile works the same way.
- **Tree comparison** (`feature-start.sh:815-862`):
  - It runs before the hook and after the gate, so it applies to resumed starts too.
  - It refuses through `refuse`, so the lock is kept and the exit code is `REFUSED_RC`. The refusal names up to `DIRTY_PATHS_NAMED` paths, and the message has the required wording.
- **Path filtering, checked against git's porcelain formats:**
  - **Trailing slash on an untracked directory:** `?? self/features/<slug>/` (a resumed start whose feature directory is still uncommitted) matches `"$TREE_FEATURE_REL"/*`.
  - **Renames:** `R  old -> new` is never filtered. That is harmless, because a line that appears identically before and after compares equal.
  - **Repo in a subdirectory (`REL_REPO`):** the prefix is carried into both `TREE_FEATURE_REL` and `TREE_REPORT_REL`. Porcelain paths are relative to the worktree's top level, which is `$WORKTREE`.
  - **Quoted paths:** a quoted path (a space in `REL_REPO`) would escape the filter. Only an un-ignored gate report under such a directory would then cause a false refusal. That is unrealistic and not worth a change.
- **The test fails without the fix:**
  - Without the pathspec, the staged `staged.txt` lands in the start commit and C1c fails.
  - Without the comparison, a gate that edits `tracked.txt` passes green and C2a fails.
  - C4a and C4b show the two exclusions are needed.
- **Code rules:** bash 3.2 forms only, no `set -e`, named constants. The gate report ends `all checks passed`, and nothing in the gate report was SKIPPED.

### Known limit (judged, not escalated)

`git status --porcelain` records status, not content. A file that was already modified before the hook and is modified further during the gate is not caught. The spec asks for exactly a porcelain snapshot and comparison, so this meets its wording. Closing the gap would mean recording a hash of each dirty file's content, and that would be a new decision.

### Observation (not a defect)

The snapshot is taken *before the setup hook*, as the spec requires. So a setup hook that changes a tracked or un-ignored file (for example, an install that rewrites a lockfile) now gets the first cloud start refused. Committing that change and running the start again then succeeds. In that case the refusal's "the gate judged a tree that no longer exists" is slightly wrong: the hook made the change before the gate ran. This was the spec's choice and I note it only so it is visible.

## Fixed in this pass

- **`self/tests/orchestrator-brief.sh` B3b.** Its label claimed it checks "wait for its exit notification before touching the tree", but it only checked "Run it in the background" and the refusal sentence. Spec item 4 requires the background run, the output captured to a scratchpad file, *and* the wait for the exit notification to be asserted. It now also asserts `its output captured to a file in your scratchpad` and `its exit notification before you read or edit anything in the tree`. I ran the test after the edit and it passes.
- **`self/tests/README.md`:**
  - The B3b description now matches the stronger assertion.
  - The `start-tree-guard.sh` entry now names a dependency that isn't visible from the test's imports (Rule 2): `plan-runner-roots.sh`'s self-mode `GATE_REPORT_LABEL` must be `self/gate-report.txt`, because that is the path the fake gate writes and the start excludes.

## Escalated to the next round

None.
