# backlog-unclaimed-delegates — cost and waste report

Generated 2026-09-23T17:10:02.996812+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $0.0000 | 0.0% |
| verify | $0.0000 | 0.0% |
| review | $0.8560 | 100.0% |
| **total** | **$0.8560** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $0.0000, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $0.4280  
cost per file touched: $0.4280

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 0.0 | $0.0000 |  |
| verify | 0.0 | $0.0000 |  |
| review | 11.9 | $0.8560 | $0.0721 |
| **total** | **11.9** | **$0.8560** | $0.0721 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **15.0 min** from 2026-09-23T16:55:03+00:00 to 2026-09-23T17:10:01+00:00, PR opened 2026-09-23T17:10:01+00:00.
Passes: review 12.0. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 12.0 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.4667 | 2.8 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.3894 | 9.1 | 02-review-sonnet | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

78598 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 17 | $0.4667 | 2.8 |  |
| sonnet | 1 | 25 | $0.3894 | 9.1 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 02-review-sonnet | 3 | 2 | 1.50 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 39 | 51 |
| 02-review-sonnet | 33 | 61 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/Users/sahildesai/dev/agentTooling/.worktrees/backlog-unclaimed-delegates/self/BACKLOG.md` | Read | 01-review-opus, 02-review-sonnet |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/BACKLOG.md, self/review-report.md | — |
| 02-review-sonnet | self/BACKLOG.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-09-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
