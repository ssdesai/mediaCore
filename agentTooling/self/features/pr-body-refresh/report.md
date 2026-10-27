# pr-body-refresh — cost and waste report

Generated 2026-10-27T15:39:17.057516+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $16.6979 | 85.0% |
| verify | $0.0000 | 0.0% |
| review | $2.9563 | 15.0% |
| **total** | **$19.6542** | 100.0% |

1 planning row carried from the capture of 2026-10-27: the capture could not reach its transcript (an earlier round's container, or expired), so the planning figure chains that capture's dollars with this one's.

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $16.6979, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $6.5514  
cost per file touched: $3.2757

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 51.2 | $16.6979 | $0.3262 |
| verify | 0.0 | $0.0000 |  |
| review | 5.1 | $2.9563 | $0.5803 |
| **total** | **56.3** | **$19.6542** | $0.3492 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **41.6 min** from 2026-10-27T14:57:40+00:00 to 2026-10-27T15:39:16+00:00, PR opened 2026-10-27T15:39:16+00:00.
Passes: review 5.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 5.2 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $16.6979 † | 51.2 † | $0.0000 | 0.0 | $0.9554 | 2.0 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.1471 | 1.7 | 02-review-opus | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.8538 | 1.4 | 03-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

217968 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 78 | $2.9563 | 5.1 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 3 | 1.00 |
| 02-review-opus | 4 | 4 | 1.00 |
| 03-review-opus | 5 | 3 | 1.67 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 67 | 90 |
| 02-review-opus | 48 | 87 |
| 03-review-opus | 53 | 150 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | README.md, self/review-report.md, self/tests/feature-lifecycle.sh | — |
| 02-review-opus | LIFECYCLE.md, README.md, self/review-report.md, self/tests/feature-lifecycle.sh | — |
| 03-review-opus | /tmp/plan-capture.mZgNG7/scratch/hunks.sh, /tmp/plan-capture.mZgNG7/scratch/rows.py, self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.mZgNG7/scratch/rows.py | 03-review-opus | 03-review-opus | 55 |
| /tmp/plan-capture.mZgNG7/scratch/rows.py | 03-review-opus | 03-review-opus | 65 |

## Warnings

- re-hunting computed without streams for: 01-review-opus, 02-review-opus
- edit overlap computed without streams for: 01-review-opus, 02-review-opus

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
