# split-tests-method — cost and waste report

Generated 2026-11-07T17:31:22.033576+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $12.9272 | 82.8% |
| verify | $0.0000 | 0.0% |
| review | $2.6760 | 17.2% |
| **total** | **$15.6033** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $12.9272, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $5.2011  
cost per file touched: $3.9008

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 55.7 | $12.9272 | $0.2322 |
| verify | 0.0 | $0.0000 |  |
| review | 4.7 | $2.6760 | $0.5641 |
| **total** | **60.4** | **$15.6033** | $0.2583 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **30.4 min** from 2026-11-07T17:00:34+00:00 to 2026-11-07T17:30:59+00:00, PR opened 2026-11-07T17:30:59+00:00.
Passes: review 4.9. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 4.9 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $12.9272 † | 55.7 † | $0.0000 | 0.0 | $1.2176 | 2.3 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.8340 | 1.6 | 02-review-opus | escalated | escalations/02-review-opus.md |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.6244 | 0.9 | 03-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

208797 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 52 | $2.6760 | 4.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 6 | 3 | 2.00 |
| 02-review-opus | 2 | 2 | 1.00 |
| 03-review-opus | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 69 | 111 |
| 02-review-opus | 65 | 60 |
| 03-review-opus | 69 | 68 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling-split-tests-method/self/features/split-tests-method/README.md` | Read | 01-review-opus, 02-review-opus |
| `/home/user/agentTooling-split-tests-method/self/gate-report.txt` | Read | 01-review-opus, 03-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md, self/tests/README.md, self/tests/split-tests-pair.sh | — |
| 02-review-opus | harness/methods/README.md, self/review-report.md | — |
| 03-review-opus | self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
