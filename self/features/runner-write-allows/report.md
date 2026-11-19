# runner-write-allows — cost and waste report

Generated 2026-11-16T20:22:01.624901+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $8.6253 | 56.0% |
| verify | $0.0000 | 0.0% |
| review | $6.7754 | 44.0% |
| **total** | **$15.4007** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $8.6253, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $3.8502  
cost per file touched: $0.6160

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 355.4 | $8.6253 | $0.0243 |
| verify | 0.0 | $0.0000 |  |
| review | 25.7 | $6.7754 | $0.2633 |
| **total** | **381.1** | **$15.4007** | $0.0404 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **130.3 min** from 2026-11-16T18:11:40+00:00 to 2026-11-16T20:22:00+00:00, PR opened 2026-11-16T20:22:00+00:00.
Passes: review 25.9. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 30.0 min over 4 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $8.6253 † | 355.4 † | $0.0000 | 0.0 | $3.2882 | 12.5 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $3.4872 | 13.2 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

350460 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 4 | 132 | $6.7754 | 25.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 01-audit-opus | 13 | 10 | 1.30 |
| 02-review-opus | 2 | 2 | 1.00 |
| 02-audit-opus | 18 | 13 | 1.38 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 87 | 106 |
| 01-audit-opus | 72 | 779 |
| 02-review-opus | 45 | 54 |
| 02-audit-opus | 72 | 1109 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/analysis/roots.py` | Read | 01-review-opus, 02-audit-opus |
| `/home/user/agentTooling/hooks/allow-repo-commands.sh` | Read | 01-audit-opus, 01-review-opus, 02-audit-opus, 02-review-opus |
| `/home/user/agentTooling/self/tests/allow-repo-commands.sh` | Read | 01-audit-opus, 02-audit-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | /tmp/plan-capture.rFiQwX/scratch/spot.sh, self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.hcvIw1/scratch/attack.py, /tmp/plan-capture.hcvIw1/scratch/cases.txt, /tmp/plan-capture.hcvIw1/scratch/cases2.txt, /tmp/plan-capture.hcvIw1/scratch/malformed.py, /tmp/plan-capture.hcvIw1/scratch/mypyw.sh, /tmp/plan-capture.hcvIw1/scratch/setup.sh, /tmp/plan-capture.hcvIw1/scratch/tools.sh, /tmp/plan-capture.hcvIw1/scratch/wdemo.sh, /tmp/plan-capture.hcvIw1/scratch/words.py, self/features/runner-write-allows/audit-report.md | — |
| 02-review-opus | self/BACKLOG.md, self/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.JJksds/scratch/attack.py, /tmp/plan-capture.JJksds/scratch/cases1.txt, /tmp/plan-capture.JJksds/scratch/cases2.txt, /tmp/plan-capture.JJksds/scratch/cases3.txt, /tmp/plan-capture.JJksds/scratch/cases4.txt, /tmp/plan-capture.JJksds/scratch/flags.py, /tmp/plan-capture.JJksds/scratch/glob.sh, /tmp/plan-capture.JJksds/scratch/globreal.sh, /tmp/plan-capture.JJksds/scratch/malformed.py, /tmp/plan-capture.JJksds/scratch/real.sh, /tmp/plan-capture.JJksds/scratch/setup.sh, /tmp/plan-capture.JJksds/scratch/table.py, self/features/runner-write-allows/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/features/runner-write-allows/audit-report.md | 01-audit-opus | 01-audit-opus | 110 |
| self/features/runner-write-allows/audit-report.md | 01-audit-opus | 01-audit-opus | 84 |
| /tmp/plan-capture.JJksds/scratch/attack.py | 02-audit-opus | 02-audit-opus | 73 |
| /tmp/plan-capture.JJksds/scratch/cases3.txt | 02-audit-opus | 02-audit-opus | 112 |
| /tmp/plan-capture.JJksds/scratch/cases3.txt | 02-audit-opus | 02-audit-opus | 63 |
| /tmp/plan-capture.JJksds/scratch/cases3.txt | 02-audit-opus | 02-audit-opus | 50 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
