# sandbox-consumer-reads — cost and waste report

Generated 2026-10-02T04:19:28.395053+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $3.1948 | 79.0% |
| verify | $0.0000 | 0.0% |
| review | $0.8478 | 21.0% |
| **total** | **$4.0426** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $3.1948, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.0426  
cost per file touched: $1.3475

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 20.6 | $3.1948 | $0.1548 |
| verify | 0.0 | $0.0000 |  |
| review | 1.1 | $0.8478 | $0.7647 |
| **total** | **21.7** | **$4.0426** | $0.1859 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **1.5 min** from 2026-09-30T20:12:52+00:00 to 2026-09-30T20:14:22+00:00, PR opened 2026-09-30T20:14:22+00:00.
Passes: review 1.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.2 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $3.1948 | 20.6 | $0.0000 | 0.0 | $0.8478 | 1.1 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

70520 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 23 | $0.8478 | 1.1 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 3 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 66 | 78 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md, self/tests/hook-wiring.sh, sync-plans.sh | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-02 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
