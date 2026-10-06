# lifecycle-records-and-numbering — cost and waste report

Generated 2026-09-18T04:14:40.374594+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $42.5163 | 91.1% |
| verify | $0.0000 | 0.0% |
| review | $4.1738 | 8.9% |
| **total** | **$46.6901** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $42.5163, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $23.3451  
cost per file touched: $11.6725

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 280.0 | $42.5163 | $0.1518 |
| ↳ acceptance tests | 6.9 |  |  |
| ↳ implementation | 11.7 |  |  |
| ↳ gate | 18.7 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 10.5 | $4.1738 | $0.3993 |
| **total** | **290.5** | **$46.6901** | $0.1607 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **347.6 min** from 2026-09-17T22:27:04+00:00 to 2026-09-18T04:14:38+00:00, PR opened 2026-09-18T04:14:38+00:00.
Passes: review 72.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 72.5 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $42.5163 † | 280.0 † | $0.0000 | 0.0 | $3.1885 | 7.0 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.9853 | 3.5 | 02-review-sonnet | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and its `checkpoint` stamps span rounds 1, 2 — one figure cannot be divided between them, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

202989 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 33 | $3.1885 | 7.0 |  |
| sonnet | 1 | 35 | $0.9853 | 3.5 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 5 | 4 | 1.25 |
| 02-review-sonnet | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 106 | 103 |
| 02-review-sonnet | 60 | 73 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/Users/sahildesai/dev/agentTooling/.worktrees/lifecycle-records-and-numbering/self/tests/verdict-readers.sh` | Read | 01-review-opus, 02-review-sonnet |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | LIFECYCLE.md, plan-runner-roots.sh, self/review-report.md, self/tests/verdict-readers.sh | — |
| 02-review-sonnet | self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
