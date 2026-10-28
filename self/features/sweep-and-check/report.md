# sweep-and-check — cost and waste report

Generated 2026-09-04T06:07:47.273211+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $6.5230 | 37.2% |
| build | $6.8379 | 39.0% |
| verify | $0.6432 | 3.7% |
| review | $3.5468 | 20.2% |
| **total** | **$17.5510** | 100.0% |

**Skipped, not missing:** 80-level-scripts-sonnet. The runner filed each without running it — its level gate was already green — so there is no `usage.json` and no cost to roll up.

cost per plan: $1.5955  
cost per file touched: $0.6500

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| planning: sessions | 0.0 | $0.0000 |  |
| planning: delegates | 13.2 | $6.5230 | $0.4954 |
| build | 40.7 | $6.8379 | $0.1679 |
| verify | 2.5 | $0.6432 | $0.2569 |
| review | 7.8 | $3.5468 | $0.4549 |
| **total** | **64.2** | **$17.5510** | $0.2734 |

Planning minutes are transcript spans: a delegate's span is its working time, a session's includes every minute nobody was typing, so the delegates row is the planning figure for a feature planned by delegates and the sessions row for one planned by hand. Build, verify and review minutes are summed over plans, so a parallel pair counts twice — the wall clock below does not.

Wall clock, as the runner saw it: **55.5 min** from 2026-09-04T04:49:22+00:00 to 2026-09-04T05:44:52+00:00, PR opened 2026-09-04T05:44:52+00:00.
Passes: build 41.6, verify 2.5, review 7.9. Gates: 0.7 min over 1 run(s). Plans as timed by the runner: 51.2 min over 10 run(s).

## Cold-start tax

938749 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| haiku | 1 | 38 | $0.5232 | 4.6 | plan 81-docs-haiku took 38 turns on haiku (> 8, may have needed more judgment than haiku gives) |
| opus | 1 | 44 | $3.5468 | 7.8 |  |
| sonnet | 8 | 168 | $6.9579 | 38.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 73-tests-check-plans-sonnet | 4 | 3 | 1.33 |
| 74-tests-sync-check-sonnet | 2 | 2 | 1.00 |
| 75-tests-sweep-sonnet | 5 | 2 | 2.50 |
| 76-check-plans-sonnet | 4 | 3 | 1.33 |
| 77-sync-check-and-update-sonnet | 9 | 9 | 1.00 |
| 78-sweep-sonnet | 2 | 2 | 1.00 |
| 79-zero-with-evidence-sonnet | 6 | 4 | 1.50 |
| 81-docs-haiku | 19 | 9 | 2.11 |
| 83-review-opus | 8 | 7 | 1.14 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 73-tests-check-plans-sonnet | 157 | not computed: streams unavailable |
| 74-tests-sync-check-sonnet | 130 | not computed: streams unavailable |
| 75-tests-sweep-sonnet | 94 | not computed: streams unavailable |
| 76-check-plans-sonnet | 119 | not computed: streams unavailable |
| 77-sync-check-and-update-sonnet | 132 | not computed: streams unavailable |
| 78-sweep-sonnet | 86 | not computed: streams unavailable |
| 79-zero-with-evidence-sonnet | 92 | not computed: streams unavailable |
| 81-docs-haiku | 133 | not computed: streams unavailable |
| 82-verify-sonnet | 37 | not computed: streams unavailable |
| 83-review-opus | 36 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 83-review-opus | README.md, RUNNER.md, analysis/README.md, check-plans.sh, self/review-report.md, self/tests/README.md, self/tests/check-plans.sh | — |

## Cross-plan edit overlap

not computed: streams unavailable

## Warnings

- plan 80-level-scripts-sonnet was filed as skipped by the runner (its level gate was green); it never ran, so it has no usage.json by design
- plan 82-verify-sonnet has 0 files_edited; excluded from churn ratio

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
