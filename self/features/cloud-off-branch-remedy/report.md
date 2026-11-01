# cloud-off-branch-remedy — cost and waste report

Generated 2026-10-27T18:22:25.082472+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $6.0110 | 73.4% |
| verify | $0.0000 | 0.0% |
| review | $2.1819 | 26.6% |
| **total** | **$8.1930** | 100.0% |

1 planning row carried from the capture of 2026-10-27: the capture could not reach its transcript (an earlier round's container, or expired), so the planning figure chains that capture's dollars with this one's.

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $6.0110, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $2.7310  
cost per file touched: $2.7310

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 217.9 | $6.0110 | $0.0276 |
| verify | 0.0 | $0.0000 |  |
| review | 3.5 | $2.1819 | $0.6290 |
| **total** | **221.4** | **$8.1930** | $0.0370 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **29.2 min** from 2026-10-27T17:53:12+00:00 to 2026-10-27T18:22:24+00:00, PR opened 2026-10-27T18:22:24+00:00.
Passes: review 4.9. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 4.9 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $6.0110 † | 217.9 † | $0.0000 | 0.0 | $0.9977 | 1.9 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.6573 | 0.8 | 02-review-opus | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.5269 | 0.8 | 03-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

182836 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 49 | $2.1819 | 3.5 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 02-review-opus | 1 | 1 | 1.00 |
| 03-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 73 | 79 |
| 02-review-opus | 46 | 51 |
| 03-review-opus | 44 | 71 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | hooks/allow-repo-commands.sh, self/review-report.md | — |
| 02-review-opus | self/review-report.md | — |
| 03-review-opus | /tmp/plan-capture.4lGe2y/scratch/wd.py, self/review-report.md | — |

## Cross-plan edit overlap

none found.

## Warnings

- re-hunting computed without streams for: 01-review-opus, 02-review-opus
- edit overlap computed without streams for: 01-review-opus, 02-review-opus

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
