# ledger-and-routing — cost and waste report

Generated 2026-09-18T13:28:00.847670+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $45.2219 | 91.8% |
| verify | $0.0000 | 0.0% |
| review | $4.0438 | 8.2% |
| **total** | **$49.2657** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $45.2219, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $24.6329  
cost per file touched: $12.3164

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 84.7 | $45.2219 | $0.5339 |
| verify | 0.0 | $0.0000 |  |
| review | 6.1 | $4.0438 | $0.6631 |
| **total** | **90.8** | **$49.2657** | $0.5426 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **42.1 min** from 2026-09-18T12:45:54+00:00 to 2026-09-18T13:27:59+00:00, PR opened 2026-09-18T13:27:59+00:00.
Passes: review 6.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 6.2 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $45.2219 | 84.7 | $0.0000 | 0.0 | $3.4782 | 3.5 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 | 0.0 | $0.0000 | 0.0 | $0.5656 | 2.6 | 02-review-sonnet | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

190176 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 41 | $3.4782 | 3.5 |  |
| sonnet | 1 | 24 | $0.5656 | 2.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 6 | 4 | 1.50 |
| 02-review-sonnet | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 136 | 119 |
| 02-review-sonnet | 51 | 71 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | README.md, analysis/report.py, self/PROJECT_FACTS.md, self/review-report.md | — |
| 02-review-sonnet | self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/review-report.md | 01-review-opus | 01-review-opus | 87 |

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
