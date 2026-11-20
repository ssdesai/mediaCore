# pull-round-cleanups — cost and waste report

Generated 2026-11-20T04:00:26.084510+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: skipped — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $14.8153 | 76.4% |
| verify | $0.0000 | 0.0% |
| review | $4.5746 | 23.6% |
| **total** | **$19.3899** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $14.8153, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $3.2316  
cost per file touched: $1.9390

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 446.5 | $14.8153 | $0.0332 |
| verify | 0.0 | $0.0000 |  |
| review | 12.3 | $4.5746 | $0.3730 |
| **total** | **458.8** | **$19.3899** | $0.0423 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **150.6 min** from 2026-11-20T01:29:49+00:00 to 2026-11-20T04:00:25+00:00, PR opened 2026-11-20T04:00:25+00:00.
Passes: review 12.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 15.3 min over 6 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $14.8153 † | 446.5 † | $0.0000 | 0.0 | $1.5570 | 4.4 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.5318 | 3.7 | 02-review-opus | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.4858 | 4.1 | 03-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

299573 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 6 | 96 | $4.5746 | 12.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 01-audit-opus | 3 | 2 | 1.50 |
| 02-review-opus | 4 | 3 | 1.33 |
| 02-audit-opus | 2 | 2 | 1.00 |
| 03-review-opus | 1 | 1 | 1.00 |
| 03-audit-opus | 4 | 4 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 85 | 56 |
| 01-audit-opus | 79 | 256 |
| 02-review-opus | 67 | 67 |
| 02-audit-opus | 80 | 221 |
| 03-review-opus | 45 | 50 |
| 03-audit-opus | 80 | 289 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/analysis/roots.py` | Read | 01-audit-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | LIFECYCLE.md, self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.ihSZih/scratch/audit.sh, self/features/pull-round-cleanups/audit-report.md | — |
| 02-review-opus | analysis/README.md, analysis/roots.py, self/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.EydcRy/scratch/attack.sh, self/features/pull-round-cleanups/audit-report.md | — |
| 03-review-opus | self/review-report.md | — |
| 03-audit-opus | /tmp/plan-capture.w8wSNu/scratch/attack.sh, /tmp/plan-capture.w8wSNu/scratch/attack2.sh, /tmp/plan-capture.w8wSNu/scratch/attack3.sh, self/features/pull-round-cleanups/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.ihSZih/scratch/audit.sh | 01-audit-opus | 01-audit-opus | 714 |

---

Rates from `analysis/rates_history.json`, last checked 2026-11-18 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
