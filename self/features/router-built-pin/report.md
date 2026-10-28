# router-built-pin — cost and waste report

Generated 2026-09-23T17:25:09.289939+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $10.8178 | 89.1% |
| verify | $0.0000 | 0.0% |
| review | $1.3299 | 10.9% |
| **total** | **$12.1477** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $10.8178, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $6.0738  
cost per file touched: $12.1477

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 84.8 | $10.8178 | $0.1276 |
| verify | 0.0 | $0.0000 |  |
| review | 6.8 | $1.3299 | $0.1943 |
| **total** | **91.6** | **$12.1477** | $0.1326 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **36.5 min** from 2026-09-23T16:48:35+00:00 to 2026-09-23T17:25:07+00:00, PR opened 2026-09-23T17:25:07+00:00.
Passes: review 6.9. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 6.9 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $10.8178 † | 84.8 † | $0.0000 | 0.0 | $0.6780 | 1.3 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.6518 | 5.6 | 02-review-sonnet | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

122963 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 20 | $0.6780 | 1.3 |  |
| sonnet | 1 | 44 | $0.6518 | 5.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 02-review-sonnet | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 69 | 68 |
| 02-review-sonnet | 55 | 42 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 02-review-sonnet | self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-09-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
