# cloud-checkpoint-push — cost and waste report

Generated 2026-11-08T00:14:08.479195+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $8.0957 | 89.7% |
| verify | $0.0000 | 0.0% |
| review | $0.9284 | 10.3% |
| **total** | **$9.0240** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $8.0957, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $9.0240  
cost per file touched: $4.5120

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 177.7 | $8.0957 | $0.0456 |
| ↳ acceptance tests | 2.5 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 1.5 | $0.9284 | $0.6393 |
| **total** | **179.2** | **$9.0240** | $0.0504 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **87.4 min** from 2026-11-07T22:46:43+00:00 to 2026-11-08T00:14:07+00:00, PR opened 2026-11-08T00:14:07+00:00.
Passes: review 1.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.5 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $8.0957 | 177.7 | $0.0000 | 0.0 | $0.9284 | 1.5 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

66094 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 24 | $0.9284 | 1.5 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 69 | 84 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | feature-capture.sh, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
