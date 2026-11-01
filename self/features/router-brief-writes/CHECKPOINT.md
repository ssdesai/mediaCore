# Checkpoint: router-brief-writes

status: committed
updated: 2026-10-02T23:04:51Z
gate: === gate: done — all checks passed === (shellcheck skipped: not installed)

## Slices
- [x] acceptance tests — self/tests/routing-record.sh R12a–c (evidence), R12i–t (carve-out, near misses, derivation); feature-lifecycle.sh RBb2 (15 red in routing-record.sh, expected)
- [x] 1. routing.py — feature_dir_in_worktree, is_router_write, worked_in → evidence; CLI prints `<id>\t<evidence>`; roots.checkout_of
- [x] 2. feature-close.sh — splits the line on the tab, names the evidence in the refusal; header comment
- [x] 3. docs — LIFECYCLE 3/5/6, ORCHESTRATION coordinator shapes
- [x] READMEs — analysis/README.md (routing.py, roots.py), self/tests/README.md (R12, RB), root README feature-close row

## Learned
- `--unpinned-builder`'s only consumer is feature-close.sh.
- R12 fixtures: `$AT` = throwaway agentTooling with bare `.git`; features at `$AT/self/features`.

## Resume
- bash self/tests/routing-record.sh (green); bash self/tests/feature-lifecycle.sh; self/gate.sh
