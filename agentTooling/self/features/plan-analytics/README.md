# plan-analytics

Tooling to measure what a feature cost to build — planning plus execution — and to
surface where delegated fanout wasted effort. Includes the `plans/` restructure that
makes a feature addressable in the first place.

## Goal

Every batch already leaves a full record of what the executors did (`.stream.jsonl`,
`.progress.md`), and every interactive planning session leaves one in
`~/.claude/projects/`. Nothing reads either. This feature adds durable capture and a
weekly report so a high-level feature can be priced end-to-end and compared against
prior features.

Three facts shape the design:

- **There was no such thing as a feature on disk.** Plans lived in one global queue
  (`plans/auto/…`) and completed batches were archived into branch-named folders by
  hand. Branch is the wrong key — this repo's `browseImages` branch hosted three
  distinct features — and "by hand" means the grouping was frequently just absent.
  So the queue moves under `plans/features/<slug>/`, and the feature directory becomes
  the unit holding a batch's manifest, plans, logs and cost records together.
- **The execution record is ephemeral.** `.stream.jsonl` is gitignored by design and
  0.2–1.5 MB per plan. Cost history dies with the machine unless a small sidecar is
  extracted and committed.
- **Planning cost lives elsewhere and carries no price.** Session transcripts have
  per-message `usage` and `model` but no cost field, so dollars must be computed from
  a rate table and then **frozen at capture time** — otherwise refreshing rates
  silently reprices completed features and destroys the cross-feature trend.

## Batches

This runs as two batches with a by-hand step between them, because the migration needs
bash and build executors have none.

**Batch A — `./agentTooling/run-plans.sh`** (48–50), then plan 51 by hand. Changes what
the runner reads, then moves what is on disk to match. Deliberately no verify plan: its
verification is a human running the migration with the tree in front of them, which is
plan 51.

**Batch B — `./agentTooling/run-batch.sh plan-analytics`** (52–57), then plan 58 by hand.
The analysis tooling, written against the layout batch A establishes.

Running B first would write path logic against a layout about to disappear, and plan 57
would verify it against un-migrated data.

## Plans

| Plan | Batch | What it does |
|---|---|---|
| `48-feature-scoped-runner-sonnet` | A | Runner resolves a feature slug and drains `plans/features/<slug>/<queue>/` instead of a fixed path. |
| `49-feature-layout-sync-and-docs-sonnet` | A | `sync-plans.sh` generates the feature tree; AGENT_PLANS.md gains the `Feature:` header rule and the manifest spec. |
| `50-plan-layout-migration-script-sonnet` | A | `migrate-plans-layout.sh`, plus a manifest for each of the five batches that already ran. |
| `51-migrate-plan-layout` | — | *Interactive.* Runs the migration, removes the legacy trees, smoke-tests the resolver. |
| `52-runner-usage-capture-sonnet` | B | `finalize_plan` writes a committed `<plan>.usage.json` from the run's final `result` event. |
| `53-analysis-pricing-haiku` | B | The rate table (per-model $/Mtok, cache multipliers, intro-price windows) and `analysis/README.md`. |
| `54-analysis-backfill-sonnet` | B | One-shot extraction of `usage.json` from `.stream.jsonl` files already on disk. |
| `55-analysis-capture-planning-sonnet` | B | Mines session transcripts by branch and window, excludes runner sessions, freezes cost. |
| `56-analysis-report-sonnet` | B | The report: cost roll-up, waste metrics, tripwires, and a cross-feature trend view. |
| `57-verify-sonnet` | B | Post-build verification. |
| `58-plan-analytics-install` | — | *Interactive.* Backfill, first capture + report across all six features, subtree push. |

## Metrics the report must produce

**Load-bearing** — feature cost roll-up (planning / build / verify / total); re-hunting
(the same tool target searched by ≥2 plans in a batch — AGENT_PLANS.md asserts this is
the dominant waste in multi-plan runs); churn ratio (edits ÷ unique files); cold-start
tax (cache-creation tokens summed across plans, the price of splitting); model fit
(turns vs. model tier); plan length vs. LoC changed.

**Tripwires, silent by default** — plan drift (files edited but unlisted, listed but
untouched); cross-plan edit overlap (plan N+1 editing text plan N wrote); two features
sharing a branch with no `session_window` separating them.

## Deliberately excluded

- **File-level collision as a metric.** Checked against batch 39–47: plans 44 and 45
  both edit `frontend/src/App.tsx` on entirely disjoint regions, and the runner is
  sequential so there is no race. File-level overlap is mostly false positives; only
  the region-level tripwire survives.
- **Retry/attempt tracking.** Observed failures are API 500s — infrastructure, not
  planning. Counting attempts would measure provider uptime. `subtype`, `is_error`,
  `num_turns`, and `duration_ms` in the ordinary capture already flag an abnormal run.
- **Semantic plan-adherence.** Not mechanically computable; the drift numbers pick
  which plans are worth reading plan-vs-diff by hand.
- **Automated price fetching.** A silently mis-parsed rate is worse than a stale
  constant with a visible date. The table carries `RATES_VERIFIED` and the report warns
  when it ages out; refreshing is a step in the weekly review.
- **Renumbering the historical plans per-feature.** Tempting once each feature owns a
  directory, but the global `01`–`58` sequence is referenced from commit messages,
  `PROJECT_FACTS.md` and the progress logs. Numbers stay global and stay unique.

## Machine-readable

```json
{
  "slug": "plan-analytics",
  "branches": ["browseImages"],
  "session_window": { "from": "2026-07-30T15:49:00", "to": "2026-07-30T19:03:00" },
  "plans": [
    "48-feature-scoped-runner-sonnet",
    "49-feature-layout-sync-and-docs-sonnet",
    "50-plan-layout-migration-script-sonnet",
    "52-runner-usage-capture-sonnet",
    "53-analysis-pricing-haiku",
    "54-analysis-backfill-sonnet",
    "55-analysis-capture-planning-sonnet",
    "56-analysis-report-sonnet",
    "57-verify-sonnet"
  ],
  "exclude_sessions": []
}
```
