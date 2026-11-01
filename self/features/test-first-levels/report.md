# test-first-levels — cost and waste report

Generated 2026-09-10T03:44:30.471071+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $1.8154 | 27.4% |
| verify | $1.9883 | 30.0% |
| review | $2.8200 | 42.6% |
| **total** | **$6.6237** | 100.0% |

cost per plan: $1.1040  
cost per file touched: $0.3896

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| planning: sessions | 0.0 | $0.0000 |  |
| planning: delegates | 0.0 | $0.0000 |  |
| build | 7.0 | $1.8154 | $0.2601 |
| verify | 5.7 | $1.9883 | $0.3481 |
| review | 8.9 | $2.8200 | $0.3174 |
| **total** | **21.6** | **$6.6237** | $0.3070 |

Planning minutes are transcript spans: a delegate's span is its working time, a session's includes every minute nobody was typing, so the delegates row is the planning figure for a feature planned by delegates and the sessions row for one planned by hand. Build, verify and review minutes are summed over plans, so a parallel pair counts twice — the wall clock below does not.

No wall clock: this feature has no `timing.jsonl`, so its batch ran on a runner that predates stamping. Only the executors' own durations are known.

## Cold-start tax

331273 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| haiku | 1 | 24 | $0.1859 | 2.1 | plan 67-gate-label-and-skip-haiku took 24 turns on haiku (> 8, may have needed more judgment than haiku gives) |
| opus | 1 | 34 | $2.8200 | 8.9 |  |
| sonnet | 4 | 102 | $3.6178 | 10.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 65-runner-sentinels-sonnet | 11 | 4 | 2.75 |
| 66-batch-level-loop-sonnet | 6 | 2 | 3.00 |
| 67-gate-label-and-skip-haiku | 17 | 3 | 5.67 |
| 68-doctrine-levels-sonnet | 7 | 4 | 1.75 |
| 69-verify-sonnet | 5 | 3 | 1.67 |
| 70-review-opus | 7 | 5 | 1.40 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 65-runner-sentinels-sonnet | 175 | 130 |
| 66-batch-level-loop-sonnet | 105 | 71 |
| 67-gate-label-and-skip-haiku | 105 | 176 |
| 68-doctrine-levels-sonnet | 131 | 112 |
| 69-verify-sonnet | 53 | 16 |
| 70-review-opus | 36 | 175 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/Users/sahildesai/dev/agentTooling/RUNNER.md` | Read | 65-runner-sentinels-sonnet, 70-review-opus |
| `/Users/sahildesai/dev/agentTooling/plan-runner-lib.sh` | Read | 65-runner-sentinels-sonnet, 69-verify-sonnet, 70-review-opus |
| `/Users/sahildesai/dev/agentTooling/templates/README.md` | Read | 67-gate-label-and-skip-haiku, 70-review-opus |
| `/Users/sahildesai/dev/agentTooling/templates/plans/gate.sh` | Read | 67-gate-label-and-skip-haiku, 69-verify-sonnet |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 69-verify-sonnet | .gitignore, plan-runner-lib.sh, self/features/_scratch-levels/gatetest/gate.sh | — |
| 70-review-opus | AGENT_TOOLING_TESTING_RESTRUCTURE.md, RUNNER.md, plan-runner-lib.sh, self/review-report.md, templates/README.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| plan-runner-lib.sh | 65-runner-sentinels-sonnet | 69-verify-sonnet | 56 |
| plan-runner-lib.sh | 65-runner-sentinels-sonnet | 69-verify-sonnet | 55 |
| plan-runner-lib.sh | 65-runner-sentinels-sonnet | 70-review-opus | 373 |
| RUNNER.md | 65-runner-sentinels-sonnet | 70-review-opus | 258 |
| RUNNER.md | 65-runner-sentinels-sonnet | 70-review-opus | 184 |
| templates/README.md | 67-gate-label-and-skip-haiku | 70-review-opus | 265 |

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
