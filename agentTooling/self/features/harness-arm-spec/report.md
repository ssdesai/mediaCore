# harness-arm-spec — cost and waste report

Generated 2026-11-04T15:01:23.696548+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $3.1932 | 54.6% |
| build | $1.4837 | 25.4% |
| verify | $0.2668 | 4.6% |
| review | $0.8998 | 15.4% |
| **total** | **$5.8435** | 100.0% |

cost per plan: $0.8348  
cost per file touched: $0.3246

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| planning: sessions | 16.1 | $2.8031 | $0.1736 |
| planning: delegates | 1.4 | $0.3901 | $0.2890 |
| build | 4.6 | $1.4837 | $0.3208 |
| verify | 0.7 | $0.2668 | $0.3935 |
| review | 2.5 | $0.8998 | $0.3670 |
| **total** | **25.3** | **$5.8435** | $0.2314 |

Planning minutes are transcript spans: a delegate's span is its working time, a session's includes every minute nobody was typing, so the delegates row is the planning figure for a feature planned by delegates and the sessions row for one planned by hand. Build, verify and review minutes are summed over plans, so a parallel pair counts twice — the wall clock below does not.

Wall clock, as the runner saw it: **19.8 min** from 2026-11-04T14:41:32+00:00 to 2026-11-04T15:01:22+00:00, PR opened 2026-11-04T15:01:22+00:00.
Passes: build 4.8, verify 0.7, review 2.5. Gates: 11.8 min over 1 run(s). Plans as timed by the runner: 8.0 min over 7 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $1.4837 | 4.6 | $0.2668 | 0.7 | $0.8998 | 2.5 | 07-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

346780 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 20 | $0.8998 | 2.5 |  |
| sonnet | 6 | 115 | $1.7504 | 5.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-tests-arm-spec-sonnet | 2 | 2 | 1.00 |
| 02-lib-templates-sonnet | 8 | 5 | 1.60 |
| 03-driver-sonnet | 21 | 2 | 10.50 |
| 04-smoke-sonnet | 2 | 1 | 2.00 |
| 05-docs-sonnet | 18 | 7 | 2.57 |
| 07-review-opus | 4 | 3 | 1.33 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-tests-arm-spec-sonnet | 100 | 270 |
| 02-lib-templates-sonnet | 105 | 79 |
| 03-driver-sonnet | 83 | 97 |
| 04-smoke-sonnet | 64 | 108 |
| 05-docs-sonnet | 65 | 92 |
| 06-verify-sonnet | 33 | 0 |
| 07-review-opus | 76 | 75 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/harness/lib.sh` | Read | 01-tests-arm-spec-sonnet, 02-lib-templates-sonnet, 04-smoke-sonnet, 07-review-opus |
| `/home/user/agentTooling/harness/new-experiment.sh` | Read | 03-driver-sonnet, 04-smoke-sonnet |
| `/home/user/agentTooling/harness/run.sh` | Read | 03-driver-sonnet, 04-smoke-sonnet, 06-verify-sonnet |
| `/home/user/agentTooling/harness/tests/smoke.sh` | Read | 04-smoke-sonnet, 05-docs-sonnet |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 05-docs-sonnet | — | arm-spec.sh, arm-spec.shared.md, experiment.json, harness/tests/*.sh, harness/tests/arm-spec.sh, isolation.md, lib.sh, new-experiment.sh, scorecard-programs.cells.md, self/features/harness-arm-spec/, tests/arm-spec.sh |
| 07-review-opus | harness/README.md, harness/tests/arm-spec.sh, self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| harness/tests/arm-spec.sh | 01-tests-arm-spec-sonnet | 07-review-opus | 84 |
| harness/README.md | 05-docs-sonnet | 07-review-opus | 151 |

## Warnings

- plan 06-verify-sonnet has 0 files_edited; excluded from churn ratio

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
