# Coordination: ablation-wave

Session `4cba07a3-a87d-5001-97c1-4a7b4cc0510c`, a Claude Code cloud session started in
`/home/user` above its repositories (so its transcript records branch `HEAD` and no
repository's hooks ran in it), coordinated the tooling-ablation experiment and its
follow-ups from 2026-11-05 to 2026-11-11: vinylCatalogue `tooling-ablation`,
`split-tests-experiment` and the pin repair `pin-split-tests-delegate`; agentTooling
`harness-ablation-methods`, `ablation-harness-fixes`, `split-tests-method`,
`delegate-cost-claims`, the pin repair `pin-delegate-cost-claims-audit`, and
`coordinator-cost-records`, the feature that added this kind of record. It built nothing in
its own tree: every feature was built by an Agent delegate, claimed by that feature. It is
registered retroactively (`orchestration-start.sh ablation-wave --coordinator --session …`),
so `agent_tooling` is the commit the record was written at, not one the session ran under —
it ran under several. The window first closed at 2026-11-08T17:41:09Z, with
`coordinator-cost-records` unpriced; once that feature merged (#138) and had a cost record,
`session_window.to` was moved to 2026-11-11T14:06:53Z, past the build's hand-back and the
merge of #138, and the record recaptured. That instant is the turn that asked for a security
audit of #138's hook changes: from there on the session's work was hook hardening, recorded
separately in `../hook-hardening-wave/`, whose `from` is the same instant, so the two
windows partition the session and nothing is priced twice.

This is a **coordinator record** (`"kind": "coordinator"`): the session coordinated
several features by delegating each to an Agent subagent, and every delegate is claimed by
the feature it built (its brief header or a pin). The coordinator's own transcript — the
briefs, the analysis, the reading of results — is claimed by no feature, so it is priced
here, on a line of its own, with only its own `feature: none` delegates that no feature
claims: `orchestration-capture.sh --self ablation-wave` writes `planning.json`, and
`python3 analysis/report.py --self --orchestration ablation-wave --checkout
vinylCatalogue=<its checkout>` sets it beside every feature's `report.json` in `report.md`
and `report.json`. The record is no role: nothing is refused in the session or in its
delegates, which share its session id.

```json
{
  "slug": "ablation-wave",
  "kind": "coordinator",
  "session": "4cba07a3-a87d-5001-97c1-4a7b4cc0510c",
  "agent_tooling": "8f9e0b47b3aaadb60fa13bd43721a5dcc0b305b7",
  "session_window": {"from": "2026-11-05T16:39:00.566Z", "to": "2026-11-11T14:06:53Z"},
  "features": [
    {"repo": "agentTooling", "slug": "harness-ablation-methods", "session": null, "branch": null, "pr": "https://github.com/ssdesai/agentTooling/pull/130", "report": "self/features/harness-ablation-methods/report.json"},
    {"repo": "vinylCatalogue", "slug": "tooling-ablation", "session": null, "branch": null, "pr": "https://github.com/ssdesai/vinylCatalogue/pull/291", "report": "plans/features/tooling-ablation/report.json"},
    {"repo": "agentTooling", "slug": "ablation-harness-fixes", "session": null, "branch": null, "pr": "https://github.com/ssdesai/agentTooling/pull/132", "report": "self/features/ablation-harness-fixes/report.json"},
    {"repo": "vinylCatalogue", "slug": "split-tests-experiment", "session": null, "branch": null, "pr": "https://github.com/ssdesai/vinylCatalogue/pull/297", "report": "plans/features/split-tests-experiment/report.json"},
    {"repo": "agentTooling", "slug": "split-tests-method", "session": null, "branch": null, "pr": "https://github.com/ssdesai/agentTooling/pull/133", "report": "self/features/split-tests-method/report.json"},
    {"repo": "agentTooling", "slug": "delegate-cost-claims", "session": null, "branch": null, "pr": "https://github.com/ssdesai/agentTooling/pull/134", "report": "self/features/delegate-cost-claims/report.json"},
    {"repo": "vinylCatalogue", "slug": "pin-split-tests-delegate", "session": null, "branch": null, "pr": "https://github.com/ssdesai/vinylCatalogue/pull/309", "report": "plans/features/pin-split-tests-delegate/report.json"},
    {"repo": "agentTooling", "slug": "pin-delegate-cost-claims-audit", "session": null, "branch": null, "pr": "https://github.com/ssdesai/agentTooling/pull/136", "report": "self/features/pin-delegate-cost-claims-audit/report.json"},
    {"repo": "agentTooling", "slug": "coordinator-cost-records", "session": null, "branch": null, "pr": "https://github.com/ssdesai/agentTooling/pull/138", "report": "self/features/coordinator-cost-records/report.json"}
  ]
}
```
