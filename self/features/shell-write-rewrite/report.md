# shell-write-rewrite — cost and waste report

Generated 2026-09-22T16:49:31.164616+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $18.5406 | 85.8% |
| verify | $0.0000 | 0.0% |
| review | $3.0710 | 14.2% |
| **total** | **$21.6116** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $18.5406, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $21.6116  
cost per file touched: $7.2039

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 121.0 | $18.5406 | $0.1533 |
| ↳ acceptance tests | 3.2 |  |  |
| ↳ implementation | 109.5 |  |  |
| ↳ gate | 3.8 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 3.6 | $3.0710 | $0.8609 |
| **total** | **124.5** | **$21.6116** | $0.1736 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **1177.8 min** from 2026-09-21T21:11:41+00:00 to 2026-09-22T16:49:29+00:00, PR opened 2026-09-22T16:49:29+00:00.
Passes: review 3.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.6 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $18.5406 | 121.0 | $0.0000 | 0.0 | $3.0710 | 3.6 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

113778 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 36 | $3.0710 | 3.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 5 | 3 | 1.67 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 88 | 110 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md, self/tests/README.md, self/tests/allow-repo-commands.sh | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/tests/allow-repo-commands.sh | 01-review-opus | 01-review-opus | 378 |

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
