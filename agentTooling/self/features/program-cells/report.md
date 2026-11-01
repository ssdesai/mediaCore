# program-cells — cost and waste report

Generated 2026-10-31T00:03:40.373000+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $11.1954 | 75.8% |
| verify | $0.0000 | 0.0% |
| review | $3.5829 | 24.2% |
| **total** | **$14.7783** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $11.1954, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $7.3891  
cost per file touched: $3.6946

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 103.3 | $11.1954 | $0.1084 |
| verify | 0.0 | $0.0000 |  |
| review | 6.7 | $3.5829 | $0.5348 |
| **total** | **110.0** | **$14.7783** | $0.1343 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **26.7 min** from 2026-10-30T23:36:57+00:00 to 2026-10-31T00:03:39+00:00, PR opened 2026-10-31T00:03:39+00:00.
Passes: review 6.8. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 6.8 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $11.1954 † | 103.3 † | $0.0000 | 0.0 | $2.5485 | 4.5 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.0344 | 2.2 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

213500 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 74 | $3.5829 | 6.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 4 | 3 | 1.33 |
| 02-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 70 | 109 |
| 02-review-opus | 46 | 103 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/harness/README.md` | Read | 01-review-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | harness/new-experiment.sh, harness/program-stages.sh, self/review-report.md | — |
| 02-review-opus | harness/README.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
