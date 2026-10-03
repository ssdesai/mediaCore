# bounded-opening-stretch — cost and waste report

Generated 2026-09-10T14:10:52.903431+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $11.3323 | 85.6% |
| verify | $0.0000 | 0.0% |
| review | $1.9110 | 14.4% |
| **total** | **$13.2433** | 100.0% |

Sessions this feature shares: `e21abdc0-6f3b-4306-a18e-81272cadb107` (this feature's share $3.6553 of $20.4734), also claimed by agentTooling/self-corpus-identity. The shares of all claimants sum to the session's own cost, so summing these features' totals now counts it once, not once per feature.

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $11.3323, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $13.2433  
cost per file touched: $6.6216

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 51.5 | $11.3323 | $0.2203 |
| ↳ acceptance tests | 2.9 |  |  |
| ↳ implementation | 4.5 |  |  |
| ↳ gate | 4.9 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 5.3 | $1.9110 | $0.3579 |
| **total** | **56.8** | **$13.2433** | $0.2332 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **29.5 min** from 2026-09-10T03:55:33+00:00 to 2026-09-10T04:25:01+00:00, PR opened 2026-09-10T04:14:02+00:00.
Passes: review 5.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 5.4 min over 1 run(s).

## Cold-start tax

76600 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 25 | $1.9110 | 5.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 99-review-opus | 4 | 2 | 2.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 99-review-opus | 58 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 99-review-opus | analysis/capture_planning.py, self/review-report.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
