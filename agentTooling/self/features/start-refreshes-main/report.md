# start-refreshes-main — cost and waste report

Generated 2026-09-21T17:39:38.667843+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $3.8211 | 74.6% |
| verify | $0.0000 | 0.0% |
| review | $1.3005 | 25.4% |
| **total** | **$5.1216** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $3.8211, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $5.1216  
cost per file touched: $1.2804

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 35.7 | $3.8211 | $0.1071 |
| verify | 0.0 | $0.0000 |  |
| review | 3.1 | $1.3005 | $0.4211 |
| **total** | **38.8** | **$5.1216** | $0.1321 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **3.6 min** from 2026-09-21T17:36:01+00:00 to 2026-09-21T17:39:36+00:00, PR opened 2026-09-21T17:39:36+00:00.
Passes: review 3.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.1 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $3.8211 | 35.7 | $0.0000 | 0.0 | $1.3005 | 3.1 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

65383 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 18 | $1.3005 | 3.1 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 5 | 4 | 1.25 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 52 | 62 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | hooks/README.md, self/review-report.md, self/tests/README.md, self/tests/feature-lifecycle.sh | — |

## Cross-plan edit overlap

none found.

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
