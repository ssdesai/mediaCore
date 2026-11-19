# backlog-cleanup — cost and waste report

Generated 2026-11-17T15:28:07.875964+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $3.4054 | 77.9% |
| verify | $0.0000 | 0.0% |
| review | $0.9678 | 22.1% |
| **total** | **$4.3733** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $3.4054, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.3733  
cost per file touched: $0.8747

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 51.9 | $3.4054 | $0.0656 |
| verify | 0.0 | $0.0000 |  |
| review | 1.6 | $0.9678 | $0.6066 |
| **total** | **53.5** | **$4.3733** | $0.0818 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **1.9 min** from 2026-11-17T15:26:13+00:00 to 2026-11-17T15:28:07+00:00, PR opened 2026-11-17T15:28:07+00:00.
Passes: review 1.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.6 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $3.4054 | 51.9 | $0.0000 | 0.0 | $0.9678 | 1.6 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

72935 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 18 | $0.9678 | 1.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 5 | 5 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 62 | 123 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | /tmp/plan-capture.UqcI4p/scratch/check.sh, /tmp/plan-capture.UqcI4p/scratch/check2.sh, /tmp/plan-capture.UqcI4p/scratch/check3.sh, /tmp/plan-capture.UqcI4p/scratch/check4.sh, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
