# Checkpoint: propagation-as-feature

status: committed
updated: 2026-09-27T01:28:39Z
gate: === gate: done — all checks passed === (101 ok; shellcheck skipped, not installed — informational by design)

## Slices
- [x] acceptance tests — `self/tests/propagation-pull.sh` (12 red before the build,
      expected), `sync-check.sh` phase 9 moved onto a feature branch, gate records it
- [x] 1. `update.sh`: refuse off a started feature's branch; print the pulled split sha
- [x] 2. `LIFECYCLE.md` → "Propagate" rewritten as the hand-feature recipe
- [x] 3. `README.md` (`update.sh` entry, "Updating"), `ORCHESTRATION.md` one sentence
- [x] 4. manifest prose, NOTES.md, BACKLOG.md (entry deleted, e2e-test entry added)
- [x] READMEs and tests-README rows (`self/tests/README.md`, `self/README.md`)
- [x] gate green, commit

## Learned
- Neither `git subtree` nor `git merge` is in `hooks/policy.py`'s deny table; the hook
  sees only the top-level command, so update.sh is a prompt, never a deny.
- `routing.worked_in` reads only the router's own transcript (cwd + Edit/Write paths): a
  router that runs `<wt>/agentTooling/update.sh` by absolute path is NOT flagged, so its
  pull would be routing overhead unless it pins itself (`--pin`).
- Run the gate by the worktree's absolute path: the Bash cwd resets to the primary
  between calls, so `./self/gate.sh` after a standalone `cd` gates the primary instead.

## Resume
- Nothing to resume: the review pass is next (`run-review.sh --self propagation-as-feature`).
