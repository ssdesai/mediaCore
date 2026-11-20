# orchestrator-record-move-guard — cost and waste report

Generated 2026-11-20T12:40:28.910670+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: skipped — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $7.4566 | 79.0% |
| verify | $0.0000 | 0.0% |
| review | $1.9804 | 21.0% |
| **total** | **$9.4370** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $7.4566, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.7185  
cost per file touched: $2.3592

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 966.6 | $7.4566 | $0.0077 |
| verify | 0.0 | $0.0000 |  |
| review | 5.9 | $1.9804 | $0.3348 |
| **total** | **972.5** | **$9.4370** | $0.0097 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **6.6 min** from 2026-11-20T12:33:53+00:00 to 2026-11-20T12:40:28+00:00, PR opened 2026-11-20T12:40:28+00:00.
Passes: review 6.0. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 7.3 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $7.4566 | 966.6 | $0.0000 | 0.0 | $1.9804 | 5.9 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

129434 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 40 | $1.9804 | 5.9 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 01-audit-opus | 6 | 2 | 3.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 82 | 60 |
| 01-audit-opus | 79 | 553 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/analysis/roots.py` | Read | 01-audit-opus, 01-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | hooks/allow-repo-commands.sh, self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.FQn39D/scratch/audit.py, self/features/orchestrator-record-move-guard/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.FQn39D/scratch/audit.py | 01-audit-opus | 01-audit-opus | 52 |
| /tmp/plan-capture.FQn39D/scratch/audit.py | 01-audit-opus | 01-audit-opus | 97 |
| /tmp/plan-capture.FQn39D/scratch/audit.py | 01-audit-opus | 01-audit-opus | 242 |
| /tmp/plan-capture.FQn39D/scratch/audit.py | 01-audit-opus | 01-audit-opus | 274 |

---

Rates from `analysis/rates_history.json`, last checked 2026-11-18 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
