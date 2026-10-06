# cost-capture-collisions — cost and waste report

Generated 2026-10-05T18:30:27.691903+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $24.7249 | 91.3% |
| verify | $0.0000 | 0.0% |
| review | $2.3530 | 8.7% |
| **total** | **$27.0778** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $24.7249, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $9.0259  
cost per file touched: $27.0778

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 106.0 | $24.7249 | $0.2333 |
| ↳ acceptance tests | 5.7 |  |  |
| ↳ implementation | 10.1 |  |  |
| ↳ gate | 1.3 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 6.0 | $2.3530 | $0.3891 |
| **total** | **112.0** | **$27.0778** | $0.2417 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **42.4 min** from 2026-10-05T17:48:06+00:00 to 2026-10-05T18:30:27+00:00, PR opened 2026-10-05T18:30:27+00:00.
Passes: review 6.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 6.2 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $24.7249 † | 106.0 † | $0.0000 | 0.0 | $1.6211 | 2.6 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.5082 | 3.0 | 02-review-sonnet | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.2236 | 0.5 | 03-review-sonnet | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and its `checkpoint` stamps span rounds 1, 2 — one figure cannot be divided between them, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

185593 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 33 | $1.6211 | 2.6 |  |
| sonnet | 2 | 46 | $0.7319 | 3.5 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 02-review-sonnet | 2 | 1 | 2.00 |
| 03-review-sonnet | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 121 | 114 |
| 02-review-sonnet | 55 | 52 |
| 03-review-sonnet | 36 | 46 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agenttooling/analysis/capture_planning.py` | Read | 01-review-opus, 02-review-sonnet |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 02-review-sonnet | self/review-report.md | — |
| 03-review-sonnet | self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/review-report.md | 02-review-sonnet | 02-review-sonnet | 45 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-02 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
