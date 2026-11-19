# vendored-edit-ask — cost and waste report

Generated 2026-11-13T19:24:29.514612+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $3.2768 | 63.2% |
| verify | $0.0000 | 0.0% |
| review | $1.9068 | 36.8% |
| **total** | **$5.1835** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $3.2768, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $2.5918  
cost per file touched: $1.0367

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 223.8 | $3.2768 | $0.0146 |
| verify | 0.0 | $0.0000 |  |
| review | 3.8 | $1.9068 | $0.5084 |
| **total** | **227.5** | **$5.1835** | $0.0228 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **4.1 min** from 2026-11-13T19:20:23+00:00 to 2026-11-13T19:24:29+00:00, PR opened 2026-11-13T19:24:29+00:00.
Passes: review 3.8. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 4.7 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $3.2768 | 223.8 | $0.0000 | 0.0 | $1.9068 | 3.8 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

129905 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 52 | $1.9068 | 3.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 01-audit-opus | 9 | 4 | 2.25 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 64 | 50 |
| 01-audit-opus | 39 | 294 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.UwT9lj/scratch/hook_attack.py, /tmp/plan-capture.UwT9lj/scratch/hook_attack2.py, /tmp/plan-capture.UwT9lj/scratch/wire_attack.py, self/features/vendored-edit-ask/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.UwT9lj/scratch/hook_attack.py | 01-audit-opus | 01-audit-opus | 86 |
| /tmp/plan-capture.UwT9lj/scratch/hook_attack2.py | 01-audit-opus | 01-audit-opus | 48 |
| /tmp/plan-capture.UwT9lj/scratch/hook_attack.py | 01-audit-opus | 01-audit-opus | 151 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
