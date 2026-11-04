# Orchestration: rehearsal-prep

The last fixes before the harness is rehearsed with a real `claude`: the cloud start's tree
guard (the start commit carries only the feature directory, and a tree that changes while
the base gate runs is refused; the implementer brief template runs the start in the
background and waits) and the smoke test's end-to-end pricing of an ordinary cell plus the
`stages {review: false}` run assertion. This wave starts where the `program-ab` record's
window ends, so the orchestrator's overhead is not counted twice. Run by orchestrator
session `2483ee85-6358-53d1-b3fe-c7f1f895ab08` with one Sonnet implementer session per
feature, each on its own `claude/<slug>` branch.

The orchestrator builds nothing itself and commits nothing except this record, which it
pushes on its assigned branch as a records-only PR; each feature's own record travels in
that feature's PR. Cost is read
together: `orchestration-capture.sh rehearsal-prep` prices the orchestrator's own transcript
(overhead) into `planning.json`, and `python3 analysis/report.py --orchestration rehearsal-prep`
joins it with every feature's `report.json` into `report.md` and `report.json`.

```json
{
  "slug": "rehearsal-prep",
  "session": "2483ee85-6358-53d1-b3fe-c7f1f895ab08",
  "agent_tooling": "bc3835d880540da2150ee61df89818992e902445",
  "session_window": {"from": "2026-10-31T02:07:46Z", "to": "2026-10-31T14:13:36Z"},
  "features": [
    {"repo": "agentTooling", "slug": "start-tree-guard", "session": "51bc5aac-a3b8-5131-b8ea-e035c0ecf5d7", "branch": "claude/start-tree-guard", "pr": "https://github.com/ssdesai/agentTooling/pull/115", "report": "self/features/start-tree-guard/report.json"},
    {"repo": "agentTooling", "slug": "smoke-priced-cells", "session": "1416683c-041a-52d3-8142-aa1450e27a65", "branch": "claude/smoke-priced-cells", "pr": "https://github.com/ssdesai/agentTooling/pull/114", "report": "self/features/smoke-priced-cells/report.json"}
  ]
}
```
