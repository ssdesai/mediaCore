# subtree-pull-keeps-base — cost and waste report

Generated 2026-10-27T22:06:51.801524+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $6.3061 | 74.2% |
| verify | $0.0000 | 0.0% |
| review | $2.1967 | 25.8% |
| **total** | **$8.5028** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $6.3061, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.2514  
cost per file touched: $1.7006

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 45.7 | $6.3061 | $0.1379 |
| verify | 0.0 | $0.0000 |  |
| review | 5.2 | $2.1967 | $0.4258 |
| **total** | **50.9** | **$8.5028** | $0.1671 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **19.2 min** from 2026-10-27T21:47:38+00:00 to 2026-10-27T22:06:50+00:00, PR opened 2026-10-27T22:06:50+00:00.
Passes: review 5.3. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 5.3 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $6.3061 † | 45.7 † | $0.0000 | 0.0 | $1.1124 | 3.4 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.0843 | 1.8 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

150476 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 45 | $2.1967 | 5.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 5 | 4 | 1.25 |
| 02-review-opus | 3 | 2 | 1.50 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 96 | 98 |
| 02-review-opus | 59 | 120 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/self/features/subtree-pull-keeps-base/NOTES.md` | Read | 01-review-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | LIFECYCLE.md, ORCHESTRATION.md, README.md, self/review-report.md | — |
| 02-review-opus | self/features/subtree-pull-keeps-base/NOTES.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
