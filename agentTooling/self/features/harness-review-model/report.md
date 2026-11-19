# harness-review-model — cost and waste report

Generated 2026-11-05T04:36:53.552731+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $1.7228 | 60.1% |
| verify | $0.0000 | 0.0% |
| review | $1.1444 | 39.9% |
| **total** | **$2.8672** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $1.7228, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $2.8672  
cost per file touched: $0.5734

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 35.5 | $1.7228 | $0.0485 |
| verify | 0.0 | $0.0000 |  |
| review | 0.5 | $1.1444 | $2.1044 |
| **total** | **36.0** | **$2.8672** | $0.0795 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **4.8 min** from 2026-11-05T04:32:04+00:00 to 2026-11-05T04:36:52+00:00, PR opened 2026-11-05T04:36:52+00:00.
Passes: review 4.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 4.5 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $1.7228 | 35.5 | $0.0000 | 0.0 | $1.1444 | 0.5 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

3502 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 4 | $1.1444 | 0.5 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 7 | 5 | 1.40 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 64 | 104 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | harness/README.md, harness/tests/README.md, harness/tests/review-model.sh, harness/tests/smoke.sh, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
