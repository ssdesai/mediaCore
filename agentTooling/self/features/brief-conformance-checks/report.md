# brief-conformance-checks — cost and waste report

Generated 2026-11-19T13:14:11.443617+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $18.7162 | 66.9% |
| verify | $0.0000 | 0.0% |
| review | $9.2569 | 33.1% |
| **total** | **$27.9731** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $18.7162, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.6622  
cost per file touched: $1.2715

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 622.1 | $18.7162 | $0.0301 |
| verify | 0.0 | $0.0000 |  |
| review | 22.0 | $9.2569 | $0.4212 |
| **total** | **644.1** | **$27.9731** | $0.0434 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **496.7 min** from 2026-11-19T04:57:28+00:00 to 2026-11-19T13:14:10+00:00, PR opened 2026-11-19T13:14:10+00:00.
Passes: review 25.3. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 30.9 min over 6 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $18.7162 † | 622.1 † | $0.0000 | 0.0 | $4.4928 | 12.8 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.9325 | 7.4 | 02-review-opus | escalated | escalations/02-review-opus.md |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.8316 | 1.7 | 03-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

464980 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 6 | 149 | $9.2569 | 22.0 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 01-audit-opus | 13 | 11 | 1.18 |
| 02-review-opus | 3 | 2 | 1.50 |
| 02-audit-opus | 7 | 6 | 1.17 |
| 03-review-opus | 1 | 1 | 1.00 |
| 03-audit-opus | 5 | 5 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 97 | 93 |
| 01-audit-opus | 84 | 581 |
| 02-review-opus | 51 | 74 |
| 02-audit-opus | 84 | 480 |
| 03-review-opus | 42 | 45 |
| 03-audit-opus | 84 | 315 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/conformance.py` | Read | 01-audit-opus, 01-review-opus |
| `/home/user/agentTooling/self/features/brief-conformance-checks/audit-report.md` | Read | 02-audit-opus, 03-audit-opus |
| `/home/user/agentTooling/self/tests/brief-conformance.sh` | Read | 01-review-opus, 02-audit-opus, 03-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.WJVVuQ/scratch/conf.py, /tmp/plan-capture.WJVVuQ/scratch/envfunc.sh, /tmp/plan-capture.WJVVuQ/scratch/hookone.sh, /tmp/plan-capture.WJVVuQ/scratch/hookpy.sh, /tmp/plan-capture.WJVVuQ/scratch/hookrun.py, /tmp/plan-capture.WJVVuQ/scratch/roots.sh, /tmp/plan-capture.WJVVuQ/scratch/selftest.sh, /tmp/plan-capture.WJVVuQ/scratch/setup.sh, /tmp/plan-capture.WJVVuQ/scratch/stray.sh, /tmp/plan-capture.WJVVuQ/scratch/stub-claude, self/features/brief-conformance-checks/audit-report.md | — |
| 02-review-opus | conformance.py, self/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.86antU/scratch/attack.sh, /tmp/plan-capture.86antU/scratch/close.sh, /tmp/plan-capture.86antU/scratch/conf.sh, /tmp/plan-capture.86antU/scratch/extract.sh, /tmp/plan-capture.86antU/scratch/hook.py, self/features/brief-conformance-checks/audit-report.md | — |
| 03-review-opus | self/review-report.md | — |
| 03-audit-opus | /tmp/plan-capture.0SLVsA/scratch/all.sh, /tmp/plan-capture.0SLVsA/scratch/attack.sh, /tmp/plan-capture.0SLVsA/scratch/conf.sh, /tmp/plan-capture.0SLVsA/scratch/hook.py, self/features/brief-conformance-checks/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.WJVVuQ/scratch/hookrun.py | 01-audit-opus | 01-audit-opus | 74 |

---

Rates from `analysis/rates_history.json`, last checked 2026-11-18 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
