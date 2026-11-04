# harness-same-repo — cost and waste report

Generated 2026-11-01T13:38:11.308692+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $6.5140 | 79.3% |
| verify | $0.0000 | 0.0% |
| review | $1.7034 | 20.7% |
| **total** | **$8.2174** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $6.5140, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.1087  
cost per file touched: $4.1087

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 64.7 | $6.5140 | $0.1007 |
| verify | 0.0 | $0.0000 |  |
| review | 3.1 | $1.7034 | $0.5445 |
| **total** | **67.8** | **$8.2174** | $0.1212 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **16.7 min** from 2026-11-01T13:21:28+00:00 to 2026-11-01T13:38:10+00:00, PR opened 2026-11-01T13:38:10+00:00.
Passes: review 3.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.2 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $6.5140 † | 64.7 † | $0.0000 | 0.0 | $1.1909 | 2.2 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.5125 | 1.0 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

112373 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 41 | $1.7034 | 3.1 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 02-review-opus | 2 | 1 | 2.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 73 | 104 |
| 02-review-opus | 37 | 73 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | harness/README.md, self/review-report.md | — |
| 02-review-opus | self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/review-report.md | 02-review-opus | 02-review-opus | 101 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
