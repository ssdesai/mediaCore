# harness-review-effort — cost and waste report

Generated 2026-11-05T14:38:49.692247+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $2.2633 | 53.0% |
| verify | $0.0000 | 0.0% |
| review | $2.0097 | 47.0% |
| **total** | **$4.2730** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $2.2633, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.0683  
cost per file touched: $1.4243

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 68.0 | $2.2633 | $0.0333 |
| verify | 0.0 | $0.0000 |  |
| review | 3.0 | $2.0097 | $0.6698 |
| **total** | **71.0** | **$4.2730** | $0.0602 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **42.5 min** from 2026-11-05T13:56:21+00:00 to 2026-11-05T14:38:49+00:00, PR opened 2026-11-05T14:38:49+00:00.
Passes: review 3.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.1 min over 4 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $2.2633 † | 68.0 † | $0.0000 | 0.0 | $0.5785 | 1.2 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.5531 | 0.6 | 02-review-opus | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.4168 | 0.6 | 03-review-opus | clean | — |
| 4 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.4613 | 0.6 | 04-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

166917 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 4 | 56 | $2.0097 | 3.0 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 7 | 3 | 2.33 |
| 02-review-opus | 1 | 1 | 1.00 |
| 03-review-opus | 1 | 1 | 1.00 |
| 04-review-opus | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 48 | 58 |
| 02-review-opus | 31 | 46 |
| 03-review-opus | 27 | 52 |
| 04-review-opus | 32 | 50 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/harness/README.md` | Read | 01-review-opus, 03-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | harness/README.md, harness/tests/README.md, self/review-report.md | — |
| 02-review-opus | self/review-report.md | — |
| 03-review-opus | self/review-report.md | — |
| 04-review-opus | self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
