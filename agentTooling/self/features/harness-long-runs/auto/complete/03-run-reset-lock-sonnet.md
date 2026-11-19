# 03 — run.sh: the experiment lock and `--reset <cell>`

Feature: `harness-long-runs` — plan 3 of 4 build plans (6 in the batch). `harness/run.sh`
learns to stop safely before the 2-hour background-command kill, to reset a killed cell
non-destructively, to take several `--only` specs, and to refuse a `--from` whose earlier
outputs are missing.

Add a per-experiment lock taken by every non-dry run, and `--reset <spec>`: move a killed
cell's worktree, branch and state aside with a `Killed<UTC ts>` suffix so the next
`--only <spec>` run starts from setup. Never delete, never push.

Depends on: 02-run-cells-budget-sonnet.md (the `CELLS` enumeration, `ONLY_SPECS`,
`cell_spec`, the lib constants). The contract is `harness/tests/long-runs.sh` (plan 01) —
read it first; cases 4 (lock gone), 6–11 are this plan's.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- bash 3.2, `set -uo pipefail`, no `set -e`; every magic value a named constant.
- Why the reset lives in `run.sh`: a consumer's permission hook denies an agent's direct
  `git worktree move` / `git branch -m`; `run.sh` is one invocation the human approves,
  and its own git, like `setup_tree`'s `git worktree add` (`run.sh:281-286`), is
  harness-run. Do not touch `hooks/`.
- No lock exists today (none in `run.sh`, `lib.sh`, `program-stages.sh`). Grep those three
  for `trap` before adding one and chain with anything already there.
- `state/` is committed with the ledger, so the lock must not live there. It lives in
  `"$(git -C "$CONSUMER_ROOT" rev-parse --git-common-dir)"/harness-locks/<basename of
  EXPERIMENT_DIR>.lock/` (make the common dir absolute — `rev-parse` may print it
  relative), a directory made with `mkdir` (atomic), holding a file `pid`.
- Cell paths: `resolve_cell` (`run.sh:133-185`) sets `BRANCH`, `TREE`
  (`<repo>-<branch>`, `harness_worktree_path`, `lib.sh:616`), `STATE`
  (`$STATE_DIR/$BRANCH.json`), `REPO_PATH`, `REMOTE`, `SLUG`. A dry run exports
  `HARNESS_RESOLVE_NO_CLONE=1` (`run.sh:83`); a reset does too.
- State helpers `harness_state_init/set/set_str/get/intervention` (`lib.sh:973-1008`).
  `run_cell`'s `harness_state_init` must keep an existing file (the fresh post-reset state
  depends on it) — confirm by reading it.
- Ledger rows: one JSON object per line in `results.jsonl`, keyed by `.branch`; failure is
  `.method_failed == true` (`build_ledger_row`, `run.sh:721-813`).
- `cost_lost_usd`: `write_stage_manifest` (`run.sh:494-510`) closes an orphaned open
  `session_window` in `$TREE/plans/features/$SLUG/README.md` (`open_manifest_window_of`,
  460-475) and prices it with `capture_one` (619). Transcripts are filed by the tree's
  path, so a window must be priced **before** the tree moves.
- Setup's branch-collision guard is `run.sh:269-279`.

## Files

- Modify `harness/lib.sh` — constants beside plan 02's, and the two lock functions:

```bash
# Experiment lock and cell reset (harness/README.md → "Resetting a killed cell")
HARNESS_LOCK_DIR_NAME="harness-locks"
HARNESS_LOCK_PID_FILE="pid"
HARNESS_KILLED_SUFFIX="Killed"
HARNESS_KILLED_TS_FORMAT='+%Y%m%dT%H%M%SZ'
HARNESS_KILLED_STATE_SUBDIR="killed"
```

  `harness_lock_acquire <lock-dir>`: `mkdir -p` the parent; `mkdir` the lock; on failure
  read `pid` — alive (`kill -0`) → `harness_die "a harness run for this experiment is in
  progress (pid N, lock <dir>)"`; dead or unreadable → `harness_warn` stale, replace the
  pid file and proceed. Write `$$`. Sets `HARNESS_LOCK_HELD=<dir>`.
  `harness_lock_release`: only when `HARNESS_LOCK_HELD` is set: remove the pid file and
  `rmdir` the lock dir.

- Modify `harness/run.sh`.

## `harness/run.sh`

1. **Lock in ordinary runs.** After the experiment and `CELLS` are resolved and before the
   drive loop, in a non-dry run: acquire; release on `EXIT` (so the budget stop and every
   `harness_die` release too). A dry run takes no lock.
2. **`--reset <spec>`** → `RESET_SPEC`. With `--only`, `--from`, `--dry-run` or
   `--time-budget` → `harness_die` (usage). Header comment and `usage` range updated.
   Flow, as its own branch after enumeration (with `ONLY_SPECS=("$RESET_SPEC")`), ending
   in `exit`:
   1. exactly one cell in `CELLS`, else die — zero: "no cell matches"; several: name each
      cell's spec and branch. A program cell → die "reset of a program cell is not
      supported" (excluded — see the manifest).
   2. `resolve_cell`; acquire the lock.
   3. completed: a row with `.branch == $BRANCH` and `.method_failed != true` → die
      ("has a completed record row; a reset never touches a finished cell"). Earlier failed
      rows stay as history.
   4. no `$TREE`, no local branch, no `$STATE` → die "nothing to reset".
   5. `ts="$(date -u "$HARNESS_KILLED_TS_FORMAT")"`; `new_branch="$BRANCH$HARNESS_KILLED_SUFFIX$ts"`;
      `new_tree="$(harness_worktree_path "$REPO_PATH" "$new_branch")"`; new state path
      `$STATE_DIR/$HARNESS_KILLED_STATE_SUBDIR/$new_branch.json`. Refuse if any exists.
      If `$TREE` exists but is not in `git -C "$REPO_PATH" worktree list --porcelain`,
      die before moving anything.
   6. price before moving: carry `cost_lost_usd` from the old state (0 when absent); if
      `$TREE` has an open window, factor the pricing in `write_stage_manifest` (494-510)
      into a function both call, and add its result. A pricing failure warns and adds 0,
      and the intervention says so.
   7. move, in order, each only if present: `git -C "$REPO_PATH" worktree move "$TREE"
      "$new_tree"`; `git -C "$REPO_PATH" branch -m "$BRANCH" "$new_branch"`; `mkdir -p` the
      killed subdir and `mv "$STATE"` there. On any failure stop at once, print what was
      moved and what was not, exit 1 — no rollback, nothing deleted.
   8. write a fresh `$STATE`: `harness_state_init`, `harness_state_set cost_lost_usd
      <carried>`, one `harness_state_intervention` naming the reset and the three new
      paths. Nothing else (no `t_setup_start`, no `stages`), so setup's first-setup path
      runs next time.
   9. print the moved paths, `nothing was deleted or pushed`, a note when
      `refs/remotes/$REMOTE/$BRANCH` exists (the remote branch was left alone; say what
      setup's collision guard, 269-279, will do with it — read it), and
      `next: <$0> <experiment arg> --only <cell_spec>`. Exit 0.
3. **Never** on the reset path: `rm -rf`, `git worktree remove`, `git branch -D/-d`,
   `git push`, `git reset`, `git update-ref`.
