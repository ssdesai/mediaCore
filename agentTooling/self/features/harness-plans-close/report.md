# harness-plans-close — cost and waste report

Generated 2026-11-04T20:38:42.329477+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $1.9002 | 54.1% |
| verify | $0.0000 | 0.0% |
| review | $1.6098 | 45.9% |
| **total** | **$3.5100** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $1.9002, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.1700  
cost per file touched: $0.5850

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 57.4 | $1.9002 | $0.0331 |
| verify | 0.0 | $0.0000 |  |
| review | 3.1 | $1.6098 | $0.5139 |
| **total** | **60.5** | **$3.5100** | $0.0580 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **31.3 min** from 2026-11-04T20:07:22+00:00 to 2026-11-04T20:38:41+00:00, PR opened 2026-11-04T20:38:41+00:00.
Passes: review 3.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.2 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $1.9002 † | 57.4 † | $0.0000 | 0.0 | $0.5953 | 1.3 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.5469 | 1.1 | 02-review-opus | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.4675 | 0.8 | 03-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

118578 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 48 | $1.6098 | 3.1 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 02-review-opus | 6 | 5 | 1.20 |
| 03-review-opus | 3 | 2 | 1.50 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 50 | 50 |
| 02-review-opus | 40 | 52 |
| 03-review-opus | 35 | 40 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/self/review-report.md` | Read | 02-review-opus, 03-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | harness/README.md, self/review-report.md | — |
| 02-review-opus | harness/README.md, harness/methods/plans/run.sh, harness/tests/README.md, harness/tests/plans-method.sh, self/review-report.md | — |
| 03-review-opus | self/features/harness-plans-close/README.md, self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| harness/README.md | 01-review-opus | 02-review-opus | 79 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
