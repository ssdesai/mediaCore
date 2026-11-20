# hook-allowlist-design — cost and waste report

Generated 2026-11-19T18:17:02.424393+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $21.5845 | 94.3% |
| verify | $0.0000 | 0.0% |
| review | $1.3043 | 5.7% |
| **total** | **$22.8888** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $21.5845, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $22.8888  
cost per file touched: $11.4444

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 126.8 | $21.5845 | $0.1703 |
| verify | 0.0 | $0.0000 |  |
| review | 2.7 | $1.3043 | $0.4828 |
| **total** | **129.5** | **$22.8888** | $0.1768 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **3.0 min** from 2026-11-19T18:14:03+00:00 to 2026-11-19T18:17:01+00:00, PR opened 2026-11-19T18:17:01+00:00.
Passes: review 2.7. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 2.7 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $21.5845 | 126.8 | $0.0000 | 0.0 | $1.3043 | 2.7 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

87361 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 29 | $1.3043 | 2.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 2 | 1.50 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 109 | 88 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/DESIGN-2026-11-19-hook-allowlist.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-11-18 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
