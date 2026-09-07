# recovered-duration-lower-bound — cost and waste report

Generated 2026-09-07T20:03:41.797466+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $69.3938 | 95.6% |
| verify | $0.0000 | 0.0% |
| review | $3.1853 | 4.4% |
| **total** | **$72.5791** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $69.3938, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $72.5791  
cost per file touched: $18.1448

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 1357.3 | $69.3938 | $0.0511 |
| ↳ acceptance tests | 5.5 |  |  |
| ↳ implementation | 13.5 |  |  |
| ↳ gate | 1.9 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 7.0 | $3.1853 | $0.4558 |
| **total** | **1364.3** | **$72.5791** | $0.0532 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **210.8 min** from 2026-09-07T16:18:18+00:00 to 2026-09-07T19:49:07+00:00, PR opened 2026-09-07T19:30:08+00:00.
Passes: review 7.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 7.0 min over 2 run(s).

## Cold-start tax

135231 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 44 | $3.1853 | 7.0 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 88-review-opus | 5 | 4 | 1.25 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 88-review-opus | 65 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 88-review-opus | analysis/README.md, analysis/report.py, self/features/recovered-duration-lower-bound/NOTES.md, self/review-report.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
