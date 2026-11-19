# Checkpoint: orchestrator-role-guard

status: committed           planned | tests-written | implementing | gating | committed
updated: 2026-11-05T17:12:51Z
gate: not run (the whole gate is the coordinator's); every touched test file run green, listed under Resume

## Slices
- [x] acceptance tests — self/tests/orchestrator-role.sh, self/tests/hook-orchestrator-role.sh, self/tests/hook-wiring.sh extension, gate.sh and tests/README.md rows
- [x] 1. hooks/orchestrator_role.py + plan-runner-roots.sh reader (orchestrator_record_for_session, refuse_orchestrator_session)
- [x] 2. script guards (feature-start, run-plans, run-verify, run-review, run-batch, feature-close) + orchestration-start.sh reverse guard + orchestration-records.sh fixture copy
- [x] 3. hook (Bash + Agent denies) + wire-settings.py Agent matcher + regenerated .claude/settings.json (self-settings.sh's one-command reader now reads the shared command)
- [x] 4. templates/plans/ORCHESTRATOR_SESSION_BRIEF.md + sync-plans.sh GENERATED + templates READMEs + sync-check.sh
- [x] 5. READMEs and docs (hooks/README, LIFECYCLE, ORCHESTRATION, README.md, PROJECT_FACTS, self/orchestrations/README, BACKLOG, NOTES)

## Learned
- Every lifecycle script already sources plan-runner-roots.sh, so the shell reader goes there and no fixture needs a new copy.
- The hook cannot import analysis/; the orchestrations path is mirrored as a constant in hooks/orchestrator_role.py.
- A fixture that holds the record must commit it on main before the feature branch is cut, or the tree is dirty.
- Bash in this repo hangs on `rev` in a pipe; use the Grep tool for line tails.

## Resume
- git status --short; git log --oneline origin/main..HEAD
- green: orchestrator-role, hook-orchestrator-role, hook-wiring, allow-repo-commands, hook-cloud-profile, hook-escalation, self-settings, policy-table, orchestration-records, orchestrator-brief, sync-check, cloud-start, session-start, readme-index, feature-readme-check, template-versions; check-readme-index.py, wire-settings.py --self --check, profile-confinement.sh, bash -n, py_compile
- never run self/gate.sh or feature-lifecycle.sh here (coordinator's)
