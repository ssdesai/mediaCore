# integration-hnm-wording — cost and waste report

Generated 2026-10-01T18:08:40.790253+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $1.7525 | 76.9% |
| verify | $0.0000 | 0.0% |
| review | $0.5258 | 23.1% |
| **total** | **$2.2783** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $1.7525, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $2.2783  
cost per file touched: $0.7594

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 5.2 | $1.7525 | $0.3349 |
| verify | 0.0 | $0.0000 |  |
| review | 0.8 | $0.5258 | $0.6350 |
| **total** | **6.1** | **$2.2783** | $0.3759 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **1.1 min** from 2026-10-01T18:07:32+00:00 to 2026-10-01T18:08:39+00:00, PR opened 2026-10-01T18:08:39+00:00.
Passes: review 0.9. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 0.9 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $1.7525 | 5.2 | $0.0000 | 0.0 | $0.5258 | 0.8 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

42774 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 18 | $0.5258 | 0.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 4 | 3 | 1.33 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 51 | 60 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | /var/folders/w1/sjvnhgn11ml_fj_s_kch9xv40000gn/T/plan-capture.dziwT9/scratch/dec.py, INTEGRATION.md, plans/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-09-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
