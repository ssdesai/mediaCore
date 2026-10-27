# capture-merges-committed-record — cost and waste report

Generated 2026-10-27T14:52:09.027304+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $18.1309 | 92.5% |
| verify | $0.0000 | 0.0% |
| review | $1.4696 | 7.5% |
| **total** | **$19.6005** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $18.1309, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $9.8003  
cost per file touched: $9.8003

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 36.3 | $18.1309 | $0.4999 |
| verify | 0.0 | $0.0000 |  |
| review | 2.5 | $1.4696 | $0.5838 |
| **total** | **38.8** | **$19.6005** | $0.5054 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **13.6 min** from 2026-10-27T14:38:34+00:00 to 2026-10-27T14:52:08+00:00, PR opened 2026-10-27T14:52:08+00:00.
Passes: review 2.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 2.6 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $18.1309 † | 36.3 † | $0.0000 | 0.0 | $1.2756 | 1.9 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.1940 | 0.6 | 02-review-sonnet | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

110112 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 36 | $1.2756 | 1.9 |  |
| sonnet | 1 | 9 | $0.1940 | 0.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 02-review-sonnet | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 96 | 85 |
| 02-review-sonnet | 63 | 39 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/analysis/capture_planning.py` | Read | 01-review-opus, 02-review-sonnet |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | analysis/README.md, self/review-report.md | — |
| 02-review-sonnet | self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
