# track-artist-field — cost and waste report

Generated 2026-09-07T15:49:26.471043+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $35.9462 | 94.7% |
| verify | $0.0000 | 0.0% |
| review | $2.0129 | 5.3% |
| **total** | **$37.9591** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $35.9462, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $37.9591  
cost per file touched: $7.5918

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 1076.1 | $35.9462 | $0.0334 |
| ↳ acceptance tests | 2.1 |  |  |
| ↳ implementation | 3.6 |  |  |
| ↳ gate | 1.0 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 4.8 | $2.0129 | $0.4150 |
| **total** | **1081.0** | **$37.9591** | $0.0351 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **22.6 min** from 2026-09-06T22:36:13+00:00 to 2026-09-06T22:58:48+00:00, PR opened 2026-09-06T22:49:25+00:00.
Passes: review 5.0. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 4.9 min over 1 run(s).

## Cold-start tax

79562 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 32 | $2.0129 | 4.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 6 | 5 | 1.20 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 60 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | INTEGRATION.md, plans/BACKLOG.md, plans/review-report.md, src/mediacore/README.md, tests/README.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
