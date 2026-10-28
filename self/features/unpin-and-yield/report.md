# unpin-and-yield — cost and waste report

Generated 2026-10-03T00:13:02.500561+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $6.9117 | 89.6% |
| verify | $0.0000 | 0.0% |
| review | $0.7981 | 10.4% |
| **total** | **$7.7098** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $6.9117, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $7.7098  
cost per file touched: $7.7098

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 53.4 | $6.9117 | $0.1296 |
| ↳ acceptance tests | 2.9 |  |  |
| ↳ implementation | 14.1 |  |  |
| ↳ gate | 0.1 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 1.9 | $0.7981 | $0.4192 |
| **total** | **55.3** | **$7.7098** | $0.1395 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **19.9 min** from 2026-10-02T23:53:03+00:00 to 2026-10-03T00:13:00+00:00, PR opened 2026-10-03T00:13:00+00:00.
Passes: review 1.9. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.9 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $6.9117 | 53.4 | $0.0000 | 0.0 | $0.7981 | 1.9 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

61060 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 17 | $0.7981 | 1.9 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 68 | 74 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-02 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
