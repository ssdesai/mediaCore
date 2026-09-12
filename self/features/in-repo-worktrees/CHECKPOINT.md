# Checkpoint: in-repo-worktrees

status: committed
updated: 2026-09-11T14:56:00Z
gate: all checks passed (69 checks: 43 bash -n, 23 self-tests, py_compile, 2 informational; 0 failed, 0 skipped)

## Slices
- [x] acceptance tests — `self/tests/feature-lifecycle.sh` (nested path, exclude
      idempotence, occupied path, legacy close phase L; 62 red), new
      `self/tests/worktree-claims.sh` (12 red), `recover-at-close.sh` paths moved;
      gate.sh rows — committed as `in-repo-worktrees: acceptance tests`
- [x] 1. feature-start.sh — `WORKTREES_DIR_NAME`, nested path, idempotent
      `info/exclude` entry in the common git dir, Next lines
- [x] 2. feature-close.sh — worktree found via `git worktree list --porcelain` by
      branch, fallback nested then legacy
- [x] 3. capture_planning.py — `WORKTREES_DIR_NAME`, `feature_worktree_path`,
      `legacy_worktree_path`, `claim_roots`, `cwd_claimable`; `transcript_dir_name`
      mangles `.`; seven fixtures' `tr '/' '-'` fixed to `tr '/.' '--'` (NOTES 6)
- [x] 4. docs — LIFECYCLE.md, README.md rows + Updating note, PROJECT_FACTS.md,
      AGENT_DIRECT.md, analysis/README.md, self/tests/README.md rows
- [x] gate green, commit

## Learned
- A bare `mktemp -d` on macOS is `…/T/tmp.XXXX`: a `.` in every fixture path, which is
  why every `/`-only project-dir fixture broke once `transcript_dir_name` mangled `.`.
- `git clean -fdx` skips a nested worktree; `-ffdx` deletes it (NOTES 7).

## Resume
- `git -C /Users/sahildesai/dev/vinylCatalogue-in-repo-worktrees status --short`
- gate: `…/agentTooling/self/gate.sh` (background), read `self/gate-report.txt`
- then commit everything (manifest README carries the coordinator's `subagents` pin)
