# close-after-filing — cost and waste report

Generated 2026-11-17T13:43:08.491414+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $9.3736 | 45.0% |
| verify | $0.0000 | 0.0% |
| review | $11.4454 | 55.0% |
| **total** | **$20.8190** | 100.0% |

1 planning row carried from the capture of 2026-11-17: the capture could not reach its transcript (an earlier round's container, or expired), so the planning figure chains that capture's dollars with this one's.

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $9.3736, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $1.7349  
cost per file touched: $0.7179

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 208.7 | $9.3736 | $0.0449 |
| verify | 0.0 | $0.0000 |  |
| review | 28.0 | $11.4454 | $0.4089 |
| **total** | **236.7** | **$20.8190** | $0.0879 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **596.6 min** from 2026-11-17T03:46:31+00:00 to 2026-11-17T13:43:07+00:00, PR opened 2026-11-17T13:43:07+00:00.
Passes: review 28.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 36.3 min over 12 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $9.3736 † | 208.7 † | $0.0000 | 0.0 | $1.9572 | 4.0 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.0217 | 4.9 | 02-review-opus | escalated | escalations/02-review-opus.md |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.0534 | 5.3 | 03-review-opus | escalated | escalations/03-review-opus.md |
| 4 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.1172 | 5.8 | 04-review-opus | escalated | escalations/04-review-opus.md |
| 5 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.6301 | 4.3 | 05-review-opus | clean | — |
| 6 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.6659 | 3.7 | 06-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

713002 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 12 | 265 | $11.4454 | 28.0 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 01-audit-opus | 2 | 2 | 1.00 |
| 02-review-opus | 2 | 2 | 1.00 |
| 02-audit-opus | 5 | 3 | 1.67 |
| 03-review-opus | 1 | 1 | 1.00 |
| 03-audit-opus | 10 | 6 | 1.67 |
| 04-review-opus | 1 | 1 | 1.00 |
| 04-audit-opus | 14 | 7 | 2.00 |
| 05-review-opus | 1 | 1 | 1.00 |
| 05-audit-opus | 6 | 5 | 1.20 |
| 06-review-opus | 3 | 3 | 1.00 |
| 06-audit-opus | 6 | 6 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 75 | 39 |
| 01-audit-opus | 82 | 229 |
| 02-review-opus | 52 | 87 |
| 02-audit-opus | 82 | 281 |
| 03-review-opus | 50 | 77 |
| 03-audit-opus | 82 | 334 |
| 04-review-opus | 45 | 76 |
| 04-audit-opus | 82 | 371 |
| 05-review-opus | 45 | 58 |
| 05-audit-opus | 82 | 288 |
| 06-review-opus | 56 | 78 |
| 06-audit-opus | 82 | 206 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/gate.sh, self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.5H4E5u/scratch/attack.sh, self/features/close-after-filing/audit-report.md | — |
| 02-review-opus | self/features/close-after-filing/NOTES.md, self/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.10p3zO/scratch/attack.sh, /tmp/plan-capture.10p3zO/scratch/headfix/feature-close.sh, self/features/close-after-filing/audit-report.md | — |
| 03-review-opus | self/review-report.md | — |
| 03-audit-opus | /tmp/plan-capture.f7pYJw/scratch/attack.sh, /tmp/plan-capture.f7pYJw/scratch/attack2.sh, /tmp/plan-capture.f7pYJw/scratch/mkfix.sh, /tmp/plan-capture.f7pYJw/scratch/pushcheck.sh, /tmp/plan-capture.f7pYJw/scratch/setup.sh, self/features/close-after-filing/audit-report.md | — |
| 04-review-opus | self/review-report.md | — |
| 04-audit-opus | /tmp/plan-capture.IZa4DY/scratch/attack.sh, /tmp/plan-capture.IZa4DY/scratch/cgpatch.py, /tmp/plan-capture.IZa4DY/scratch/mkfix.sh, /tmp/plan-capture.IZa4DY/scratch/patch.py, /tmp/plan-capture.IZa4DY/scratch/pushcheck.sh, /tmp/plan-capture.IZa4DY/scratch/setup.sh, self/features/close-after-filing/audit-report.md | — |
| 05-review-opus | self/review-report.md | — |
| 05-audit-opus | /tmp/plan-capture.ZEIf8u/scratch/attack.sh, /tmp/plan-capture.ZEIf8u/scratch/forge_graph.py, /tmp/plan-capture.ZEIf8u/scratch/mk.sh, /tmp/plan-capture.ZEIf8u/scratch/stub-claude, self/features/close-after-filing/audit-report.md | — |
| 06-review-opus | /tmp/plan-capture.Mgkmyl/scratch/cmp.sh, README.md, self/review-report.md | — |
| 06-audit-opus | /tmp/plan-capture.QcdDqq/scratch/patch.py, /tmp/plan-capture.QcdDqq/scratch/patch2.py, /tmp/plan-capture.QcdDqq/scratch/run.sh, /tmp/plan-capture.QcdDqq/scratch/run2.sh, /tmp/plan-capture.QcdDqq/scratch/run3.sh, self/features/close-after-filing/audit-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
