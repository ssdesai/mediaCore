# Checkpoint: capture-on-branch

status: committed
updated: 2026-09-17T15:18:00Z
gate: all checks passed (84 ok, 0 FAIL; shellcheck skipped — not installed, informational)

## Slices
- [x] acceptance tests — `feature-lifecycle.sh` rewritten (52 red), new
      `capture-from-worktree.sh` (2 red: F1, F7), `recover-at-close.sh` C/E/F (17 red),
      `routing-record.sh` R6 (4 red), `sync-check.sh` pr.sh v3 (red); gate.sh registers
- [x] 1. analysis: `roots.session_root` → primary for a worktree; `manifest.py
      set-window-to --replace`; `routing.py --refresh-for <slug>`
- [x] 2. `feature-capture.sh` (branch mode + post-merge mode) and the `feature-close.sh` shim
- [x] 3. `run-review.sh` tail; `stamp_pass_end` in `plan-runner-lib.sh`
- [x] 4. `pr.sh` both copies: `PR_AUTO_MERGE`; template-version 3; TEMPLATE_VERSIONS
- [x] 5. `feature-start.sh` printed Next step 4 and comments; `self/gate.sh` script list
- [x] 6. docs and READMEs (root, analysis, self, self/tests, templates/plans, doctrine)
- [x] 7. stale `feature-close` references in analysis/*.py and test comments
- [x] NOTES.md, BACKLOG entries, manifest Slices table
- [x] gate green, commit

## Learned
- Bash tool cwd resets between calls for this agent: absolute paths only; the hook denies
  `X=/p; … $X` shapes.
- There was no git-dir guard inside `capture_planning.py`; the "refusal" was
  `roots.session_root` resolving a worktree's copy to the worktree (its `.git` file).
- `git status --porcelain` collapses an untracked dir; the stray check needs
  `--untracked-files=all`.

## Resume
- `git -C <wt> log --oneline main..HEAD`; `bash <wt>/self/tests/feature-lifecycle.sh`;
  `bash <wt>/self/tests/recover-at-close.sh`; `<wt>/self/gate.sh`
