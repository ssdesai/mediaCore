# branch-sync-and-fanout-docs — cost and waste report

Generated 2026-11-18T19:18:58.568868+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $3.1689 | 69.3% |
| verify | $0.0000 | 0.0% |
| review | $1.4019 | 30.7% |
| **total** | **$4.5709** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $3.1689, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $2.2854  
cost per file touched: $0.6530

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 49.8 | $3.1689 | $0.0636 |
| verify | 0.0 | $0.0000 |  |
| review | 3.1 | $1.4019 | $0.4513 |
| **total** | **52.9** | **$4.5709** | $0.0863 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **3.6 min** from 2026-11-18T19:15:20+00:00 to 2026-11-18T19:18:58+00:00, PR opened 2026-11-18T19:18:58+00:00.
Passes: review 3.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 4.7 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $3.1689 | 49.8 | $0.0000 | 0.0 | $1.4019 | 3.1 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

96092 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 39 | $1.4019 | 3.1 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 5 | 3 | 1.67 |
| 01-audit-opus | 7 | 4 | 1.75 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 84 | 107 |
| 01-audit-opus | 78 | 196 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/self/tests/feature-sync.sh` | Read | 01-audit-opus, 01-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | LIFECYCLE.md, feature-sync.sh, self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.vnRyG9/scratch/audit.sh, /tmp/plan-capture.vnRyG9/scratch/decision.py, /tmp/plan-capture.vnRyG9/scratch/payload.py, self/features/branch-sync-and-fanout-docs/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.vnRyG9/scratch/audit.sh | 01-audit-opus | 01-audit-opus | 86 |
| /tmp/plan-capture.vnRyG9/scratch/audit.sh | 01-audit-opus | 01-audit-opus | 285 |

---

Rates from `analysis/rates_history.json`, last checked 2026-11-18 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
