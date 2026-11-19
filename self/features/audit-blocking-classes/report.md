# audit-blocking-classes — cost and waste report

Generated 2026-11-16T14:46:00.193139+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $4.6746 | 70.8% |
| verify | $0.0000 | 0.0% |
| review | $1.9315 | 29.2% |
| **total** | **$6.6061** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $4.6746, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $3.3031  
cost per file touched: $0.8258

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 83.6 | $4.6746 | $0.0559 |
| verify | 0.0 | $0.0000 |  |
| review | 5.8 | $1.9315 | $0.3347 |
| **total** | **89.4** | **$6.6061** | $0.0739 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **6.3 min** from 2026-11-16T14:39:43+00:00 to 2026-11-16T14:45:59+00:00, PR opened 2026-11-16T14:45:59+00:00.
Passes: review 5.9. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 7.2 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $4.6746 | 83.6 | $0.0000 | 0.0 | $1.9315 | 5.8 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

112517 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 37 | $1.9315 | 5.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 4 | 2 | 2.00 |
| 01-audit-opus | 7 | 6 | 1.17 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 81 | 68 |
| 01-audit-opus | 76 | 356 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/features/audit-blocking-classes/NOTES.md, self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.cmiRqc/scratch/close.sh, /tmp/plan-capture.cmiRqc/scratch/gen.py, /tmp/plan-capture.cmiRqc/scratch/hook.sh, /tmp/plan-capture.cmiRqc/scratch/start.sh, /tmp/plan-capture.cmiRqc/scratch/unit.sh, self/features/audit-blocking-classes/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/features/audit-blocking-classes/NOTES.md | 01-review-opus | 01-review-opus | 184 |
| /tmp/plan-capture.cmiRqc/scratch/hook.sh | 01-audit-opus | 01-audit-opus | 41 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
