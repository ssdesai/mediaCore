# orchestration-start-branch-v2 — cost and waste report

Generated 2026-11-19T16:53:58.094410+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $21.9297 | 64.5% |
| verify | $0.0000 | 0.0% |
| review | $12.0535 | 35.5% |
| **total** | **$33.9832** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $21.9297, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.2479  
cost per file touched: $0.8943

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 1344.8 | $21.9297 | $0.0163 |
| verify | 0.0 | $0.0000 |  |
| review | 45.8 | $12.0535 | $0.2630 |
| **total** | **1390.6** | **$33.9832** | $0.0244 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **798.9 min** from 2026-11-19T03:35:01+00:00 to 2026-11-19T16:53:57+00:00, PR opened 2026-11-19T16:53:57+00:00.
Passes: review 51.8. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 58.5 min over 8 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $21.9297 † | 1344.8 † | $0.0000 | 0.0 | $3.5791 | 10.7 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.6352 | 14.4 | 02-review-opus | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.6045 | 8.7 | 03-review-opus | clean | — |
| 4 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $3.2347 | 12.1 | 04-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

730714 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 8 | 218 | $12.0535 | 45.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 4 | 3 | 1.33 |
| 01-audit-opus | 13 | 11 | 1.18 |
| 02-review-opus | 2 | 2 | 1.00 |
| 02-audit-opus | 9 | 7 | 1.29 |
| 03-review-opus | 2 | 2 | 1.00 |
| 03-audit-opus | 10 | 9 | 1.11 |
| 04-review-opus | 2 | 2 | 1.00 |
| 04-audit-opus | 12 | 11 | 1.09 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 80 | 112 |
| 01-audit-opus | 80 | 494 |
| 02-review-opus | 53 | 85 |
| 02-audit-opus | 81 | 503 |
| 03-review-opus | 35 | 83 |
| 03-audit-opus | 82 | 549 |
| 04-review-opus | 43 | 89 |
| 04-audit-opus | 82 | 885 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/self/features/orchestration-start-branch-v2/audit-report.md` | Read | 02-audit-opus, 03-audit-opus, 04-audit-opus, 04-review-opus |
| `/home/user/agentTooling/self/gate-report.txt` | Read | 01-review-opus, 03-review-opus, 04-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | /tmp/plan-capture.xfrFEG/scratch/gitmv.sh, self/BACKLOG.md, self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.ykpPzB/scratch/cases1.json, /tmp/plan-capture.ykpPzB/scratch/cases2.json, /tmp/plan-capture.ykpPzB/scratch/cases3.json, /tmp/plan-capture.ykpPzB/scratch/hook.py, /tmp/plan-capture.ykpPzB/scratch/m59.sh, /tmp/plan-capture.ykpPzB/scratch/m59b.sh, /tmp/plan-capture.ykpPzB/scratch/setup.sh, /tmp/plan-capture.ykpPzB/scratch/start-all.sh, /tmp/plan-capture.ykpPzB/scratch/start.sh, /tmp/plan-capture.ykpPzB/scratch/start2.sh, self/features/orchestration-start-branch-v2/audit-report.md | — |
| 02-review-opus | self/BACKLOG.md, self/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.arUdwf/scratch/build.sh, /tmp/plan-capture.arUdwf/scratch/cases1.json, /tmp/plan-capture.arUdwf/scratch/cases2.json, /tmp/plan-capture.arUdwf/scratch/hook.py, /tmp/plan-capture.arUdwf/scratch/start-all.sh, /tmp/plan-capture.arUdwf/scratch/start.sh, self/features/orchestration-start-branch-v2/audit-report.md | — |
| 03-review-opus | self/BACKLOG.md, self/review-report.md | — |
| 03-audit-opus | /tmp/plan-capture.yW0Uiq/scratch/build.sh, /tmp/plan-capture.yW0Uiq/scratch/cases.json, /tmp/plan-capture.yW0Uiq/scratch/cases2.json, /tmp/plan-capture.yW0Uiq/scratch/hook.py, /tmp/plan-capture.yW0Uiq/scratch/shadow.sh, /tmp/plan-capture.yW0Uiq/scratch/start-all.sh, /tmp/plan-capture.yW0Uiq/scratch/start-more.sh, /tmp/plan-capture.yW0Uiq/scratch/start.sh, self/features/orchestration-start-branch-v2/audit-report.md | — |
| 04-review-opus | self/BACKLOG.md, self/review-report.md | — |
| 04-audit-opus | /tmp/plan-capture.Fiyg7f/scratch/build.sh, /tmp/plan-capture.Fiyg7f/scratch/hook.py, /tmp/plan-capture.Fiyg7f/scratch/hook2.py, /tmp/plan-capture.Fiyg7f/scratch/push-all.sh, /tmp/plan-capture.Fiyg7f/scratch/push.sh, /tmp/plan-capture.Fiyg7f/scratch/realmove.sh, /tmp/plan-capture.Fiyg7f/scratch/start-all.sh, /tmp/plan-capture.Fiyg7f/scratch/start.sh, /tmp/plan-capture.Fiyg7f/scratch/vendored-all.sh, /tmp/plan-capture.Fiyg7f/scratch/vendored.sh, self/features/orchestration-start-branch-v2/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/review-report.md | 01-review-opus | 01-review-opus | 91 |
| /tmp/plan-capture.ykpPzB/scratch/cases1.json | 01-audit-opus | 01-audit-opus | 115 |
| /tmp/plan-capture.ykpPzB/scratch/cases2.json | 01-audit-opus | 01-audit-opus | 144 |
| /tmp/plan-capture.arUdwf/scratch/cases1.json | 02-audit-opus | 02-audit-opus | 87 |
| /tmp/plan-capture.arUdwf/scratch/start.sh | 02-audit-opus | 02-audit-opus | 65 |
| self/BACKLOG.md | 02-review-opus | 03-review-opus | 119 |
| /tmp/plan-capture.yW0Uiq/scratch/hook.py | 03-audit-opus | 03-audit-opus | 106 |
| self/BACKLOG.md | 01-review-opus | 04-review-opus | 493 |
| self/features/orchestration-start-branch-v2/audit-report.md | 04-audit-opus | 04-audit-opus | 49 |

---

Rates from `analysis/rates_history.json`, last checked 2026-11-18 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
