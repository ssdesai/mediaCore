# python-entry-exact — cost and waste report

Generated 2026-11-16T08:48:52.072992+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $21.2598 | 82.9% |
| verify | $0.0000 | 0.0% |
| review | $4.3971 | 17.1% |
| **total** | **$25.6569** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $21.2598, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $6.4142  
cost per file touched: $1.6036

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 88.3 | $21.2598 | $0.2407 |
| verify | 0.0 | $0.0000 |  |
| review | 11.3 | $4.3971 | $0.3908 |
| **total** | **99.6** | **$25.6569** | $0.2577 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **32.7 min** from 2026-11-16T08:16:07+00:00 to 2026-11-16T08:48:50+00:00, PR opened 2026-11-16T08:48:50+00:00.
Passes: review 11.4. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 14.2 min over 4 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $21.2598 † | 88.3 † | $0.0000 | 0.0 | $2.6492 | 6.0 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.7478 | 5.2 | 02-review-sonnet | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

275620 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 93 | $4.1696 | 10.6 |  |
| sonnet | 1 | 11 | $0.2274 | 0.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 01-audit-opus | 7 | 5 | 1.40 |
| 02-review-sonnet | 4 | 4 | 1.00 |
| 02-audit-opus | 11 | 7 | 1.57 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 62 | 102 |
| 01-audit-opus | 43 | 391 |
| 02-review-sonnet | 46 | 33 |
| 02-audit-opus | 43 | 545 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling-delegate-cost-claims/analysis/capture_planning.py` | Read | 01-audit-opus, 02-audit-opus |
| `/home/user/agentTooling-delegate-cost-claims/self/features/python-entry-exact/audit-report.md` | Read | 01-review-opus, 02-audit-opus |
| `/home/user/agentTooling-delegate-cost-claims/self/tests/hook-orchestrator-role.sh` | Read | 01-audit-opus, 01-review-opus, 02-audit-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | hooks/README.md, self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.BFNYe6/scratch/argv.sh, /tmp/plan-capture.BFNYe6/scratch/audit.py, /tmp/plan-capture.BFNYe6/scratch/orch.txt, /tmp/plan-capture.BFNYe6/scratch/plain.txt, self/features/python-entry-exact/audit-report.md | — |
| 02-review-sonnet | self/features/python-entry-exact/NOTES.md, self/review-report.md, self/tests/README.md, self/tests/manifest-window.sh | — |
| 02-audit-opus | /tmp/plan-capture.7lkXF2/scratch/attack.py, /tmp/plan-capture.7lkXF2/scratch/cases.txt, /tmp/plan-capture.7lkXF2/scratch/payloads.py, /tmp/plan-capture.7lkXF2/scratch/runtime.sh, /tmp/plan-capture.7lkXF2/scratch/setup.sh, /tmp/plan-capture.7lkXF2/scratch/trusted.sh, self/features/python-entry-exact/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.7lkXF2/scratch/cases.txt | 02-audit-opus | 02-audit-opus | 47 |
| /tmp/plan-capture.7lkXF2/scratch/cases.txt | 02-audit-opus | 02-audit-opus | 48 |
| /tmp/plan-capture.7lkXF2/scratch/cases.txt | 02-audit-opus | 02-audit-opus | 51 |
| /tmp/plan-capture.7lkXF2/scratch/attack.py | 02-audit-opus | 02-audit-opus | 65 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
