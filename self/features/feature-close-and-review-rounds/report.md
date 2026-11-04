# feature-close-and-review-rounds — cost and waste report

Generated 2026-09-17T20:33:23.271332+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $52.8833 | 89.7% |
| verify | $0.0000 | 0.0% |
| review | $6.0497 | 10.3% |
| **total** | **$58.9330** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $52.8833, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $58.9330  
cost per file touched: $7.3666

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 109.5 | $52.8833 | $0.4829 |
| ↳ acceptance tests | 20.6 |  |  |
| ↳ implementation | 36.1 |  |  |
| ↳ gate | 42.5 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 27.8 | $6.0497 | $0.2178 |
| **total** | **137.3** | **$58.9330** | $0.4293 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **128.2 min** from 2026-09-17T18:25:12+00:00 to 2026-09-17T20:33:21+00:00, PR opened 2026-09-17T20:33:21+00:00.
Passes: review 27.8. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 27.8 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $52.8833 | 109.5 | $0.0000 | 0.0 | $6.0497 | 27.8 | 110-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

160803 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 68 | $6.0497 | 27.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 110-review-opus | 10 | 8 | 1.25 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 110-review-opus | 94 | 205 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 110-review-opus | /var/folders/w1/sjvnhgn11ml_fj_s_kch9xv40000gn/T/plan-capture.VLCpvJ/scratch/check-latest.sh, README.md, harness/SPEC.md, harness/methods/null/README.md, plan-runner-roots.sh, self/BACKLOG.md, self/review-report.md, templates/plans/features/TEMPLATE.md | — |

## Cross-plan edit overlap

none found.

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
