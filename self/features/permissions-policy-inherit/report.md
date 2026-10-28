# permissions-policy-inherit — cost and waste report

Generated 2026-09-16T18:10:13.936698+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $26.7649 | 91.8% |
| verify | $0.0000 | 0.0% |
| review | $2.3791 | 8.2% |
| **total** | **$29.1439** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $26.7649, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $29.1439  
cost per file touched: $14.5720

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 176.6 | $26.7649 | $0.1516 |
| ↳ acceptance tests | 7.5 |  |  |
| ↳ implementation | 6.8 |  |  |
| ↳ gate | 12.5 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 3.4 | $2.3791 | $0.6940 |
| **total** | **180.0** | **$29.1439** | $0.1619 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **109.6 min** from 2026-09-16T16:14:00+00:00 to 2026-09-16T18:03:34+00:00, PR opened 2026-09-16T18:03:34+00:00.
Passes: review 3.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.5 min over 2 run(s).

## Cold-start tax

127865 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 31 | $2.3791 | 3.4 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 100-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 100-review-opus | 108 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 100-review-opus | hooks/wire-settings.py, self/review-report.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
