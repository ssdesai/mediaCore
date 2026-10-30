# policy-module — cost and waste report

Generated 2026-09-18T11:59:13.993736+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $24.4682 | 79.5% |
| verify | $0.0000 | 0.0% |
| review | $6.3166 | 20.5% |
| **total** | **$30.7848** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $24.4682, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $10.2616  
cost per file touched: $5.1308

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 442.2 | $24.4682 | $0.0553 |
| ↳ implementation | 6.0 |  |  |
| ↳ gate | 4.7 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 14.5 | $6.3166 | $0.4343 |
| **total** | **456.7** | **$30.7848** | $0.0674 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **47.0 min** from 2026-09-18T11:12:10+00:00 to 2026-09-18T11:59:12+00:00, PR opened 2026-09-18T11:59:12+00:00.
Passes: review 14.7. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 14.7 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $24.4682 † | 442.2 † | $0.0000 | 0.0 | $4.3139 | 4.7 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.6881 | 8.7 | 02-review-sonnet | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.3146 | 1.2 | 03-review-sonnet | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and its `checkpoint` stamps span rounds 1, 2 — one figure cannot be divided between them, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

301844 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 44 | $4.3139 | 4.7 |  |
| sonnet | 2 | 81 | $2.0027 | 9.9 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 3 | 1.00 |
| 02-review-sonnet | 8 | 5 | 1.60 |
| 03-review-sonnet | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 111 | 137 |
| 02-review-sonnet | 70 | 197 |
| 03-review-sonnet | 48 | 51 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/Users/sahildesai/dev/agentTooling/.worktrees/policy-module/hooks/allow-repo-commands.sh` | Read | 01-review-opus, 02-review-sonnet |
| `/Users/sahildesai/dev/agentTooling/.worktrees/policy-module/self/tests/policy-table.sh` | Read | 01-review-opus, 02-review-sonnet |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/features/policy-module/NOTES.md, self/review-report.md, self/tests/allow-repo-commands.sh | — |
| 02-review-sonnet | /var/folders/w1/sjvnhgn11ml_fj_s_kch9xv40000gn/T/plan-capture.NX6sGj/scratch/check_old.py, self/features/policy-module/NOTES.md, self/review-report.md, self/tests/README.md, self/tests/hook-escalation.sh | — |
| 03-review-sonnet | self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /var/folders/w1/sjvnhgn11ml_fj_s_kch9xv40000gn/T/plan-capture.NX6sGj/scratch/check_old.py | 02-review-sonnet | 02-review-sonnet | 99 |

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
