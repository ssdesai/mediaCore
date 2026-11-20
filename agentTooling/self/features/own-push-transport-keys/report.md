# own-push-transport-keys — cost and waste report

Generated 2026-11-20T14:54:22.537265+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $3.7872 | 62.0% |
| verify | $0.0000 | 0.0% |
| review | $2.3220 | 38.0% |
| **total** | **$6.1092** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $3.7872, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $2.0364  
cost per file touched: $1.0182

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 106.8 | $3.7872 | $0.0354 |
| verify | 0.0 | $0.0000 |  |
| review | 2.2 | $2.3220 | $1.0734 |
| **total** | **109.0** | **$6.1092** | $0.0560 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **10.9 min** from 2026-11-20T14:43:26+00:00 to 2026-11-20T14:54:21+00:00, PR opened 2026-11-20T14:54:21+00:00.
Passes: review 10.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 11.9 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $3.7872 | 106.8 | $0.0000 | 0.0 | $2.3220 | 2.2 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

74146 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 17 | $2.3220 | 2.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 01-audit-opus | 6 | 5 | 1.20 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 59 | 66 |
| 01-audit-opus | 79 | 368 |
| 01-conformance-opus | 3 | 0 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/hooks/allow-repo-commands.sh` | Read | 01-audit-opus, 01-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.qif19R/scratch/cfg_attack.py, /tmp/plan-capture.qif19R/scratch/insert.py, /tmp/plan-capture.qif19R/scratch/orch_block.txt, /tmp/plan-capture.qif19R/scratch/setup.sh, self/features/own-push-transport-keys/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/features/own-push-transport-keys/audit-report.md | 01-audit-opus | 01-audit-opus | 117 |

## Warnings

- plan 01-conformance-opus has 0 files_edited; excluded from churn ratio

---

Rates from `analysis/rates_history.json`, last checked 2026-11-18 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
