# start-tree-guard — cost and waste report

Generated 2026-10-31T13:52:19.610485+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $1.2206 | 65.4% |
| verify | $0.0000 | 0.0% |
| review | $0.6443 | 34.6% |
| **total** | **$1.8649** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $1.2206, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.8649  
cost per file touched: $0.6216

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 27.6 | $1.2206 | $0.0443 |
| verify | 0.0 | $0.0000 |  |
| review | 1.8 | $0.6443 | $0.3599 |
| **total** | **29.3** | **$1.8649** | $0.0636 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **2.1 min** from 2026-10-31T13:50:13+00:00 to 2026-10-31T13:52:19+00:00, PR opened 2026-10-31T13:52:19+00:00.
Passes: review 1.8. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.8 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $1.2206 | 27.6 | $0.0000 | 0.0 | $0.6443 | 1.8 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

41345 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 18 | $0.6443 | 1.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 5 | 3 | 1.67 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 69 | 63 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md, self/tests/README.md, self/tests/orchestrator-brief.sh | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
