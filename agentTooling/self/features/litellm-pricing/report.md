# litellm-pricing — cost and waste report

Generated 2026-09-23T16:45:31.639869+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $8.2846 | 76.3% |
| verify | $0.0000 | 0.0% |
| review | $2.5678 | 23.7% |
| **total** | **$10.8523** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $8.2846, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $5.4262  
cost per file touched: $1.3565

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 85.2 | $8.2846 | $0.0973 |
| ↳ acceptance tests | 5.0 |  |  |
| ↳ implementation | 4.9 |  |  |
| ↳ gate | 11.0 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 11.0 | $2.5678 | $0.2340 |
| **total** | **96.1** | **$10.8523** | $0.1129 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **38.2 min** from 2026-09-23T16:03:04+00:00 to 2026-09-23T16:41:15+00:00, PR opened 2026-09-23T16:41:15+00:00.
Passes: review 11.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 11.1 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $8.2846 | 85.2 | $0.0000 | 0.0 | $1.3881 | 5.6 | 01-review-opus | clean | — |
| 2 | $0.0000 | 0.0 | $0.0000 | 0.0 | $1.1797 | 5.3 | 02-review-sonnet | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

193278 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 31 | $1.3881 | 5.6 |  |
| sonnet | 1 | 60 | $1.1797 | 5.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 6 | 5 | 1.20 |
| 02-review-sonnet | 5 | 4 | 1.25 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 63 | 139 |
| 02-review-sonnet | 42 | 98 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | /var/folders/w1/sjvnhgn11ml_fj_s_kch9xv40000gn/T/plan-capture.afsoAY/scratch/parity.py, analysis/refresh_rates.py, analysis/transcript.py, self/review-report.md, self/tests/timestamps-are-utc.sh | — |
| 02-review-sonnet | /var/folders/w1/sjvnhgn11ml_fj_s_kch9xv40000gn/T/plan-capture.mUNm22/scratch/wait-gate.sh, self/review-report.md, self/tests/README.md, self/tests/report-footnotes.sh | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-09-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
