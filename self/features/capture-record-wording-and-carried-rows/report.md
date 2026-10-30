# capture-record-wording-and-carried-rows — cost and waste report

Generated 2026-10-27T21:36:20.479121+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $1.2847 | 63.9% |
| verify | $0.0000 | 0.0% |
| review | $0.7251 | 36.1% |
| **total** | **$2.0098** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $1.2847, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $2.0098  
cost per file touched: $2.0098

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 15.1 | $1.2847 | $0.0853 |
| verify | 0.0 | $0.0000 |  |
| review | 0.9 | $0.7251 | $0.7809 |
| **total** | **16.0** | **$2.0098** | $0.1256 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **1.2 min** from 2026-10-27T21:35:08+00:00 to 2026-10-27T21:36:19+00:00, PR opened 2026-10-27T21:36:19+00:00.
Passes: review 1.0. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.0 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $1.2847 | 15.1 | $0.0000 | 0.0 | $0.7251 | 0.9 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

64982 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 12 | $0.7251 | 0.9 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 62 | 79 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
