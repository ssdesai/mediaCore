# Checkpoint: manifest-pin-subagent

status: committed
updated: 2026-09-26T18:32:58Z
gate: === gate: done — all checks passed ===

## Slices
- [x] acceptance tests — self/tests/manifest-pin-subagent.sh (22 red), feature-lifecycle.sh C1i2/C2f-C2i, wired in self/gate.sh; committed
- [x] 1. manifest.py pin-subagent (AGENT_ID_RE, SUBAGENTS_KEY, refusals)
- [x] 2. capture_planning.parse_manifest -> routing.parse_manifest
- [x] 3. pin advice names the command: feature-capture.sh warn line, capture_planning list_subagents advice lines
- [x] 4. docs: LIFECYCLE §4 + rule 1, TEMPLATE subagents bullet, ORCHESTRATION coordinator shapes, AGENT_DIRECT, AGENT_PLANS
- [x] 5. manifest prose, BACKLOG deletions, NOTES.md
- [x] READMEs: analysis/README.md, self/tests/README.md, root README.md, self/PROJECT_FACTS.md
- [x] gate green (1043 ok lines, VERDICT all checks passed), commit

## Learned
- Every real agent id on this machine is `a` + 16 lowercase hex; fixtures use 17 hex.
- session-claims.sh patches `cp.parse_manifest` as a module global; the import keeps it counting.
- TEMPLATE.md is a generated stub: no template-version, no TEMPLATE_VERSIONS row.

## Resume
- git status --short; git log --oneline backlog-rulings-2026-09-26..HEAD
- bash self/tests/manifest-pin-subagent.sh, then self/gate.sh and self/gate-report.txt
