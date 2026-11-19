# audit-round-cap — cost and waste report

Generated 2026-11-17T18:40:29.400103+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $0.7053 | 41.2% |
| verify | $0.0000 | 0.0% |
| review | $1.0060 | 58.8% |
| **total** | **$1.7113** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $0.7053, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $0.8556  
cost per file touched: $0.8556

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 77.4 | $0.7053 | $0.0091 |
| verify | 0.0 | $0.0000 |  |
| review | 1.6 | $1.0060 | $0.6116 |
| **total** | **79.0** | **$1.7113** | $0.0217 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **28.1 min** from 2026-11-17T18:12:23+00:00 to 2026-11-17T18:40:28+00:00, PR opened 2026-11-17T18:40:28+00:00.
Passes: review 1.7. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.7 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $0.7053 † | 77.4 † | $0.0000 | 0.0 | $0.5677 | 1.0 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.4383 | 0.7 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

77993 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 25 | $1.0060 | 1.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 02-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 27 | 48 |
| 02-review-opus | 23 | 46 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/LIFECYCLE.md` | Read | 01-review-opus, 02-review-opus |
| `/home/user/agentTooling/self/gate-report.txt` | Read | 01-review-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 02-review-opus | LIFECYCLE.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
