# pull-agenttooling-pr173 — cost and waste report

Generated 2026-11-21T03:37:05.086764+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $0.0000 | 0.0% |
| verify | $0.0000 | 0.0% |
| review | $7.8217 | 100.0% |
| **total** | **$7.8217** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $0.0000, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.3036  
cost per file touched: $0.5587

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 0.0 | $0.0000 |  |
| verify | 0.0 | $0.0000 |  |
| review | 17.0 | $7.8217 | $0.4609 |
| **total** | **17.0** | **$7.8217** | $0.4609 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **658.2 min** from 2026-11-20T15:35:43+00:00 to 2026-11-21T02:33:55+00:00.
Passes: review 23.7. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 26.5 min over 6 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.3188 | 7.1 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.2467 | 8.4 | 02-review-opus | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $3.2563 | 1.4 | 03-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

329552 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 6 | 117 | $7.8217 | 17.0 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 01-audit-opus | 7 | 3 | 2.33 |
| 02-review-opus | 3 | 2 | 1.50 |
| 02-audit-opus | 6 | 6 | 1.00 |
| 03-review-opus | 2 | 2 | 1.00 |
| 03-audit-opus | 10 | 5 | 2.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 40 | 69 |
| 01-audit-opus | 82 | 821 |
| 02-review-opus | 44 | 98 |
| 02-audit-opus | 82 | 733 |
| 03-review-opus | 41 | 92 |
| 03-audit-opus | 83 | 688 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/mediaCore/agentTooling/hooks/allow-repo-commands.sh` | Read | 01-audit-opus, 02-audit-opus, 03-audit-opus |
| `/home/user/mediaCore/plans/features/pull-agenttooling-pr173/README.md` | Read | 01-review-opus, 02-review-opus, 03-review-opus |
| `/home/user/mediaCore/plans/gate-report.txt` | Read | 01-review-opus, 02-review-opus, 03-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | plans/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.BSus1H/scratch/attack.py, /tmp/plan-capture.BSus1H/scratch/setup.sh, plans/features/pull-agenttooling-pr173/audit-report.md | — |
| 02-review-opus | plans/features/pull-agenttooling-pr173/README.md, plans/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.ixuKVT/scratch/attack2.py, /tmp/plan-capture.ixuKVT/scratch/attack_hook_empty.py, /tmp/plan-capture.ixuKVT/scratch/attack_move.py, /tmp/plan-capture.ixuKVT/scratch/attack_start.py, /tmp/plan-capture.ixuKVT/scratch/setup.sh, plans/features/pull-agenttooling-pr173/audit-report.md | — |
| 03-review-opus | plans/features/pull-agenttooling-pr173/README.md, plans/review-report.md | — |
| 03-audit-opus | /tmp/plan-capture.rXBQCL/scratch/move_attack.py, /tmp/plan-capture.rXBQCL/scratch/push_attack.py, /tmp/plan-capture.rXBQCL/scratch/setup.sh, /tmp/plan-capture.rXBQCL/scratch/start_attack.sh, plans/features/pull-agenttooling-pr173/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.BSus1H/scratch/attack.py | 01-audit-opus | 01-audit-opus | 122 |
| /tmp/plan-capture.BSus1H/scratch/attack.py | 01-audit-opus | 01-audit-opus | 57 |
| /tmp/plan-capture.BSus1H/scratch/attack.py | 01-audit-opus | 01-audit-opus | 53 |
| plans/features/pull-agenttooling-pr173/README.md | 02-review-opus | 03-review-opus | 541 |
| /tmp/plan-capture.rXBQCL/scratch/move_attack.py | 03-audit-opus | 03-audit-opus | 169 |
| plans/features/pull-agenttooling-pr173/audit-report.md | 03-audit-opus | 03-audit-opus | 113 |
| plans/features/pull-agenttooling-pr173/audit-report.md | 03-audit-opus | 03-audit-opus | 98 |

---

Rates from `analysis/rates_history.json`, last checked 2026-11-18 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
