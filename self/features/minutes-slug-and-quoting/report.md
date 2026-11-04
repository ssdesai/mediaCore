# minutes-slug-and-quoting — cost and waste report

Generated 2026-09-18T14:51:32.787854+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $34.5082 | 95.1% |
| verify | $0.0000 | 0.0% |
| review | $1.7673 | 4.9% |
| **total** | **$36.2755** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $34.5082, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $36.2755  
cost per file touched: $6.0459

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 68.4 | $34.5082 | $0.5045 |
| ↳ acceptance tests | 8.2 |  |  |
| ↳ implementation | 42.4 |  |  |
| ↳ gate | 6.5 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 5.0 | $1.7673 | $0.3568 |
| **total** | **73.4** | **$36.2755** | $0.4945 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **75.8 min** from 2026-09-18T13:35:40+00:00 to 2026-09-18T14:51:31+00:00, PR opened 2026-09-18T14:51:31+00:00.
Passes: review 5.0. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 5.0 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $34.5082 | 68.4 | $0.0000 | 0.0 | $1.7673 | 5.0 | 01-review-sonnet | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

160911 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| sonnet | 1 | 55 | $1.7673 | 5.0 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-sonnet | 10 | 6 | 1.67 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-sonnet | 86 | 176 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-sonnet | analysis/README.md, analysis/report.py, self/review-report.md, self/tests/README.md, self/tests/feature-lifecycle.sh, self/tests/report-footnotes.sh | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| analysis/report.py | 01-review-sonnet | 01-review-sonnet | 233 |

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
