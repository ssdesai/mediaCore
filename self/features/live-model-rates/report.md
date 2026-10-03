# live-model-rates — cost and waste report

Generated 2026-10-02T04:42:25.595706+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $7.9550 | 86.4% |
| verify | $0.0000 | 0.0% |
| review | $1.2508 | 13.6% |
| **total** | **$9.2058** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $7.9550, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.6029  
cost per file touched: $9.2058

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 75.5 | $7.9550 | $0.1053 |
| ↳ acceptance tests | 1.9 |  |  |
| ↳ implementation | 12.6 |  |  |
| ↳ gate | 4.7 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 6.4 | $1.2508 | $0.1954 |
| **total** | **81.9** | **$9.2058** | $0.1124 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **34.7 min** from 2026-10-02T04:07:41+00:00 to 2026-10-02T04:42:23+00:00, PR opened 2026-10-02T04:42:23+00:00.
Passes: review 6.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 6.5 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $7.9550 | 75.5 | $0.0000 | 0.0 | $1.0992 | 1.7 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 | 0.0 | $0.0000 | 0.0 | $0.1516 | 4.7 | 02-review-sonnet | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

107814 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 27 | $1.0992 | 1.7 |  |
| sonnet | 1 | 5 | $0.1516 | 4.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 02-review-sonnet | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 50 | 45 |
| 02-review-sonnet | 29 | 35 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 02-review-sonnet | self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-02 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
