# start-procedure-and-routing — cost and waste report

Generated 2026-09-16T22:37:25.879872+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $45.4404 | 92.9% |
| verify | $0.0000 | 0.0% |
| review | $3.4696 | 7.1% |
| **total** | **$48.9100** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $45.4404, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $24.4550  
cost per file touched: $16.3033

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 191.7 | $45.4404 | $0.2371 |
| ↳ acceptance tests | 8.1 |  |  |
| ↳ implementation | 151.4 |  |  |
| ↳ gate | 2.6 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 14.8 | $3.4696 | $0.2343 |
| **total** | **206.5** | **$48.9100** | $0.2369 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **204.2 min** from 2026-09-16T18:22:27+00:00 to 2026-09-16T21:46:37+00:00, PR opened 2026-09-16T21:46:37+00:00.
Passes: review 15.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 14.9 min over 2 run(s).

## Cold-start tax

172558 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 44 | $3.4696 | 14.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 105-review-opus | 4 | 3 | 1.33 |
| 106-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 105-review-opus | 129 | not computed: streams unavailable |
| 106-review-opus | 72 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 105-review-opus | analysis/routing.py, feature-start.sh, self/review-report.md | — |
| 106-review-opus | analysis/routing.py, self/review-report.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
