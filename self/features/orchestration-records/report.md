# orchestration-records — cost and waste report

Generated 2026-10-30T19:01:05.527313+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $3.6435 | 69.3% |
| verify | $0.0000 | 0.0% |
| review | $1.6153 | 30.7% |
| **total** | **$5.2587** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $3.6435, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $2.6294  
cost per file touched: $1.7529

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 33.5 | $3.6435 | $0.1089 |
| verify | 0.0 | $0.0000 |  |
| review | 2.4 | $1.6153 | $0.6678 |
| **total** | **35.9** | **$5.2587** | $0.1465 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **5.7 min** from 2026-10-30T18:55:25+00:00 to 2026-10-30T19:01:04+00:00, PR opened 2026-10-30T19:01:04+00:00.
Passes: review 2.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 2.5 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $3.6435 † | 33.5 † | $0.0000 | 0.0 | $1.1486 | 1.7 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.4666 | 0.8 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

119169 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 43 | $1.6153 | 2.4 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 02-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 59 | 108 |
| 02-review-opus | 20 | 63 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/self/features/orchestration-records/NOTES.md` | Read | 01-review-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | analysis/report.py, self/review-report.md | — |
| 02-review-opus | self/features/orchestration-records/NOTES.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
