# new-branch-per-feature — cost and waste report

Generated 2026-11-17T20:09:45.780343+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $0.5985 | 61.0% |
| verify | $0.0000 | 0.0% |
| review | $0.3821 | 39.0% |
| **total** | **$0.9806** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $0.5985, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $0.9806  
cost per file touched: $0.9806

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 54.0 | $0.5985 | $0.0111 |
| verify | 0.0 | $0.0000 |  |
| review | 0.7 | $0.3821 | $0.5633 |
| **total** | **54.7** | **$0.9806** | $0.0179 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **0.9 min** from 2026-11-17T20:08:52+00:00 to 2026-11-17T20:09:45+00:00, PR opened 2026-11-17T20:09:45+00:00.
Passes: review 0.7. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 0.7 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $0.5985 | 54.0 | $0.0000 | 0.0 | $0.3821 | 0.7 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

27449 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 14 | $0.3821 | 0.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 46 | 56 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
