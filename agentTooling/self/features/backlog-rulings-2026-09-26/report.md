# backlog-rulings-2026-09-26 — cost and waste report

Generated 2026-09-27T06:08:34.415133+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $0.4261 | 50.8% |
| verify | $0.0000 | 0.0% |
| review | $0.4129 | 49.2% |
| **total** | **$0.8390** | 100.0% |

Sessions this feature shares: `85f7f627-01e8-42df-8c27-d9bcc1fa8c2b` (this feature's share $0.4261 of $5.2696), also claimed by musicMap/pull-agenttooling-pr66, vinylCatalogue/backlog-rulings-2026-09-26, vinylCatalogue/pull-agenttooling-pr66. The shares of all claimants sum to the session's own cost, so summing these features' totals now counts it once, not once per feature.

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $0.4261, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $0.8390  
cost per file touched: $0.4195

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 1.2 | $0.4261 | $0.3551 |
| verify | 0.0 | $0.0000 |  |
| review | 0.6 | $0.4129 | $0.6998 |
| **total** | **1.8** | **$0.8390** | $0.4687 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **0.9 min** from 2026-09-26T17:49:14+00:00 to 2026-09-26T17:50:11+00:00, PR opened 2026-09-26T17:50:11+00:00.
Passes: review 0.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 0.6 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $0.4261 | 1.2 | $0.0000 | 0.0 | $0.4129 | 0.6 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

36012 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 13 | $0.4129 | 0.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 44 | 56 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/BACKLOG.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-09-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
