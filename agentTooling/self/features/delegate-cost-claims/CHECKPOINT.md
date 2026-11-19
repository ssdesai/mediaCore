# Checkpoint: delegate-cost-claims

status: committed
updated: 2026-11-07T19:30:00Z
gate: see self/gate-report.txt (run by the coordinator after the build)

## Slices
- [x] acceptance tests — self/tests/delegate-cost-claims.sh, self/tests/hook-brief-header.sh,
      feature-lifecycle.sh UB/UC (red on main: no --claim-check, no auto-claim, no header deny)
- [x] 1. hooks/brief_header.py — the one header definition; capture_planning reads it by path
- [x] 2. capture_planning: subagent_rows/session_rows, briefed_delegates, auto_claim_briefed,
      capture_feature(dry_run, ignore_to), claim_check, --claim-check
- [x] 3. manifest.py allow-unclaimed; report.py warning
- [x] 4. feature-close.sh claim check and --allow-unclaimed
- [x] 5. hook brief-header deny (orchestrator deny first, unchanged)
- [x] 6. fixtures copy hooks/brief_header.py; existing tests updated for auto-claim
- [x] READMEs: CONVENTIONS, LIFECYCLE, ORCHESTRATION, AGENT_DIRECT, README, analysis/,
      hooks/, self/tests/, self/features/, PROJECT_FACTS, BACKLOG, TEMPLATE
- [x] ablation-harness-fixes record repair (pin a93805d6e49ede750, --recapture)

## Learned
- feature-close's `S: PR` commit adds everything dirty, so a fence written before the PR
  rides it; the claim check therefore writes nothing and the auto-claim's pin is left to
  the capture.

## Resume
- git -C /home/user/agentTooling-delegate-cost-claims status --short
- bash self/tests/delegate-cost-claims.sh; bash self/tests/hook-brief-header.sh
- ./self/gate.sh
