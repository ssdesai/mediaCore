# own-push-real-gitdir — cost and waste report

Generated 2026-11-16T17:02:52.429270+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $11.7365 | 68.4% |
| verify | $0.0000 | 0.0% |
| review | $5.4134 | 31.6% |
| **total** | **$17.1499** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $11.7365, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.2875  
cost per file touched: $1.4292

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 301.0 | $11.7365 | $0.0390 |
| verify | 0.0 | $0.0000 |  |
| review | 16.9 | $5.4134 | $0.3208 |
| **total** | **317.9** | **$17.1499** | $0.0539 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **97.4 min** from 2026-11-16T15:24:56+00:00 to 2026-11-16T17:02:20+00:00, PR opened 2026-11-16T17:02:20+00:00.
Passes: review 17.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 20.6 min over 4 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $11.7365 † | 301.0 † | $0.0000 | 0.0 | $2.6839 | 8.1 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.7295 | 8.7 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

302119 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 4 | 95 | $5.4134 | 16.9 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 4 | 3 | 1.33 |
| 01-audit-opus | 3 | 3 | 1.00 |
| 02-review-opus | 3 | 3 | 1.00 |
| 02-audit-opus | 9 | 6 | 1.50 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 73 | 103 |
| 01-audit-opus | 39 | 697 |
| 02-review-opus | 54 | 52 |
| 02-audit-opus | 39 | 847 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/hooks/README.md` | Read | 01-review-opus, 02-review-opus |
| `/home/user/agentTooling/hooks/allow-repo-commands.sh` | Read | 01-audit-opus, 01-review-opus, 02-audit-opus, 02-review-opus |
| `/home/user/agentTooling/self/tests/hook-cloud-profile.sh` | Read | 01-audit-opus, 02-audit-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | hooks/allow-repo-commands.sh, self/review-report.md, self/tests/hook-cloud-profile.sh | — |
| 01-audit-opus | /tmp/plan-capture.DziU99/scratch/audit.py, /tmp/plan-capture.DziU99/scratch/verify.py, self/features/own-push-real-gitdir/audit-report.md | — |
| 02-review-opus | hooks/README.md, hooks/allow-repo-commands.sh, self/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.raG3G4/scratch/attack.py, /tmp/plan-capture.raG3G4/scratch/extract.sh, /tmp/plan-capture.raG3G4/scratch/legacy_remotes.sh, /tmp/plan-capture.raG3G4/scratch/origin_dir.sh, /tmp/plan-capture.raG3G4/scratch/table.py, self/features/own-push-real-gitdir/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.raG3G4/scratch/attack.py | 02-audit-opus | 02-audit-opus | 142 |
| /tmp/plan-capture.raG3G4/scratch/attack.py | 02-audit-opus | 02-audit-opus | 353 |
| /tmp/plan-capture.raG3G4/scratch/attack.py | 02-audit-opus | 02-audit-opus | 74 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
