# Checkpoint: cloud-checkpoint-push

status: committed
updated: 2026-11-08T00:00:30Z
gate: not run (the coordinator's). Run green by hand: hook-cloud-profile, cloud-start,
cloud-checkpoint-push, review-base, allow-repo-commands, hook-escalation,
hook-orchestrator-role, hook-wiring, policy-table, feature-lifecycle, capture-from-worktree,
audit-fixes, recover-at-close; profile-confinement, readme-index check, bash -n, py_compile,
wire-settings --check.

## Slices
- [x] acceptance tests — hook-cloud-profile.sh (rows + Q), cloud-start.sh (A1i, P1e), cloud-checkpoint-push.sh (C1-C5)
- [x] 1. plan-runner-roots.sh push_feature_branch + checkpoint_push; feature-capture.sh uses it
- [x] 2. feature-start.sh / run-review.sh cloud-only checkpoint push
- [x] 3. hooks/allow-repo-commands.sh own_push_allowed
- [x] docs: hooks/README, CONVENTIONS, LIFECYCLE (step 2, 5, rule 2), README rows, PROJECT_FACTS, tests README, self/README, BACKLOG, NOTES 6-11, gate.sh record

## Learned
- No policy.py change, so no settings.json regeneration.
- Fixtures that copy run-review.sh without env-profile.sh exist: it is sourced only when present.

## Resume
- Nothing left. Coordinator: run ./self/gate.sh, then the review pass.
