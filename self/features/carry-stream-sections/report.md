# carry-stream-sections — cost and waste report

Generated 2026-09-23T16:20:44.819874+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $0.0000 | 0.0% |
| verify | $0.0000 | 0.0% |
| review | $0.3765 | 100.0% |
| **total** | **$0.3765** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $0.0000, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $0.3765  
cost per file touched: $0.1883

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 0.0 | $0.0000 |  |
| verify | 0.0 | $0.0000 |  |
| review | 0.5 | $0.3765 | $0.7186 |
| **total** | **0.5** | **$0.3765** | $0.7186 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **0.9 min** from 2026-09-23T16:19:49+00:00 to 2026-09-23T16:20:43+00:00, PR opened 2026-09-23T16:20:43+00:00.
Passes: review 0.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 0.6 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $0.0000 | 0.0 | $0.0000 | 0.0 | $0.3765 | 0.5 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

33902 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 9 | $0.3765 | 0.5 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 66 | 50 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | analysis/README.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates last verified 2026-09-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
