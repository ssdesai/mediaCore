# harness-ablation-methods — cost and waste report

Generated 2026-11-05T17:18:52.545255+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $18.1084 | 90.6% |
| verify | $0.0000 | 0.0% |
| review | $1.8778 | 9.4% |
| **total** | **$19.9861** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $18.1084, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $19.9861  
cost per file touched: $3.3310

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 33.3 | $18.1084 | $0.5443 |
| verify | 0.0 | $0.0000 |  |
| review | 3.2 | $1.8778 | $0.5897 |
| **total** | **36.5** | **$19.9861** | $0.5483 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **3.4 min** from 2026-11-05T17:15:15+00:00 to 2026-11-05T17:18:41+00:00, PR opened 2026-11-05T17:18:41+00:00.
Passes: review 3.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.2 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $18.1084 | 33.3 | $0.0000 | 0.0 | $1.8778 | 3.2 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

116804 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 41 | $1.8778 | 3.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 11 | 6 | 1.83 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 82 | 103 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | harness/scorecard.py, harness/tests/README.md, harness/tests/scorecard-accept.sh, self/review-report.md, self/tests/README.md, self/tests/vanilla-pair.sh | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/tests/vanilla-pair.sh | 01-review-opus | 01-review-opus | 133 |
| self/tests/vanilla-pair.sh | 01-review-opus | 01-review-opus | 182 |
| self/tests/README.md | 01-review-opus | 01-review-opus | 68 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
