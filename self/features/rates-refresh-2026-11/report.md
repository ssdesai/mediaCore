# rates-refresh-2026-11 — cost and waste report

Generated 2026-11-18T13:16:19.699380+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $2.2338 | 61.7% |
| verify | $0.0000 | 0.0% |
| review | $1.3846 | 38.3% |
| **total** | **$3.6184** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $2.2338, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.8092  
cost per file touched: $0.9046

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 49.9 | $2.2338 | $0.0448 |
| verify | 0.0 | $0.0000 |  |
| review | 3.0 | $1.3846 | $0.4590 |
| **total** | **52.9** | **$3.6184** | $0.0684 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **3.4 min** from 2026-11-18T13:12:58+00:00 to 2026-11-18T13:16:19+00:00, PR opened 2026-11-18T13:16:19+00:00.
Passes: review 3.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.6 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $2.2338 | 49.9 | $0.0000 | 0.0 | $1.3846 | 3.0 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

101545 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 35 | $1.3846 | 3.0 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 01-audit-opus | 5 | 3 | 1.67 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 46 | 45 |
| 01-audit-opus | 78 | 265 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.zWHuF2/scratch/audit.py, /tmp/plan-capture.zWHuF2/scratch/rates_checks.sh, self/features/rates-refresh-2026-11/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.zWHuF2/scratch/audit.py | 01-audit-opus | 01-audit-opus | 217 |
| /tmp/plan-capture.zWHuF2/scratch/audit.py | 01-audit-opus | 01-audit-opus | 86 |

---

Rates from `analysis/rates_history.json`, last checked 2026-11-18 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
