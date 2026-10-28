# router-brief-writes — cost and waste report

Generated 2026-10-02T23:07:11.600562+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $3.8254 | 84.8% |
| verify | $0.0000 | 0.0% |
| review | $0.6874 | 15.2% |
| **total** | **$4.5128** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $3.8254, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.5128  
cost per file touched: $1.1282

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 46.6 | $3.8254 | $0.0821 |
| ↳ gate | 4.8 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 1.2 | $0.6874 | $0.5860 |
| **total** | **47.7** | **$4.5128** | $0.0945 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **11.3 min** from 2026-10-02T22:55:49+00:00 to 2026-10-02T23:07:09+00:00, PR opened 2026-10-02T23:07:09+00:00.
Passes: review 1.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.2 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $3.8254 | 46.6 | $0.0000 | 0.0 | $0.6874 | 1.2 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

58675 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 16 | $0.6874 | 1.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 6 | 4 | 1.50 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 66 | 72 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | analysis/routing.py, self/review-report.md, self/tests/README.md, self/tests/routing-record.sh | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-02 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
