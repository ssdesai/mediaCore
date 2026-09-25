# backlog-mirror-cleanup — cost and waste report

Generated 2026-09-25T11:36:28.562272+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $0.0000 | 0.0% |
| verify | $0.0000 | 0.0% |
| review | $0.3843 | 100.0% |
| **total** | **$0.3843** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $0.0000, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $0.3843  
cost per file touched: $0.1922

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 0.0 | $0.0000 |  |
| verify | 0.0 | $0.0000 |  |
| review | 0.6 | $0.3843 | $0.5973 |
| **total** | **0.6** | **$0.3843** | $0.5973 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **1.1 min** from 2026-09-25T11:35:24+00:00 to 2026-09-25T11:36:27+00:00, PR opened 2026-09-25T11:36:27+00:00.
Passes: review 0.7. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 0.7 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $0.0000 | 0.0 | $0.0000 | 0.0 | $0.3843 | 0.6 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

30201 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 20 | $0.3843 | 0.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 37 | 30 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | plans/BACKLOG.md, plans/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-09-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
