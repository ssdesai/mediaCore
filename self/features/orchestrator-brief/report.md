# orchestrator-brief — cost and waste report

Generated 2026-10-30T22:22:48.198764+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $1.8054 | 57.2% |
| verify | $0.0000 | 0.0% |
| review | $1.3495 | 42.8% |
| **total** | **$3.1549** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $1.8054, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.5774  
cost per file touched: $0.4507

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 29.7 | $1.8054 | $0.0608 |
| verify | 0.0 | $0.0000 |  |
| review | 2.7 | $1.3495 | $0.4924 |
| **total** | **32.4** | **$3.1549** | $0.0973 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **12.0 min** from 2026-10-30T22:10:48+00:00 to 2026-10-30T22:22:47+00:00, PR opened 2026-10-30T22:22:47+00:00.
Passes: review 2.8. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 2.8 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $1.8054 † | 29.7 † | $0.0000 | 0.0 | $0.8587 | 1.8 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.4908 | 0.9 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

97805 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 38 | $1.3495 | 2.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 5 | 4 | 1.25 |
| 02-review-opus | 4 | 4 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 50 | 100 |
| 02-review-opus | 37 | 58 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | README.md, self/review-report.md, templates/README.md, templates/plans/ORCHESTRATOR_BRIEF.md | — |
| 02-review-opus | /tmp/plan-capture.z5HMXh/scratch/mut.sh, self/review-report.md, self/tests/README.md, self/tests/orchestrator-brief.sh | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
