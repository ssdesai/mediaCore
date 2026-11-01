# cloud-wave-sessions — cost and waste report

Generated 2026-10-27T02:29:10.135348+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $6.7333 | 81.5% |
| verify | $0.0000 | 0.0% |
| review | $1.5247 | 18.5% |
| **total** | **$8.2579** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $6.7333, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.1290  
cost per file touched: $4.1290

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 38.7 | $6.7333 | $0.1741 |
| verify | 0.0 | $0.0000 |  |
| review | 10.1 | $1.5247 | $0.1505 |
| **total** | **48.8** | **$8.2579** | $0.1692 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **569.9 min** from 2026-10-26T16:59:11+00:00 to 2026-10-27T02:29:02+00:00, PR opened 2026-10-27T02:29:02+00:00.
Passes: review 10.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 10.2 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $6.7333 † | 38.7 † | $0.0000 | 0.0 | $0.8528 | 9.2 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.6719 | 0.9 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

114824 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 33 | $1.5247 | 10.1 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 02-review-opus | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 68 | 70 |
| 02-review-opus | 87 | 78 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md, templates/plans/features/TEMPLATE.md | — |
| 02-review-opus | self/review-report.md | — |

## Cross-plan edit overlap

none found.

## Warnings

- re-hunting computed without streams for: 01-review-opus
- edit overlap computed without streams for: 01-review-opus

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
