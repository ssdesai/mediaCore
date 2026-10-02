# pull-agenttooling-pr75 — cost and waste report

Generated 2026-10-02T21:17:01.321130+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $0.3247 | 43.4% |
| verify | $0.0000 | 0.0% |
| review | $0.4238 | 56.6% |
| **total** | **$0.7485** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $0.3247, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $0.7485  
cost per file touched: $0.7485

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 1.7 | $0.3247 | $0.1948 |
| verify | 0.0 | $0.0000 |  |
| review | 0.7 | $0.4238 | $0.5953 |
| **total** | **2.4** | **$0.7485** | $0.3147 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **1.1 min** from 2026-10-02T21:15:54+00:00 to 2026-10-02T21:17:00+00:00, PR opened 2026-10-02T21:17:00+00:00.
Passes: review 0.8. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 0.8 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $0.3247 | 1.7 | $0.0000 | 0.0 | $0.4238 | 0.7 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

34174 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 16 | $0.4238 | 0.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 38 | 48 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | plans/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-02 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
