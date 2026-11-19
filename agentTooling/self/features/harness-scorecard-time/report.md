# harness-scorecard-time — cost and waste report

Generated 2026-11-05T13:56:25.289595+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $1.1678 | 57.3% |
| verify | $0.0000 | 0.0% |
| review | $0.8702 | 42.7% |
| **total** | **$2.0380** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $1.1678, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.0190  
cost per file touched: $0.6793

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 35.2 | $1.1678 | $0.0332 |
| verify | 0.0 | $0.0000 |  |
| review | 1.4 | $0.8702 | $0.6270 |
| **total** | **36.6** | **$2.0380** | $0.0557 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **3.5 min** from 2026-11-05T13:52:57+00:00 to 2026-11-05T13:56:24+00:00, PR opened 2026-11-05T13:56:24+00:00.
Passes: review 1.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.5 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $1.1678 † | 35.2 † | $0.0000 | 0.0 | $0.4834 | 0.7 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.3868 | 0.7 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

70336 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 23 | $0.8702 | 1.4 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 02-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 47 | 77 |
| 02-review-opus | 34 | 48 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | harness/tests/README.md, self/review-report.md | — |
| 02-review-opus | self/features/harness-scorecard-time/README.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
