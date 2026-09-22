# prune-fresh-branch — cost and waste report

Generated 2026-09-22T21:16:45.800875+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $0.0000 | 0.0% |
| verify | $0.0000 | 0.0% |
| review | $1.5887 | 100.0% |
| **total** | **$1.5887** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $0.0000, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $0.7944  
cost per file touched: $0.5296

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 0.0 | $0.0000 |  |
| verify | 0.0 | $0.0000 |  |
| review | 3.2 | $1.5887 | $0.4944 |
| **total** | **3.2** | **$1.5887** | $0.4944 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **10.3 min** from 2026-09-22T21:06:25+00:00 to 2026-09-22T21:16:43+00:00, PR opened 2026-09-22T21:16:43+00:00.
Passes: review 3.3. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.3 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.6921 | 1.5 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.8966 | 1.7 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

120744 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 28 | $1.5887 | 3.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 02-review-opus | 3 | 3 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 50 | 61 |
| 02-review-opus | 39 | 41 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/Users/sahildesai/dev/agentTooling/.worktrees/prune-fresh-branch/self/gate-report.txt` | Read | 01-review-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 02-review-opus | feature-start.sh, self/review-report.md, self/tests/README.md | — |

## Cross-plan edit overlap

none found.

---

Rates last verified 2026-09-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
