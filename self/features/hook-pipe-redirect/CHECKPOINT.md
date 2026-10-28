# Checkpoint: hook-pipe-redirect

status: committed
updated: 2026-09-27T01:15:36Z
gate: === gate: done — all checks passed === (shellcheck skipped: not installed)

## Slices
- [x] acceptance tests — self/tests/allow-repo-commands.sh (pipe-then-redirect, stash
      list/show approved, stash mutating forms denied; 18 red), self/tests/policy-table.sh
      (stash rules), self/tests/hook-wiring.sh (retired `Bash(git stash:*)` removed),
      replay fixture's `git stash list` record now ALLOW
- [x] 1. pipe-then-redirect: `piped_into_interpreter` reads a `redirect_members` member
      (redirects out of its words, `<` file = the script); is_opaque uses members;
      redirect_members keeps a pipe's sep across a line break
- [x] 2. stash table in policy.py (list/show READ_ONLY, the rest MUTATING), hook deny +
      approval read it; `bash_deny_rules()` renders per-subcommand prefix rules + exact
      bare `git stash`
- [x] 3. wire-settings.py removes the retired `Bash(git stash:*)` rule in a merge;
      `.claude/settings.json` regenerated under --self
- [x] 4. docs: CONVENTIONS.md, hooks/README.md, root README, self/tests/README.md,
      feature README prose, NOTES.md, BACKLOG (both entries deleted)

## Learned
- `Bash(git stash:*)` is a generated permissions.deny rule (policy.bash_deny_rules), so
  a hook allow alone cannot approve `git stash list`; deny rules beat allow.
- Consumer-mode wire-settings never removed a rule; it now removes retired ones only.

## Resume
- git -C <worktree> status --short; git log --oneline main..HEAD
- bash self/tests/allow-repo-commands.sh; bash self/tests/policy-table.sh;
  bash self/tests/hook-wiring.sh (all green at slice 3); then self/gate.sh
