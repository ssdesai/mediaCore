# hook-pipe-redirect — cost and waste report

Generated 2026-09-27T06:08:34.230086+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $4.2633 | 81.0% |
| verify | $0.0000 | 0.0% |
| review | $1.0028 | 19.0% |
| **total** | **$5.2661** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $4.2633, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $5.2661  
cost per file touched: $2.6331

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 23.7 | $4.2633 | $0.1801 |
| ↳ acceptance tests | 2.5 |  |  |
| ↳ implementation | 6.2 |  |  |
| ↳ gate | 4.7 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 1.3 | $1.0028 | $0.7930 |
| **total** | **24.9** | **$5.2661** | $0.2112 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **15.9 min** from 2026-09-27T01:02:23+00:00 to 2026-09-27T01:18:16+00:00, PR opened 2026-09-27T01:18:16+00:00.
Passes: review 1.3. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.3 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $4.2633 | 23.7 | $0.0000 | 0.0 | $1.0028 | 1.3 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

87773 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 18 | $1.0028 | 1.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 44 | 74 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | README.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-09-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
