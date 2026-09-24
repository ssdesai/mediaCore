# release-original-year — cost and waste report

Generated 2026-09-24T16:47:46.794313+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $2.3012 | 80.9% |
| verify | $0.0000 | 0.0% |
| review | $0.5435 | 19.1% |
| **total** | **$2.8447** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $2.3012, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $2.8447  
cost per file touched: $1.4223

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 6.8 | $2.3012 | $0.3384 |
| ↳ acceptance tests | 1.7 |  |  |
| ↳ implementation | 3.0 |  |  |
| ↳ gate | 0.7 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 0.7 | $0.5435 | $0.7723 |
| **total** | **7.5** | **$2.8447** | $0.3791 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **11.1 min** from 2026-09-24T16:36:42+00:00 to 2026-09-24T16:47:45+00:00, PR opened 2026-09-24T16:47:45+00:00.
Passes: review 0.8. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 0.8 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $2.3012 | 6.8 | $0.0000 | 0.0 | $0.5435 | 0.7 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

47290 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 12 | $0.5435 | 0.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 55 | 54 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | plans/review-report.md, tests/test_release.py | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-09-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
