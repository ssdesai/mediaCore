# orchestration-records-in-repo — cost and waste report

Generated 2026-11-13T02:36:48.448578+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $23.0275 | 82.7% |
| verify | $0.0000 | 0.0% |
| review | $4.8008 | 17.3% |
| **total** | **$27.8283** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $23.0275, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $6.9571  
cost per file touched: $3.9755

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 2626.3 | $23.0275 | $0.0088 |
| verify | 0.0 | $0.0000 |  |
| review | 9.8 | $4.8008 | $0.4886 |
| **total** | **2636.1** | **$27.8283** | $0.0106 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **609.5 min** from 2026-11-12T16:27:18+00:00 to 2026-11-13T02:36:47+00:00, PR opened 2026-11-13T02:36:47+00:00.
Passes: review 10.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 11.3 min over 4 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $23.0275 | 2626.3 | $0.0000 | 0.0 | $1.4209 | 1.9 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 | 0.0 | $0.0000 | 0.0 | $1.0993 | 2.1 | 02-review-opus | clean | — |
| 3 | $0.0000 | 0.0 | $0.0000 | 0.0 | $2.2806 | 5.8 | 03-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

307417 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 4 | 98 | $4.8008 | 9.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 02-review-opus | 6 | 4 | 1.50 |
| 03-review-opus | 1 | 1 | 1.00 |
| 03-audit-opus | 5 | 3 | 1.67 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 64 | 58 |
| 02-review-opus | 50 | 107 |
| 03-review-opus | 37 | 54 |
| 03-audit-opus | 51 | 421 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/self/gate-report.txt` | Read | 01-review-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 02-review-opus | analysis/README.md, analysis/roots.py, orchestration-start.sh, self/review-report.md | — |
| 03-review-opus | self/review-report.md | — |
| 03-audit-opus | /tmp/plan-capture.nNNFCJ/scratch/audit.py, /tmp/plan-capture.nNNFCJ/scratch/audit2.py, self/features/orchestration-records-in-repo/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| orchestration-start.sh | 02-review-opus | 02-review-opus | 57 |
| /tmp/plan-capture.nNNFCJ/scratch/audit.py | 03-audit-opus | 03-audit-opus | 65 |
| self/features/orchestration-records-in-repo/audit-report.md | 03-audit-opus | 03-audit-opus | 184 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
