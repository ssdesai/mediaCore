# tooling-backlog-2026-09-06 — cost and waste report

Generated 2026-09-07T15:42:50.746710+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $55.8242 | 93.7% |
| verify | $0.0000 | 0.0% |
| review | $3.7493 | 6.3% |
| **total** | **$59.5735** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $55.8242, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $59.5735  
cost per file touched: $19.8578

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 1107.8 | $55.8242 | $0.0504 |
| ↳ acceptance tests | 12.4 |  |  |
| ↳ implementation | 333.4 |  |  |
| ↳ gate | 2.0 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 7.3 | $3.7493 | $0.5168 |
| **total** | **1115.0** | **$59.5735** | $0.0534 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **369.5 min** from 2026-09-06T22:32:55+00:00 to 2026-09-07T04:42:23+00:00, PR opened 2026-09-07T04:29:53+00:00.
Passes: review 7.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 7.3 min over 1 run(s).

## Cold-start tax

141720 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 40 | $3.7493 | 7.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 87-review-opus | 3 | 3 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 87-review-opus | 90 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 87-review-opus | self/BACKLOG.md, self/review-report.md, sync-plans.sh | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
