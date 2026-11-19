# audit-blocks-only-new — cost and waste report

Generated 2026-11-16T22:45:53.894761+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $3.0249 | 55.0% |
| verify | $0.0000 | 0.0% |
| review | $2.4796 | 45.0% |
| **total** | **$5.5045** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $3.0249, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.3761  
cost per file touched: $0.5504

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 121.8 | $3.0249 | $0.0248 |
| verify | 0.0 | $0.0000 |  |
| review | 7.2 | $2.4796 | $0.3454 |
| **total** | **129.0** | **$5.5045** | $0.0427 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **8.1 min** from 2026-11-16T22:37:28+00:00 to 2026-11-16T22:45:35+00:00, PR opened 2026-11-16T22:45:35+00:00.
Passes: review 7.4. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 10.2 min over 4 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $3.0249 † | 121.8 † | $0.0000 | 0.0 | $1.2372 | 3.0 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.2424 | 4.1 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

163318 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 4 | 77 | $2.4796 | 7.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 01-audit-opus | 8 | 5 | 1.60 |
| 02-review-opus | 1 | 1 | 1.00 |
| 02-audit-opus | 4 | 4 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 56 | 57 |
| 01-audit-opus | 78 | 297 |
| 02-review-opus | 53 | 70 |
| 02-audit-opus | 78 | 227 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/templates/SECURITY_AUDIT.md` | Read | 01-review-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md, templates/SECURITY_AUDIT.md | — |
| 01-audit-opus | /tmp/plan-capture.2k4lYZ/scratch/audit.sh, /tmp/plan-capture.2k4lYZ/scratch/check.sh, /tmp/plan-capture.2k4lYZ/scratch/one.sh, /tmp/plan-capture.2k4lYZ/scratch/reports.sh, self/features/audit-blocks-only-new/audit-report.md | — |
| 02-review-opus | self/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.IQZ83S/scratch/hook.py, /tmp/plan-capture.IQZ83S/scratch/reports.sh, /tmp/plan-capture.IQZ83S/scratch/setup.sh, self/features/audit-blocks-only-new/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.2k4lYZ/scratch/audit.sh | 01-audit-opus | 01-audit-opus | 88 |
| /tmp/plan-capture.2k4lYZ/scratch/audit.sh | 01-audit-opus | 01-audit-opus | 87 |
| /tmp/plan-capture.2k4lYZ/scratch/audit.sh | 01-audit-opus | 01-audit-opus | 56 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
