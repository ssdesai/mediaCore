# plan-analytics — cost and waste report

Generated 2026-08-05T18:39:53.431973+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $39.2380 | 85.2% |
| build | $5.4695 | 11.9% |
| verify | $1.3526 | 2.9% |
| **total** | **$46.0601** (partial) | 100.0% |

**This total is a lower bound** — at least one input is unavailable, so the real cost is higher and the percentages are skewed toward whatever survived.

cost per plan: $5.1178  
cost per file touched: $2.0936

## Cold-start tax

511368 cache-creation tokens across build/verify plans.

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
| 48-feature-scoped-runner-sonnet | 310 | 268 |
| 49-feature-layout-sync-and-docs-sonnet | 414 | 157 |
| 50-plan-layout-migration-script-sonnet | 498 | 395 |
| 52-runner-usage-capture-sonnet | 208 | 96 |
| 53-analysis-pricing-haiku | 209 | 152 |
| 54-analysis-backfill-sonnet | 159 | 223 |
| 55-analysis-capture-planning-sonnet | 254 | 379 |
| 56-analysis-report-sonnet | 221 | 764 |
| 57-verify-sonnet | 81 | 0 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `agentTooling/analysis/*` | Glob | 54-analysis-backfill-sonnet, 55-analysis-capture-planning-sonnet, 56-analysis-report-sonnet |
| `plans/features/*/README.md` | Glob | 50-plan-layout-migration-script-sonnet, 55-analysis-capture-planning-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/README.md` | Read | 49-feature-layout-sync-and-docs-sonnet, 50-plan-layout-migration-script-sonnet, 53-analysis-pricing-haiku, 57-verify-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/RUNNER.md` | Read | 48-feature-scoped-runner-sonnet, 54-analysis-backfill-sonnet, 56-analysis-report-sonnet, 57-verify-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/analysis/README.md` | Read | 54-analysis-backfill-sonnet, 55-analysis-capture-planning-sonnet, 56-analysis-report-sonnet, 57-verify-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/analysis/backfill_usage.py` | Read | 54-analysis-backfill-sonnet, 55-analysis-capture-planning-sonnet, 56-analysis-report-sonnet, 57-verify-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/analysis/capture_planning.py` | Read | 56-analysis-report-sonnet, 57-verify-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/analysis/pricing.py` | Read | 53-analysis-pricing-haiku, 54-analysis-backfill-sonnet, 55-analysis-capture-planning-sonnet, 56-analysis-report-sonnet, 57-verify-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/plan-runner-lib.sh` | Read | 48-feature-scoped-runner-sonnet, 52-runner-usage-capture-sonnet, 54-analysis-backfill-sonnet, 57-verify-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/plans/features/plan-analytics/README.md` | Read | 50-plan-layout-migration-script-sonnet, 55-analysis-capture-planning-sonnet, 56-analysis-report-sonnet |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 48-feature-scoped-runner-sonnet | — | plan-runner-lib.sh |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| README.md | 49-feature-layout-sync-and-docs-sonnet | 50-plan-layout-migration-script-sonnet | 248 |
| analysis/backfill_usage.py | 54-analysis-backfill-sonnet | 54-analysis-backfill-sonnet | 116 |
| analysis/backfill_usage.py | 54-analysis-backfill-sonnet | 54-analysis-backfill-sonnet | 133 |
| analysis/README.md | 53-analysis-pricing-haiku | 54-analysis-backfill-sonnet | 867 |
| analysis/README.md | 54-analysis-backfill-sonnet | 55-analysis-capture-planning-sonnet | 779 |
| analysis/README.md | 55-analysis-capture-planning-sonnet | 56-analysis-report-sonnet | 531 |
| analysis/README.md | 55-analysis-capture-planning-sonnet | 56-analysis-report-sonnet | 586 |
| analysis/README.md | 53-analysis-pricing-haiku | 56-analysis-report-sonnet | 163 |
| analysis/README.md | 54-analysis-backfill-sonnet | 56-analysis-report-sonnet | 163 |
| analysis/README.md | 55-analysis-capture-planning-sonnet | 56-analysis-report-sonnet | 163 |

## Warnings

- plan 57-verify-sonnet has 2 attempt(s) with no recorded cost (sessions: 0aa7f47d-4f02-43d1-a97d-0c431e21a27d, 886aa05b-2498-4e91-9553-ded8cc1dbbb5); its total is a lower bound
- plan 57-verify-sonnet has 0 files_edited; excluded from churn ratio

---

Rates last verified 2026-07-30 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
