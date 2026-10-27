# Checkpoint: runner-sandbox

status: committed
updated: 2026-09-30T14:34:19Z
gate: all checks passed (shellcheck skipped: not installed)

## Slices
- [x] acceptance tests — self/tests/hook-wiring.sh (sandbox cases), self/tests/self-settings.sh (section E); committed first
- [x] 1. SANDBOX_* constants + gaps/apply in hooks/wire-settings.py (both layouts)
- [x] 2. regenerate this worktree's .claude/settings.json
- [x] 3. validation run: run-review.sh --self runner-sandbox under the sandbox — no domain or path needed; artefacts removed (NOTES.md)
- [x] 3a. reviewer findings: null => INVALID (3 cases), read-surface text corrected, owned-switch ruling recorded
- [x] 4. docs: hooks/README.md, RUNNER.md, sync-plans.sh header, root README rows, tests README rows
- [x] 5. manifest prose, NOTES.md, BACKLOG entry replaced by two leftovers (consumer Playwright run, Linux)
- [x] gate

## Learned
- The review runner commits the whole tree: the validation run's commit c3ff3c2 carries uncommitted doc edits too.
- blockReadsOutsideWorkingDirectories is enforced by the sandbox at OS level (~/Library/Caches unreadable).

## Resume
- Nothing to resume; the real review is next: run-review.sh --self runner-sandbox
