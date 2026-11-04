# sweep-retirement-and-audit-fixes — cost and waste report

Generated 2026-09-17T17:36:57.999175+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $41.1447 | 96.4% |
| verify | $0.0000 | 0.0% |
| review | $1.5232 | 3.6% |
| **total** | **$42.6679** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $41.1447, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $42.6679  
cost per file touched: $42.6679

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 53.6 | $41.1447 | $0.7674 |
| ↳ acceptance tests | 8.9 |  |  |
| ↳ implementation | 109.7 |  |  |
| ↳ gate | 3.6 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 1.6 | $1.5232 | $0.9675 |
| **total** | **55.2** | **$42.6679** | $0.7731 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **125.4 min** from 2026-09-17T15:31:32+00:00 to 2026-09-17T17:36:56+00:00, PR opened 2026-09-17T17:36:56+00:00.
Passes: review 1.7. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.6 min over 1 run(s).

## Cold-start tax

82657 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 19 | $1.5232 | 1.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 109-review-opus | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 109-review-opus | 116 | 58 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 109-review-opus | self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
