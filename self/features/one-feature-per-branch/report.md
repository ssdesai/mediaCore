# one-feature-per-branch — cost and waste report

Generated 2026-10-30T20:06:44.850573+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $2.2537 | 50.0% |
| verify | $0.0000 | 0.0% |
| review | $2.2534 | 50.0% |
| **total** | **$4.5072** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $2.2537, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.5024  
cost per file touched: $1.1268

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 99.0 | $2.2537 | $0.0228 |
| verify | 0.0 | $0.0000 |  |
| review | 4.2 | $2.2534 | $0.5365 |
| **total** | **103.2** | **$4.5072** | $0.0437 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **25.1 min** from 2026-10-30T19:41:36+00:00 to 2026-10-30T20:06:44+00:00, PR opened 2026-10-30T20:06:44+00:00.
Passes: review 4.3. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 4.3 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $2.2537 † | 99.0 † | $0.0000 | 0.0 | $1.1241 | 2.2 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.5414 | 1.1 | 02-review-opus | escalated | escalations/02-review-opus.md |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.5879 | 0.9 | 03-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

164668 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 58 | $2.2534 | 4.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 2 | 1.50 |
| 02-review-opus | 3 | 3 | 1.00 |
| 03-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 53 | 99 |
| 02-review-opus | 32 | 68 |
| 03-review-opus | 30 | 45 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/analysis/capture_planning.py` | Read | 01-review-opus, 02-review-opus, 03-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | analysis/capture_planning.py, self/review-report.md | — |
| 02-review-opus | analysis/README.md, analysis/capture_planning.py, self/review-report.md | — |
| 03-review-opus | self/review-report.md, self/tests/capture-guard.sh | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
