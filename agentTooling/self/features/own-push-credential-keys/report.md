# own-push-credential-keys — cost and waste report

Generated 2026-11-16T23:58:50.734587+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $9.0005 | 54.3% |
| verify | $0.0000 | 0.0% |
| review | $7.5690 | 45.7% |
| **total** | **$16.5695** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $9.0005, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.8411  
cost per file touched: $1.3808

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 525.0 | $9.0005 | $0.0171 |
| verify | 0.0 | $0.0000 |  |
| review | 18.6 | $7.5690 | $0.4063 |
| **total** | **543.6** | **$16.5695** | $0.0305 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **233.2 min** from 2026-11-16T20:05:36+00:00 to 2026-11-16T23:58:50+00:00, PR opened 2026-11-16T23:58:50+00:00.
Passes: review 43.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 73.8 min over 8 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $9.0005 † | 525.0 † | $0.0000 | 0.0 | $2.2093 | 3.9 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.5174 | 4.9 | 02-review-opus | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.6718 | 3.9 | 03-review-opus | clean | — |
| 4 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.1705 | 5.9 | 04-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

395852 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 9 | 140 | $7.5690 | 18.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 6 | 3 | 2.00 |
| 01-audit-opus | 5 | 4 | 1.25 |
| 02-review-opus | 2 | 2 | 1.00 |
| 02-audit-opus | 3 | 3 | 1.00 |
| 03-review-opus | 1 | 1 | 1.00 |
| 03-audit-opus | 3 | 3 | 1.00 |
| 04-review-opus | 1 | 1 | 1.00 |
| 04-audit-opus | 2 | 2 | 1.00 |
| 04-audit-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 65 | 107 |
| 01-audit-opus | 72 | 377 |
| 02-review-opus | 50 | 70 |
| 02-audit-opus | 72 | 450 |
| 03-review-opus | 49 | 67 |
| 03-audit-opus | 78 | 438 |
| 04-review-opus | 39 | 56 |
| 04-audit-opus | 78 | 416 |
| 04-audit-opus | 78 | 416 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/hooks/allow-repo-commands.sh` | Read | 01-audit-opus, 01-review-opus, 02-audit-opus, 03-audit-opus |
| `/home/user/agentTooling/self/features/own-push-credential-keys/NOTES.md` | Read | 01-review-opus, 03-review-opus |
| `/home/user/agentTooling/self/gate-report.txt` | Read | 01-review-opus, 03-review-opus, 04-review-opus |
| `/home/user/agentTooling/self/tests/hook-cloud-profile.sh` | Read | 01-audit-opus, 01-review-opus, 02-audit-opus, 03-audit-opus, 04-audit-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md, self/tests/README.md, self/tests/hook-cloud-profile.sh | — |
| 01-audit-opus | /tmp/plan-capture.SdyQqi/scratch/attack.py, /tmp/plan-capture.SdyQqi/scratch/emptysub.sh, /tmp/plan-capture.SdyQqi/scratch/extract.sh, self/features/own-push-credential-keys/audit-report.md | — |
| 02-review-opus | self/review-report.md, self/tests/hook-cloud-profile.sh | — |
| 02-audit-opus | /tmp/plan-capture.pEmOGC/scratch/attack.py, /tmp/plan-capture.pEmOGC/scratch/attack2.py, self/features/own-push-credential-keys/audit-report.md | — |
| 03-review-opus | self/review-report.md | — |
| 03-audit-opus | /tmp/plan-capture.Ial4BJ/scratch/audit.py, /tmp/plan-capture.Ial4BJ/scratch/xdg.py, self/features/own-push-credential-keys/audit-report.md | — |
| 04-review-opus | self/review-report.md | — |
| 04-audit-opus | /tmp/plan-capture.ZgHfpD/scratch/audit.py, self/features/own-push-credential-keys/audit-report.md | — |
| 04-audit-opus | /tmp/plan-capture.ZgHfpD/scratch/audit.py, self/features/own-push-credential-keys/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/review-report.md | 01-review-opus | 01-review-opus | 91 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
