# harness-driver-measures — cost and waste report

Generated 2026-11-03T14:30:15.272100+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $6.4255 | 52.2% |
| verify | $0.0000 | 0.0% |
| review | $5.8727 | 47.8% |
| **total** | **$12.2982** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $6.4255, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.0994  
cost per file touched: $1.7569

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 110.9 | $6.4255 | $0.0579 |
| verify | 0.0 | $0.0000 |  |
| review | 9.4 | $5.8727 | $0.6274 |
| **total** | **120.3** | **$12.2982** | $0.1023 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **19.8 min** from 2026-11-03T14:10:24+00:00 to 2026-11-03T14:30:14+00:00, PR opened 2026-11-03T14:30:14+00:00.
Passes: review 9.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 9.5 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $6.4255 † | 110.9 † | $0.0000 | 0.0 | $1.0828 | 1.6 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.6988 | 1.6 | 02-review-opus | escalated | escalations/02-review-opus.md |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $4.0911 | 6.1 | 03-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

220273 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 188 | $5.8727 | 9.4 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 4 | 4 | 1.00 |
| 02-review-opus | 2 | 2 | 1.00 |
| 03-review-opus | 9 | 4 | 2.25 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 78 | 50 |
| 02-review-opus | 51 | 70 |
| 03-review-opus | 43 | 109 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/harness/tests/smoke.sh` | Read | 02-review-opus, 03-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | harness/lib.sh, self/review-report.md, self/tests/README.md, self/tests/harness-driver-measures.sh | — |
| 02-review-opus | harness/tests/README.md, self/review-report.md | — |
| 03-review-opus | /tmp/plan-capture.XB1Rzk/scratch/wait.sh, harness/tests/README.md, harness/tests/smoke.sh, self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| harness/tests/README.md | 02-review-opus | 03-review-opus | 138 |
| harness/tests/README.md | 03-review-opus | 03-review-opus | 251 |
| self/review-report.md | 03-review-opus | 03-review-opus | 44 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
