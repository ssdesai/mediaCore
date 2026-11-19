# hook-silent-allow-sweep — cost and waste report

Generated 2026-11-19T16:09:05.645039+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $24.1033 | 80.8% |
| verify | $0.0000 | 0.0% |
| review | $5.7360 | 19.2% |
| **total** | **$29.8393** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $24.1033, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $7.4598  
cost per file touched: $1.8650

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 1305.2 | $24.1033 | $0.0185 |
| verify | 0.0 | $0.0000 |  |
| review | 20.3 | $5.7360 | $0.2827 |
| **total** | **1325.4** | **$29.8393** | $0.0225 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **173.9 min** from 2026-11-19T13:15:07+00:00 to 2026-11-19T16:09:04+00:00, PR opened 2026-11-19T16:09:04+00:00.
Passes: review 20.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 23.9 min over 4 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $24.1033 † | 1305.2 † | $0.0000 | 0.0 | $3.2159 | 12.0 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.5200 | 8.3 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

322522 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 4 | 109 | $5.7360 | 20.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 2 | 1.50 |
| 01-audit-opus | 10 | 7 | 1.43 |
| 02-review-opus | 1 | 1 | 1.00 |
| 02-audit-opus | 9 | 8 | 1.12 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 74 | 124 |
| 01-audit-opus | 81 | 735 |
| 02-review-opus | 48 | 61 |
| 02-audit-opus | 81 | 664 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md, self/tests/orchestrator-role.sh | — |
| 01-audit-opus | /tmp/plan-capture.Uxvmm0/scratch/audit.py, /tmp/plan-capture.Uxvmm0/scratch/gencases.py, /tmp/plan-capture.Uxvmm0/scratch/one.py, /tmp/plan-capture.Uxvmm0/scratch/refuse.sh, /tmp/plan-capture.Uxvmm0/scratch/role.py, /tmp/plan-capture.Uxvmm0/scratch/table.py, self/features/hook-silent-allow-sweep/audit-report.md | — |
| 02-review-opus | self/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.oNrczl/scratch/cfg.sh, /tmp/plan-capture.oNrczl/scratch/cred.cfg, /tmp/plan-capture.oNrczl/scratch/drive.py, /tmp/plan-capture.oNrczl/scratch/drive2.py, /tmp/plan-capture.oNrczl/scratch/plant.sh, /tmp/plan-capture.oNrczl/scratch/role.sh, /tmp/plan-capture.oNrczl/scratch/setup.sh, self/features/hook-silent-allow-sweep/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.Uxvmm0/scratch/audit.py | 01-audit-opus | 01-audit-opus | 58 |

---

Rates from `analysis/rates_history.json`, last checked 2026-11-18 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
