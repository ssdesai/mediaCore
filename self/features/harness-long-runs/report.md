# harness-long-runs — cost and waste report

Generated 2026-11-04T22:48:51.291657+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $4.8055 | 55.0% |
| build | $1.5113 | 17.3% |
| verify | $0.3547 | 4.1% |
| review | $2.0734 | 23.7% |
| **total** | **$8.7449** | 100.0% |

cost per plan: $1.2493  
cost per file touched: $0.6246

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| planning: sessions | 58.1 | $3.7455 | $0.0645 |
| planning: delegates | 6.6 | $1.0601 | $0.1598 |
| build | 5.4 | $1.5113 | $0.2778 |
| verify | 1.0 | $0.3547 | $0.3512 |
| review | 3.8 | $2.0734 | $0.5423 |
| **total** | **75.0** | **$8.7449** | $0.1166 |

Planning minutes are transcript spans: a delegate's span is its working time, a session's includes every minute nobody was typing, so the delegates row is the planning figure for a feature planned by delegates and the sessions row for one planned by hand. Build, verify and review minutes are summed over plans, so a parallel pair counts twice — the wall clock below does not.

Wall clock, as the runner saw it: **37.8 min** from 2026-11-04T22:11:02+00:00 to 2026-11-04T22:48:50+00:00, PR opened 2026-11-04T22:48:50+00:00.
Passes: build 5.5, verify 1.0, review 3.9. Gates: 10.7 min over 1 run(s). Plans as timed by the runner: 10.5 min over 7 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $1.5113 | 5.4 | $0.3547 | 1.0 | $1.4568 | 2.6 | 06-review-opus | escalated | escalations/06-review-opus.md |
| 2 | $0.0000 | 0.0 | $0.0000 | 0.0 | $0.6166 | 1.2 | 07-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

422037 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 53 | $2.0734 | 3.8 |  |
| sonnet | 5 | 84 | $1.8660 | 6.4 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-tests-long-runs-sonnet | 7 | 3 | 2.33 |
| 02-run-cells-budget-sonnet | 7 | 2 | 3.50 |
| 03-run-reset-lock-sonnet | 13 | 3 | 4.33 |
| 04-docs-long-runs-sonnet | 8 | 6 | 1.33 |
| 05-verify-sonnet | 3 | 2 | 1.50 |
| 06-review-opus | 8 | 4 | 2.00 |
| 07-review-opus | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-tests-long-runs-sonnet | 119 | 325 |
| 02-run-cells-budget-sonnet | 104 | 196 |
| 03-run-reset-lock-sonnet | 108 | 237 |
| 04-docs-long-runs-sonnet | 94 | 134 |
| 05-verify-sonnet | 35 | 20 |
| 06-review-opus | 91 | 116 |
| 07-review-opus | 48 | 46 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/harness/README.md` | Read | 04-docs-long-runs-sonnet, 06-review-opus |
| `/home/user/agentTooling/harness/lib.sh` | Read | 01-tests-long-runs-sonnet, 02-run-cells-budget-sonnet, 03-run-reset-lock-sonnet, 04-docs-long-runs-sonnet, 06-review-opus |
| `/home/user/agentTooling/harness/run.sh` | Read | 02-run-cells-budget-sonnet, 03-run-reset-lock-sonnet, 04-docs-long-runs-sonnet, 05-verify-sonnet, 06-review-opus, 07-review-opus |
| `/home/user/agentTooling/harness/tests/long-runs.sh` | Read | 02-run-cells-budget-sonnet, 05-verify-sonnet, 06-review-opus |
| `/home/user/agentTooling/self/gate-report.txt` | Read | 05-verify-sonnet, 06-review-opus, 07-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-tests-long-runs-sonnet | — | #!/usr/bin/env bash |
| 03-run-reset-lock-sonnet | /tmp/plan-capture.VndZsW/scratch/reset-block.txt | — |
| 05-verify-sonnet | /tmp/plan-capture.XlwLQS/scratch/hook.py, harness/tests/long-runs.sh | — |
| 06-review-opus | harness/README.md, harness/SPEC.md, harness/run.sh, self/review-report.md | — |
| 07-review-opus | self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| harness/run.sh | 03-run-reset-lock-sonnet | 03-run-reset-lock-sonnet | 110 |
| harness/run.sh | 02-run-cells-budget-sonnet | 03-run-reset-lock-sonnet | 86 |
| harness/run.sh | 02-run-cells-budget-sonnet | 03-run-reset-lock-sonnet | 191 |
| harness/tests/long-runs.sh | 01-tests-long-runs-sonnet | 05-verify-sonnet | 45 |
| harness/tests/long-runs.sh | 05-verify-sonnet | 05-verify-sonnet | 204 |
| harness/run.sh | 02-run-cells-budget-sonnet | 06-review-opus | 137 |
| harness/run.sh | 03-run-reset-lock-sonnet | 06-review-opus | 55 |
| harness/run.sh | 02-run-cells-budget-sonnet | 06-review-opus | 53 |
| harness/README.md | 04-docs-long-runs-sonnet | 06-review-opus | 125 |
| harness/README.md | 04-docs-long-runs-sonnet | 06-review-opus | 107 |
| harness/README.md | 04-docs-long-runs-sonnet | 06-review-opus | 60 |
| harness/SPEC.md | 04-docs-long-runs-sonnet | 06-review-opus | 56 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
