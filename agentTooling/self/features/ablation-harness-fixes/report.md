# ablation-harness-fixes — cost and waste report

Generated 2026-11-07T18:57:17.362402+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $10.1496 | 90.1% |
| verify | $0.0000 | 0.0% |
| review | $1.1209 | 9.9% |
| **total** | **$11.2705** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $10.1496, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $11.2705  
cost per file touched: $2.8176

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 33.2 | $10.1496 | $0.3053 |
| verify | 0.0 | $0.0000 |  |
| review | 1.7 | $1.1209 | $0.6475 |
| **total** | **35.0** | **$11.2705** | $0.3222 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **2.1 min** from 2026-11-07T16:39:00+00:00 to 2026-11-07T16:41:08+00:00, PR opened 2026-11-07T16:41:08+00:00.
Passes: review 1.8. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.8 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $10.1496 | 33.2 | $0.0000 | 0.0 | $1.1209 | 1.7 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

78951 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 24 | $1.1209 | 1.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 5 | 4 | 1.25 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 71 | 101 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | harness/run.sh, hooks/allow-repo-commands.sh, self/review-report.md, self/tests/hook-cloud-profile.sh | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/tests/hook-cloud-profile.sh | 01-review-opus | 01-review-opus | 184 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
