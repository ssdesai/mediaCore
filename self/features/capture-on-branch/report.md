# capture-on-branch — cost and waste report

Generated 2026-09-17T15:22:47.394635+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $25.6783 | 90.0% |
| verify | $0.0000 | 0.0% |
| review | $2.8513 | 10.0% |
| **total** | **$28.5296** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $25.6783, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $28.5296  
cost per file touched: $4.0757

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 35.8 | $25.6783 | $0.7183 |
| ↳ acceptance tests | 12.6 |  |  |
| ↳ implementation | 16.1 |  |  |
| ↳ gate | 2.6 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 3.1 | $2.8513 | $0.9056 |
| **total** | **38.9** | **$28.5296** | $0.7334 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **39.8 min** from 2026-09-17T14:42:59+00:00 to 2026-09-17T15:22:46+00:00, PR opened 2026-09-17T15:22:46+00:00.
Passes: review 3.3. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.2 min over 1 run(s).

## Cold-start tax

108132 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 42 | $2.8513 | 3.1 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 107-review-opus | 7 | 7 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 107-review-opus | 140 | 128 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 107-review-opus | README.md, self/BACKLOG.md, self/features/capture-on-branch/NOTES.md, self/pr.sh, self/review-report.md, templates/plans/TEMPLATE_VERSIONS, templates/plans/pr.sh | — |

## Cross-plan edit overlap

none found.

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
