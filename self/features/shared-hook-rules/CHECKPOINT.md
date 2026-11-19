# Checkpoint: shared-hook-rules

status: committed
updated: 2026-11-13T19:14:25Z
gate: not run (coordinator's); ran: shared-rules, orchestrator-role, orchestration-records-in-repo, hook-orchestrator-role, orchestration-records, coordinator-records, allow-repo-commands, hook-wiring, self-settings, policy-table, security-audit, audit-fixes, readme-index, delegate-cost-claims, hook-brief-header, report-rounds, sync-check, recover-at-close (all green, none skipped); wire-settings --self --check in-sync; check-readme-index clean; py_compile and bash -n on every changed file

## Slices
- [x] acceptance tests — self/tests/shared-rules.sh (checked against NOTES.md ruling 8), registered in gate.sh and tests/README.md
- [x] 1. hooks/shared_rules.py: constants, derived values, the CLI
- [x] 2. hooks/orchestrator_role.py, hooks/allow-repo-commands.sh, hooks/wire-settings.py bind to it
- [x] 3. analysis/roots.py, manifest.py, routing.py, coordinator_check.py, orchestration_capture.py bind to it
- [x] 4. orchestration-start.sh reads the values through the CLI; refuses naming the module
- [x] 5. tests: U3 and R10's equality checks deleted, output check relabelled, fixtures copy shared_rules.py
- [x] READMEs, BACKLOG (URGENT removed, three entries added), NOTES.md rulings 11-18 and the audit list, gate.sh py_compile hooks line gains shared_rules.py

## Learned
- Fixtures that copy analysis/*.py now need hooks/shared_rules.py beside them (roots.py imports it).
- Hook-only pairs against a shell file cannot move: the hook may not depend on shared_rules for anything but the role rule.

## Resume
- Nothing left; the coordinator runs ./self/gate.sh, then the review.
