# generated-readme-repo-owned — cost and waste report

Generated 2026-10-26T17:09:06.565920+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $3.9246 | 80.8% |
| verify | $0.0000 | 0.0% |
| review | $0.9323 | 19.2% |
| **total** | **$4.8568** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $3.9246, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.8568  
cost per file touched: $4.8568

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 28.1 | $3.9246 | $0.1395 |
| verify | 0.0 | $0.0000 |  |
| review | 2.6 | $0.9323 | $0.3621 |
| **total** | **30.7** | **$4.8568** | $0.1582 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **3.1 min** from 2026-10-26T17:06:01+00:00 to 2026-10-26T17:09:05+00:00, PR opened 2026-10-26T17:09:05+00:00.
Passes: review 2.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 2.6 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $3.9246 | 28.1 | $0.0000 | 0.0 | $0.9323 | 2.6 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

65754 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 17 | $0.9323 | 2.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 82 | 85 |

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
