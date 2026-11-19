# hook-planted-gitdir — cost and waste report

Generated 2026-11-17T19:06:28.898716+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $4.5849 | 73.0% |
| verify | $0.0000 | 0.0% |
| review | $1.6960 | 27.0% |
| **total** | **$6.2809** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $4.5849, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $3.1405  
cost per file touched: $0.8973

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 103.4 | $4.5849 | $0.0443 |
| verify | 0.0 | $0.0000 |  |
| review | 5.4 | $1.6960 | $0.3148 |
| **total** | **108.8** | **$6.2809** | $0.0577 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **6.0 min** from 2026-11-17T19:00:26+00:00 to 2026-11-17T19:06:28+00:00, PR opened 2026-11-17T19:06:28+00:00.
Passes: review 5.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 7.5 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $4.5849 | 103.4 | $0.0000 | 0.0 | $1.6960 | 5.4 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

98555 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 35 | $1.6960 | 5.4 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 01-audit-opus | 7 | 6 | 1.17 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 74 | 83 |
| 01-audit-opus | 79 | 425 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.tQbAoJ/scratch/one.py, /tmp/plan-capture.tQbAoJ/scratch/prove.sh, /tmp/plan-capture.tQbAoJ/scratch/run.py, /tmp/plan-capture.tQbAoJ/scratch/run2.py, /tmp/plan-capture.tQbAoJ/scratch/setup.sh, self/features/hook-planted-gitdir/audit-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
