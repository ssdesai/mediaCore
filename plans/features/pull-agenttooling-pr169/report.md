# pull-agenttooling-pr169 — cost and waste report

Generated 2026-11-19T18:54:16.886254+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $0.8835 | 13.2% |
| verify | $0.0000 | 0.0% |
| review | $5.8022 | 86.8% |
| **total** | **$6.6857** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $0.8835, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.6714  
cost per file touched: $0.3184

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 67.9 | $0.8835 | $0.0130 |
| verify | 0.0 | $0.0000 |  |
| review | 17.0 | $5.8022 | $0.3411 |
| **total** | **84.9** | **$6.6857** | $0.0787 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **18.1 min** from 2026-11-19T18:36:11+00:00 to 2026-11-19T18:54:15+00:00, PR opened 2026-11-19T18:54:15+00:00.
Passes: review 17.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 18.7 min over 4 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $0.8835 † | 67.9 † | $0.0000 | 0.0 | $4.1833 | 12.3 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.6189 | 4.7 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

312992 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 4 | 128 | $5.8022 | 17.0 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 01-audit-opus | 18 | 16 | 1.12 |
| 02-review-opus | 2 | 2 | 1.00 |
| 02-audit-opus | 6 | 4 | 1.50 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 40 | 59 |
| 01-audit-opus | 106 | 1415 |
| 02-review-opus | 45 | 58 |
| 02-audit-opus | 106 | 505 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/mediaCore/plans/features/pull-agenttooling-pr169/README.md` | Read | 01-review-opus, 02-review-opus |
| `/home/user/mediaCore/plans/gate-report.txt` | Read | 01-review-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | plans/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.LEhgRP/scratch/altref.sh, /tmp/plan-capture.LEhgRP/scratch/cases1.py, /tmp/plan-capture.LEhgRP/scratch/cases2.py, /tmp/plan-capture.LEhgRP/scratch/cases3.py, /tmp/plan-capture.LEhgRP/scratch/cases4.py, /tmp/plan-capture.LEhgRP/scratch/cases5.py, /tmp/plan-capture.LEhgRP/scratch/cases6.py, /tmp/plan-capture.LEhgRP/scratch/check_report.sh, /tmp/plan-capture.LEhgRP/scratch/gen.py, /tmp/plan-capture.LEhgRP/scratch/harness.py, /tmp/plan-capture.LEhgRP/scratch/lists.py, /tmp/plan-capture.LEhgRP/scratch/parse_test.sh, /tmp/plan-capture.LEhgRP/scratch/remote.sh, /tmp/plan-capture.LEhgRP/scratch/setup.sh, /tmp/plan-capture.LEhgRP/scratch/verify1.sh, plans/features/pull-agenttooling-pr169/audit-report.md | — |
| 02-review-opus | plans/features/pull-agenttooling-pr169/README.md, plans/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.EY97PH/scratch/harness.py, /tmp/plan-capture.EY97PH/scratch/one.py, /tmp/plan-capture.EY97PH/scratch/setup.sh, plans/features/pull-agenttooling-pr169/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.LEhgRP/scratch/cases2.py | 01-audit-opus | 01-audit-opus | 101 |
| /tmp/plan-capture.LEhgRP/scratch/cases2.py | 01-audit-opus | 01-audit-opus | 115 |
| /tmp/plan-capture.EY97PH/scratch/harness.py | 02-audit-opus | 02-audit-opus | 48 |

---

Rates from `analysis/rates_history.json`, last checked 2026-11-18 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
