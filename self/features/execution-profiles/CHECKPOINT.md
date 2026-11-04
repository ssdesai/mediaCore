# Checkpoint: execution-profiles

## Round 2 (rework of escalation 01: the gate never resumes under a runner)

status: committed
updated: 2026-10-05T21:30:37Z
gate: not run (the coordinator owns ./self/gate.sh); gate-resume, template-versions,
      sync-check run individually and green; bash -n on the touched scripts clean

### Slices
- [x] acceptance tests — self/tests/gate-resume.sh K11a-c + R1-R4 (f584532; R2, R3, K11b red before the fix)
- [x] 1. templates/plans/gate.sh + self/gate.sh: GATE_FEATURES_DIR in GATE_TREE_EXCLUDES;
      TEMPLATE_VERSIONS re-recorded at v3
- [x] 2. NOTES ruling 42, design §8/§10, tests README row, READMEs describing the tree sha

### Resume
- Nothing to resume. Next is the coordinator's ./self/gate.sh, then the round-2 review.

## Slice A / B (round 1)

status: committed (d77e1bd tests, 950e882 build; slice B 830eae0)
gate: round 1's was run by the coordinator, green.
- Slice A: detector + layout, confinement, cloud start, derived router, forge, pr.sh v6, open-session v4.
- Slice B: environment adapters, SessionStart wiring, resumable gate (gate.sh v3), gate key, sleep rewrite, doctrine.
