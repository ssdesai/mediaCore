# Checkpoint: self-settings-untracked

status: committed
updated: 2026-09-27T01:21:17Z
gate: all checks passed (101 checks; shellcheck not installed)

## Slices
- [x] acceptance tests — self/tests/self-settings.sh (new; setup hook, gate check, vendored
      layout, tracked listing) + feature-lifecycle.sh S1v/S1v2/S6h; committed first
- [x] 1. wire-settings.py --self: vendored layout (no .git here, one above) writes nothing and
      checks for absence; concrete regenerate command in every hint; write message no longer
      says "commit it"
- [x] 2. self/worktree-setup.sh runs wire-settings.py --self --write
- [x] 3. feature-start.sh --self regenerates the primary's file when it is missing
- [x] 4. untrack .claude/settings.json (git rm --cached) and ignore it in .gitignore
- [x] 5. self/gate.sh: shell_scripts + record for self-settings.sh
- [x] 6. docs: hooks/README.md, README.md, self/README.md, self/tests/README.md,
      self/PROJECT_FACTS.md, LIFECYCLE.md, manifest prose, NOTES.md, BACKLOG entry removed
- [x] 7. gate green, commit

## Learned
- Generated file had no drift from the tracked one at the start (--check in-sync).
- hook-wiring.sh's --self repos are plain mktemp dirs with no .git anywhere above: the
  vendored test is "no .git here AND one in an ancestor", so those cases are unchanged.
- feature-lifecycle.sh stubs self/worktree-setup.sh; the real hook is exercised in
  self-settings.sh.

## Resume
- git -C <wt> status --short; bash self/tests/self-settings.sh; bash self/tests/feature-lifecycle.sh
- self/gate.sh, then read self/gate-report.txt
