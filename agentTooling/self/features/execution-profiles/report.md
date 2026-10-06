# execution-profiles — cost and waste report

Generated 2026-10-05T21:37:20.260506+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $40.5591 | 95.3% |
| verify | $0.0000 | 0.0% |
| review | $1.9980 | 4.7% |
| **total** | **$42.5571** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $40.5591, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $21.2786  
cost per file touched: $42.5571

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 277.6 | $40.5591 | $0.1461 |
| ↳ acceptance tests | 6.8 |  |  |
| ↳ implementation | 13.1 |  |  |
| ↳ gate | 0.2 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 2.8 | $1.9980 | $0.7095 |
| **total** | **280.4** | **$42.5571** | $0.1518 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **138.4 min** from 2026-10-05T19:18:52+00:00 to 2026-10-05T21:37:19+00:00, PR opened 2026-10-05T21:37:19+00:00.
Passes: review 2.9. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 2.9 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $40.5591 † | 277.6 † | $0.0000 | 0.0 | $1.8148 | 2.4 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.1832 | 0.4 | 02-review-sonnet | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and its `checkpoint` stamps span rounds 1, 2 — one figure cannot be divided between them, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

161014 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 34 | $1.8148 | 2.4 |  |
| sonnet | 1 | 7 | $0.1832 | 0.4 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 02-review-sonnet | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 144 | 96 |
| 02-review-sonnet | 53 | 23 |

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
