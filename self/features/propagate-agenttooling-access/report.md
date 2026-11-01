# propagate-agenttooling-access — cost and waste report

Generated 2026-10-27T02:15:42.075430+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $8.6072 | 82.9% |
| verify | $0.0000 | 0.0% |
| review | $1.7807 | 17.1% |
| **total** | **$10.3878** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $8.6072, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $3.4626  
cost per file touched: $1.7313

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 45.9 | $8.6072 | $0.1877 |
| verify | 0.0 | $0.0000 |  |
| review | 3.1 | $1.7807 | $0.5794 |
| **total** | **48.9** | **$10.3878** | $0.2123 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **553.6 min** from 2026-10-26T16:59:05+00:00 to 2026-10-27T02:12:44+00:00, PR opened 2026-10-27T02:12:44+00:00.
Passes: review 3.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.2 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $8.6072 † | 45.9 † | $0.0000 | 0.0 | $0.7604 | 1.3 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.4679 | 0.9 | 02-review-opus | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.5524 | 0.8 | 03-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

139699 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 43 | $1.7807 | 3.1 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 3 | 1.00 |
| 02-review-opus | 2 | 2 | 1.00 |
| 03-review-opus | 3 | 3 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 59 | 79 |
| 02-review-opus | 43 | 48 |
| 03-review-opus | 68 | 82 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | README.md, env-profile.sh, self/review-report.md | — |
| 02-review-opus | /tmp/plan-capture.futLbw/scratch/fnenv.sh, self/review-report.md | — |
| 03-review-opus | /tmp/plan-capture.icBAQV/scratch/chk.sh, /tmp/plan-capture.icBAQV/scratch/chk2.sh, self/review-report.md | — |

## Cross-plan edit overlap

none found.

## Warnings

- re-hunting computed without streams for: 01-review-opus, 02-review-opus
- edit overlap computed without streams for: 01-review-opus, 02-review-opus

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
