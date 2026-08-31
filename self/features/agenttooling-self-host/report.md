# agenttooling-self-host — cost and waste report

Generated 2026-08-05T18:39:52.771637+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $11.3702 | 69.2% |
| build | $3.6107 | 22.0% |
| verify | $1.4520 | 8.8% |
| **total** | **$16.4329** | 100.0% |

cost per plan: $3.2866  
cost per file touched: $0.7825

## Cold-start tax

313498 cache-creation tokens across build/verify plans.

## Model fit

| model | plan count | total turns | total cost usd | flags |
|---|---|---|---|---|
| haiku | 1 | 13 | $0.1599 | plan 60-self-corpus-scaffold-haiku took 13 turns on haiku (> 8, may have needed more judgment than haiku gives) |
| sonnet | 4 | 142 | $4.9028 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 59-runner-self-mode-sonnet | 18 | 7 | 2.57 |
| 60-self-corpus-scaffold-haiku | 8 | 8 | 1.00 |
| 61-self-gate-sonnet | 1 | 1 | 1.00 |
| 62-analysis-self-mode-sonnet | 22 | 5 | 4.40 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 59-runner-self-mode-sonnet | 271 | 227 |
| 60-self-corpus-scaffold-haiku | 326 | 252 |
| 61-self-gate-sonnet | 140 | 161 |
| 62-analysis-self-mode-sonnet | 292 | 251 |
| 63-verify-sonnet | 93 | 0 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/README.md` | Read | 59-runner-self-mode-sonnet, 63-verify-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/RUNNER.md` | Read | 59-runner-self-mode-sonnet, 63-verify-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/analysis/README.md` | Read | 62-analysis-self-mode-sonnet, 63-verify-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/analysis/backfill_usage.py` | Read | 62-analysis-self-mode-sonnet, 63-verify-sonnet |
| `/Users/sahildesai/dev/vinylCatalogue/agentTooling/analysis/roots.py` | Read | 62-analysis-self-mode-sonnet, 63-verify-sonnet |

## Plan drift

none found.

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| plan-runner-lib.sh | 59-runner-self-mode-sonnet | 59-runner-self-mode-sonnet | 253 |

## Warnings

- plan 63-verify-sonnet has 0 files_edited; excluded from churn ratio

---

Rates last verified 2026-07-30 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
