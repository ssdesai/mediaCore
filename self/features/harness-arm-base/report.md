# harness-arm-base — cost and waste report

Generated 2026-11-03T23:17:08.921048+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $6.1939 | 59.5% |
| build | $1.8728 | 18.0% |
| verify | $0.2534 | 2.4% |
| review | $2.0875 | 20.1% |
| **total** | **$10.4077** | 100.0% |

cost per plan: $1.0408  
cost per file touched: $0.5782

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| planning: sessions | 105.3 | $1.3439 | $0.0128 |
| planning: delegates | 11.3 | $4.8500 | $0.4273 |
| build | 6.3 | $1.8728 | $0.2959 |
| verify | 6.3 | $0.2534 | $0.0405 |
| review | 3.3 | $2.0875 | $0.6378 |
| **total** | **132.5** | **$10.4077** | $0.0786 |

Planning minutes are transcript spans: a delegate's span is its working time, a session's includes every minute nobody was typing, so the delegates row is the planning figure for a feature planned by delegates and the sessions row for one planned by hand. Build, verify and review minutes are summed over plans, so a parallel pair counts twice — the wall clock below does not.

Wall clock, as the runner saw it: **80.9 min** from 2026-11-03T21:56:12+00:00 to 2026-11-03T23:17:07+00:00, PR opened 2026-11-03T23:17:07+00:00.
Passes: build 6.5, verify 6.3, review 3.4. Gates: 11.3 min over 1 run(s). Plans as timed by the runner: 16.1 min over 10 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $1.8728 | 6.3 | $0.2534 | 6.3 | $1.3759 | 2.0 | 09-review-opus | clean | — |
| 2 | $0.0000 | 0.0 | $0.0000 | 0.0 | $0.7117 | 1.2 | 10-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

454576 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 55 | $2.0875 | 3.3 |  |
| sonnet | 8 | 173 | $2.1262 | 12.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-base-arms-driver-sonnet | 24 | 3 | 8.00 |
| 02-reading-metrics-sonnet | 11 | 3 | 3.67 |
| 03-scorecard-sonnet | 5 | 1 | 5.00 |
| 04-tests-arm-base-sonnet | 3 | 3 | 1.00 |
| 05-tests-reading-metrics-sonnet | 4 | 3 | 1.33 |
| 06-tests-smoke-base-arms-sonnet | 10 | 2 | 5.00 |
| 07-docs-sonnet | 31 | 7 | 4.43 |
| 08-verify-sonnet | 1 | 1 | 1.00 |
| 09-review-opus | 3 | 2 | 1.50 |
| 10-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-base-arms-driver-sonnet | 178 | 125 |
| 02-reading-metrics-sonnet | 152 | 261 |
| 03-scorecard-sonnet | 76 | 57 |
| 04-tests-arm-base-sonnet | 91 | 157 |
| 05-tests-reading-metrics-sonnet | 105 | 268 |
| 06-tests-smoke-base-arms-sonnet | 121 | 151 |
| 07-docs-sonnet | 141 | 152 |
| 08-verify-sonnet | 34 | 2 |
| 09-review-opus | 80 | 96 |
| 10-review-opus | 62 | 62 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/harness/README.md` | Read | 07-docs-sonnet, 09-review-opus |
| `/home/user/agentTooling/harness/lib.sh` | Read | 01-base-arms-driver-sonnet, 04-tests-arm-base-sonnet |
| `/home/user/agentTooling/harness/new-experiment.sh` | Read | 01-base-arms-driver-sonnet, 09-review-opus |
| `/home/user/agentTooling/harness/reading_metrics.py` | Read | 07-docs-sonnet, 09-review-opus |
| `/home/user/agentTooling/harness/run.sh` | Read | 01-base-arms-driver-sonnet, 02-reading-metrics-sonnet, 09-review-opus |
| `/home/user/agentTooling/harness/tests/README.md` | Read | 06-tests-smoke-base-arms-sonnet, 07-docs-sonnet |
| `/home/user/agentTooling/harness/tests/scorecard-arms.sh` | Read | 04-tests-arm-base-sonnet, 05-tests-reading-metrics-sonnet |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 08-verify-sonnet | harness/tests/smoke.sh | — |
| 09-review-opus | harness/README.md, self/review-report.md | — |
| 10-review-opus | self/README.md, self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/gate.sh | 04-tests-arm-base-sonnet | 05-tests-reading-metrics-sonnet | 67 |
| harness/tests/README.md | 04-tests-arm-base-sonnet | 05-tests-reading-metrics-sonnet | 64 |
| harness/README.md | 07-docs-sonnet | 07-docs-sonnet | 58 |
| harness/README.md | 07-docs-sonnet | 07-docs-sonnet | 277 |
| harness/README.md | 07-docs-sonnet | 09-review-opus | 162 |
| harness/README.md | 07-docs-sonnet | 09-review-opus | 275 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
