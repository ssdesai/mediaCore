# Orchestration: program-ab

The program-level A/B tooling: the orchestrator brief template, the program ledger row and
scorecard section, and the program-cells driver. This wave starts where the
`agenttooling-roles` record's window ends, so the orchestrator's overhead is not counted
twice. It was run by orchestrator session `2483ee85-6358-53d1-b3fe-c7f1f895ab08` with one
Sonnet implementer session per feature, each on its own `claude/<slug>` branch.

The orchestrator builds nothing itself and commits nothing except this record, which it
pushes on its assigned branch as a records-only PR; each feature's own record travels in
that feature's PR. Cost is read together: `orchestration-capture.sh program-ab` prices the
orchestrator's own transcript (overhead) into `planning.json`, and
`python3 analysis/report.py --orchestration program-ab` joins it with every feature's
`report.json` into `report.md` and `report.json`.

```json
{
  "slug": "program-ab",
  "session": "2483ee85-6358-53d1-b3fe-c7f1f895ab08",
  "agent_tooling": "3e6c6a14d74814a8266c05d360002e871556be2f",
  "session_window": {"from": "2026-10-30T21:41:50Z", "to": "2026-10-31T02:07:46Z"},
  "features": [
    {"repo": "agentTooling", "slug": "orchestrator-brief", "session": "bf303c6e-00d5-592c-83c4-832d6c671078", "branch": "claude/orchestrator-brief", "pr": "https://github.com/ssdesai/agentTooling/pull/109", "report": "self/features/orchestrator-brief/report.json"},
    {"repo": "agentTooling", "slug": "program-scorecard", "session": "d5a2e355-4acd-55b3-9c59-5bbb80ee1861", "branch": "claude/program-scorecard", "pr": "https://github.com/ssdesai/agentTooling/pull/110", "report": "self/features/program-scorecard/report.json"},
    {"repo": "agentTooling", "slug": "program-cells", "session": "2e6bd575-5a95-5f42-9c8e-8ce6cd8ce0e7", "branch": "claude/program-cells", "pr": "https://github.com/ssdesai/agentTooling/pull/111", "report": "self/features/program-cells/report.json"},
    {"repo": "agentTooling", "slug": "harness-claim-root", "session": "c4a8f27a-fe62-5ac9-bcee-06b9e6638710", "branch": "claude/harness-claim-root", "pr": "https://github.com/ssdesai/agentTooling/pull/113", "report": "self/features/harness-claim-root/report.json"}
  ]
}
```
