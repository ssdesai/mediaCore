# Experiment harness

The `harness/` directory — `harness/SPEC.md` and the runner, templates and README beside it — was built on 2026-08-29 by one opus delegate from a coordinator sitting in humanNetworkMap, on branch `experimentHarness` here and in humanNetworkMap (agentTooling PR #18, humanNetworkMap PR #80). It predates the self-feature lifecycle, so no manifest was written for it and its $18.24 builder stood unclaimed. This directory is that manifest, after the fact: the branch selects any session that ran on it, and the pin claims the builder whose parent was on `main` elsewhere. Built by hand, in the sense that no plan queue ran.

```json
{
  "slug": "experiment-harness",
  "method": "hand",
  "subagents": ["a17a18ebe0d95de63"],
  "plans": [],
  "branches": ["experimentHarness"],
  "session_window": {"from": "2026-08-29T16:41:00Z", "to": "2026-08-29T17:27:42Z"},
  "exclude_sessions": []
}
```
