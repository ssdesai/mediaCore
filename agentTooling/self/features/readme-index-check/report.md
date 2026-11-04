# readme-index-check — cost and waste report

Generated 2026-11-03T22:08:34.879971+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $3.9448 | 71.5% |
| build | $0.8681 | 15.7% |
| verify | $0.0000 | 0.0% |
| review | $0.7059 | 12.8% |
| **total** | **$5.5188** | 100.0% |

cost per plan: $1.3797  
cost per file touched: $0.5519

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| planning: sessions | 36.4 | $0.7489 | $0.0206 |
| planning: delegates | 8.1 | $3.1959 | $0.3946 |
| build | 2.8 | $0.8681 | $0.3148 |
| verify | 0.0 | $0.0000 |  |
| review | 1.3 | $0.7059 | $0.5251 |
| **total** | **48.6** | **$5.5188** | $0.1136 |

Planning minutes are transcript spans: a delegate's span is its working time, a session's includes every minute nobody was typing, so the delegates row is the planning figure for a feature planned by delegates and the sessions row for one planned by hand. Build, verify and review minutes are summed over plans, so a parallel pair counts twice — the wall clock below does not.

Wall clock, as the runner saw it: **15.4 min** from 2026-11-03T21:53:07+00:00 to 2026-11-03T22:08:34+00:00, PR opened 2026-11-03T22:08:34+00:00.
Passes: build 2.8, review 1.4. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 4.2 min over 4 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $0.8681 | 2.8 | $0.0000 | 0.0 | $0.7059 | 1.3 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

200368 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 13 | $0.7059 | 1.3 |  |
| sonnet | 3 | 34 | $0.8681 | 2.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 02-tests-readme-index-sonnet | 4 | 3 | 1.33 |
| 03-checker-sonnet | 1 | 1 | 1.00 |
| 04-gate-and-docs-sonnet | 11 | 6 | 1.83 |
| 01-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 02-tests-readme-index-sonnet | 164 | 294 |
| 03-checker-sonnet | 142 | 283 |
| 04-gate-and-docs-sonnet | 188 | 100 |
| 01-review-opus | 81 | 80 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 03-checker-sonnet | — | check-plans.sh |
| 01-review-opus | check-readme-index.py, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
