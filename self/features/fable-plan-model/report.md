# fable-plan-model — cost and waste report

Generated 2026-10-28T22:55:08.652129+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $4.0123 | 63.3% |
| verify | $0.0000 | 0.0% |
| review | $2.3295 | 36.7% |
| **total** | **$6.3419** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $4.0123, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $6.3419  
cost per file touched: $2.1140

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 32.6 | $4.0123 | $0.1229 |
| verify | 0.0 | $0.0000 |  |
| review | 2.3 | $2.3295 | $1.0071 |
| **total** | **35.0** | **$6.3419** | $0.1814 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **11.9 min** from 2026-10-28T22:43:11+00:00 to 2026-10-28T22:55:08+00:00, PR opened 2026-10-28T22:55:08+00:00.
Passes: review 2.4. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 2.4 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $4.0123 | 32.6 | $0.0000 | 0.0 | $2.3295 | 2.3 | 01-review-fable | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

75871 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| fable | 1 | 36 | $2.3295 | 2.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-fable | 5 | 3 | 1.67 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-fable | 52 | 67 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-fable | AGENT_PLANS.md, RUNNER.md, self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| RUNNER.md | 01-review-fable | 01-review-fable | 234 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
