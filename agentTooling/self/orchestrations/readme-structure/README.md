# Orchestration: readme-structure

The Context loading section (items 1–9) of the owner's "Workflow efficiency changes" doc:
cutting what every session reads before it works, across agentTooling and its consumers.
It covers splitting oversized READMEs and specs, a README-index gate check, and a
vinylCatalogue A/B that compares the repo's restructured READMEs and spec with the repo
as it stands (arms that differ by repository commit, on a Discogs pre-fill fixture),
which decides whether the README redesign (items 1, 2, 8) ships. They are measured
together because they share one question: what reading costs and what it buys.

The orchestrator spawns one implementer session per feature and builds nothing itself.
It commits nothing except this record, which it pushes on its assigned branch as a
records-only PR; each feature's own record travels in that feature's PR. Cost is read
together: `orchestration-capture.sh readme-structure` prices the orchestrator's own transcript
(overhead) into `planning.json`, and `python3 analysis/report.py --orchestration readme-structure`
joins it with every feature's `report.json` into `report.md` and `report.json`.

## Outcome

- **Items 5, 7, 9 and 3b** shipped in humanNetworkMap (#273, #275, #277) and musicMap (#73, #74).
- **Item 6:** the README-index check shipped in agentTooling (#119). Consumers opt in once
  their agentTooling pull lands; that wiring is handed to the experiments orchestrator.
- **The A/B** (`discogsPrefillStructure`, vinylCatalogue #231): method direct, 2 repeats per
  arm, old arm `94f14bb` (monolithic spec) against new arm `c814667` (the restructure, #218).
  - Acceptance passed in all 4 cells.
  - Bytes read before the first edit: −30.3% (154,951 → 108,013 mean).
  - README bytes read: −77.2%.
  - Cost to green: −5.5% ($12.48 → $11.80).
  - The prediction held on the means; n=2 and noisy.
  - On the owner's decision the restructure (#218) merged.
  - Items 1, 2 and 8 (rolling the structure out beyond vinylCatalogue) are handed to the
    experiments orchestrator, along with the cost-at-equal-quality question.
- **Harness work the A/B needed** shipped in agentTooling:
  - per-arm repository commits (#121);
  - a per-arm spec path (#123);
  - the long-runs feature (#125), which gives a time budget between cells and
    `run.sh --reset` for a killed cell.
- **Features with no cost row:** `harness-spec-per-arm` was cancelled by the owner before it
  pushed anything, and its replacement is `harness-arm-spec`.

## Feature costs as reported by each feature

The sources are each PR's report or the implementer session's final figure. Where a figure is
a lower bound it says so. `report.py --orchestration` reads only the `report.json` files present
in this checkout, so this table is the complete per-feature view.

| repo | feature | PR | cost |
|---|---|---|---|
| agentTooling | readme-index-check | #119 | $5.52 |
| agentTooling | harness-arm-base | #121 | $10.41 |
| humanNetworkMap | split-root-readme | #273 | $1.14 |
| musicMap | folder-scoped-facts | #73 | $1.29 |
| humanNetworkMap | trim-project-facts | #275 | $1.67 |
| musicMap | trim-project-facts | #74 | not recorded here |
| vinylCatalogue | pull-agenttooling-pr121 | #213 | $1.33 |
| vinylCatalogue | readme-restructure | #218 | ≥ $40.87 |
| vinylCatalogue | discogs-prefill-fixture | #220 | $9.30 |
| agentTooling | harness-spec-per-arm (cancelled) | — | $3.23 |
| agentTooling | harness-arm-spec | #123 | $5.84 |
| humanNetworkMap | split-test-spec | #277 | ≈ $3.10 |
| vinylCatalogue | pull-agenttooling-pr123 | #219 | $1.09 |
| vinylCatalogue | discogs-prefill-structure-run | #231 | $56.20 harness (incl. $7.63 lost to a killed cell) + ≈ $4.21 coordinator |
| agentTooling | harness-long-runs | #125 | $8.74 |
| vinylCatalogue | pull-agenttooling-pr125 | #228 | $0.98 |
| **total** | | | **≈ $155** |

The orchestrator's own overhead is priced in `planning.json` at $41.73. That figure is a lower
bound: the session's transcript is filed under two project directories, because the working
directory moved mid-orchestration, and the capture prices one of them (its `warnings`). So the
group total is about $197 or more. The `report.md` beside this README lists each feature as
unpriced only because the record carries no `report` paths: those reports live in the
consumer repositories, or on a newer agentTooling main than this checkout. The table above
carries their figures.

```json
{
  "slug": "readme-structure",
  "session": "299d0a61-3b3f-509b-b174-2a7951389f6d",
  "agent_tooling": "e4e08b9b6b66259ae09457396dc8c3b516722fbe",
  "session_window": {"from": "2026-11-03T21:30:42Z", "to": "2026-11-05T04:03:31Z"},
  "features": [
    {"repo": "agentTooling", "slug": "harness-arm-base", "session": "session_0175k4pHnERXTZPyfC4DCga6", "branch": "claude/harness-arm-base", "pr": "https://github.com/ssdesai/agentTooling/pull/121", "report": null},
    {"repo": "agentTooling", "slug": "readme-index-check", "session": "session_0175k4pJ4uGq4Bd46b7oF8Q4", "branch": "claude/readme-index-check", "pr": "https://github.com/ssdesai/agentTooling/pull/119", "report": null},
    {"repo": "humanNetworkMap", "slug": "split-root-readme", "session": "session_0175k4pJNXv22YB9tspg2jJB", "branch": "claude/split-root-readme", "pr": "https://github.com/ssdesai/humanNetworkMap/pull/273", "report": null},
    {"repo": "musicMap", "slug": "folder-scoped-facts", "session": "session_0175k4pEu8KHASySFnLqfqx2", "branch": "claude/folder-scoped-facts", "pr": "https://github.com/ssdesai/musicMap/pull/73", "report": null},
    {"repo": "humanNetworkMap", "slug": "trim-project-facts", "session": "session_0175k4pJCCKCAw4FG5XYavv1", "branch": "claude/trim-project-facts", "pr": "https://github.com/ssdesai/humanNetworkMap/pull/275", "report": null},
    {"repo": "musicMap", "slug": "trim-project-facts", "session": "session_0175k4pJ5jdS3XjHFC1okNHP", "branch": "claude/trim-project-facts", "pr": "https://github.com/ssdesai/musicMap/pull/74", "report": null},
    {"repo": "vinylCatalogue", "slug": "pull-agenttooling-pr121", "session": "session_0175k4pHemTTXrHY55w8kRiD", "branch": "claude/pull-agenttooling-pr121", "pr": "https://github.com/ssdesai/vinylCatalogue/pull/213", "report": null},
    {"repo": "vinylCatalogue", "slug": "readme-restructure", "session": "session_0175k4pF7LYD5wX4Pm9k3k3A", "branch": "claude/readme-restructure", "pr": "https://github.com/ssdesai/vinylCatalogue/pull/218", "report": null},
    {"repo": "vinylCatalogue", "slug": "discogs-prefill-fixture", "session": "session_0175k4pJahf79K8ibWquQL11", "branch": "claude/discogs-prefill-fixture", "pr": "https://github.com/ssdesai/vinylCatalogue/pull/220", "report": null},
    {"repo": "agentTooling", "slug": "harness-spec-per-arm", "session": "session_0175k4pFQWuNPag4SNUrgazv", "branch": "claude/harness-spec-per-arm", "pr": null, "report": null},
    {"repo": "agentTooling", "slug": "harness-arm-spec", "session": "session_0175k4pEMgxZDeEWhxhF2mwF", "branch": "claude/harness-arm-spec", "pr": "https://github.com/ssdesai/agentTooling/pull/123", "report": null},
    {"repo": "humanNetworkMap", "slug": "split-test-spec", "session": "session_0175k4pHFEr3BMrPPpB8zGwJ", "branch": "claude/split-test-spec", "pr": "https://github.com/ssdesai/humanNetworkMap/pull/277", "report": null},
    {"repo": "vinylCatalogue", "slug": "pull-agenttooling-pr123", "session": "session_0175k4pFzvbaQVTzYqfuTSfv", "branch": "claude/pull-agenttooling-pr123", "pr": "https://github.com/ssdesai/vinylCatalogue/pull/219", "report": null},
    {"repo": "vinylCatalogue", "slug": "discogs-prefill-structure-run", "session": "session_0175k4pF2iUMtLo17keMZCrE", "branch": "claude/discogs-prefill-structure-run", "pr": "https://github.com/ssdesai/vinylCatalogue/pull/231", "report": null},
    {"repo": "agentTooling", "slug": "harness-long-runs", "session": "session_0175k4pJ8U5mE6FcoSdCEq1h", "branch": "claude/harness-long-runs", "pr": "https://github.com/ssdesai/agentTooling/pull/125", "report": null},
    {"repo": "vinylCatalogue", "slug": "pull-agenttooling-pr125", "session": "session_0175k4pGV3HhqqNQ7jfDYgqE", "branch": "claude/pull-agenttooling-pr125", "pr": "https://github.com/ssdesai/vinylCatalogue/pull/228", "report": null}
  ]
}
```
