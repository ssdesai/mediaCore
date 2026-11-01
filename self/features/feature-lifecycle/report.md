# feature-lifecycle — cost and waste report

Generated 2026-09-04T06:07:17.434686+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $73.8979 | 95.6% |
| verify | $0.0000 | 0.0% |
| review | $3.3835 | 4.4% |
| **total** | **$77.2814** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $73.8979, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $77.2814  
cost per file touched: $38.6407

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 811.6 | $73.8979 | $0.0911 |
| ↳ acceptance tests | 9.8 |  |  |
| ↳ implementation | 49.1 |  |  |
| ↳ gate | 0.0 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 6.8 | $3.3835 | $0.4999 |
| **total** | **818.4** | **$77.2814** | $0.0944 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **71.0 min** from 2026-09-03T18:55:24+00:00 to 2026-09-03T20:06:24+00:00, PR opened 2026-09-03T20:06:24+00:00.
Passes: review 6.9. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 6.8 min over 1 run(s).

## Cold-start tax

137333 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 31 | $3.3835 | 6.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 72-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 72-review-opus | 89 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 72-review-opus | feature-start.sh, self/review-report.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
