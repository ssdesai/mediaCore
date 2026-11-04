# recover-cost-at-close — cost and waste report

Generated 2026-09-10T14:11:12.747653+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $35.1062 | 93.1% |
| verify | $0.0000 | 0.0% |
| review | $2.6184 | 6.9% |
| **total** | **$37.7246** | 100.0% |

Sessions this feature shares: `2d8b1236-3e77-450f-bc9e-8165c0cf9f9c` (this feature's share $3.4934 of $58.4732), also claimed by agentTooling/stale-failed-sidecars, agentTooling/stream-capture-file-first. The shares of all claimants sum to the session's own cost, so summing these features' totals now counts it once, not once per feature.

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $35.1062, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $37.7246  
cost per file touched: $12.5749

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 147.7 | $35.1062 | $0.2377 |
| ↳ acceptance tests | 7.5 |  |  |
| ↳ implementation | 9.4 |  |  |
| ↳ gate | 32.7 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 6.6 | $2.6184 | $0.3989 |
| **total** | **154.2** | **$37.7246** | $0.2446 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **74.0 min** from 2026-09-06T14:10:19+00:00 to 2026-09-06T15:24:20+00:00, PR opened 2026-09-06T15:11:54+00:00.
Passes: review 6.7. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 6.6 min over 1 run(s).

## Cold-start tax

108449 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 31 | $2.6184 | 6.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 85-review-opus | 3 | 3 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 85-review-opus | 140 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 85-review-opus | analysis/report.py, feature-close.sh, self/review-report.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
