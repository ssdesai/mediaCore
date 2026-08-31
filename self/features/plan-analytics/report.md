# plan-analytics — cost and waste report

Generated 2026-08-27T21:32:00.153466+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $41.0559 | 81.1% |
| build | $5.4695 | 10.8% |
| verify | $4.0929 | 8.1% |
| review | $0.0000 | 0.0% |
| **total** | **$50.6183** | 100.0% |

cost per plan: $5.6243  
cost per file touched: $2.3008

$2.7403 of the total above is **derived**, not measured — priced from session transcripts by recover_attempts.py for attempts the CLI itself never reported a cost for.

## Cold-start tax

511368 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | flags |
|---|---|---|---|---|
| haiku | 1 | 9 | $0.1146 | plan 53-analysis-pricing-haiku took 9 turns on haiku (> 8, may have needed more judgment than haiku gives) |
| sonnet | 8 | 159 | $6.7075 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 48-feature-scoped-runner-sonnet | 16 | 5 | 3.20 |
| 49-feature-layout-sync-and-docs-sonnet | 17 | 6 | 2.83 |
| 50-plan-layout-migration-script-sonnet | 7 | 7 | 1.00 |
| 52-runner-usage-capture-sonnet | 5 | 2 | 2.50 |
| 53-analysis-pricing-haiku | 3 | 3 | 1.00 |
| 54-analysis-backfill-sonnet | 4 | 2 | 2.00 |
| 55-analysis-capture-planning-sonnet | 2 | 2 | 1.00 |
| 56-analysis-report-sonnet | 4 | 2 | 2.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 48-feature-scoped-runner-sonnet | 310 | not computed: streams unavailable |
| 49-feature-layout-sync-and-docs-sonnet | 414 | not computed: streams unavailable |
| 50-plan-layout-migration-script-sonnet | 498 | not computed: streams unavailable |
| 52-runner-usage-capture-sonnet | 208 | not computed: streams unavailable |
| 53-analysis-pricing-haiku | 209 | not computed: streams unavailable |
| 54-analysis-backfill-sonnet | 159 | not computed: streams unavailable |
| 55-analysis-capture-planning-sonnet | 254 | not computed: streams unavailable |
| 56-analysis-report-sonnet | 221 | not computed: streams unavailable |
| 57-verify-sonnet | 81 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 48-feature-scoped-runner-sonnet | — | plan-runner-lib.sh |

## Cross-plan edit overlap

not computed: streams unavailable

## Warnings

- plan 57-verify-sonnet has 2 attempt(s) priced from session transcripts rather than reported by the CLI (sessions: 0aa7f47d-4f02-43d1-a97d-0c431e21a27d, 886aa05b-2498-4e91-9553-ded8cc1dbbb5)
- plan 57-verify-sonnet has 0 files_edited; excluded from churn ratio

---

Rates last verified 2026-08-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
