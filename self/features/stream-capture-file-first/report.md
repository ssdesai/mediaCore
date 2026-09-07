# stream-capture-file-first — cost and waste report

Generated 2026-09-06T16:27:35.334586+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $84.2069 | 96.0% |
| verify | $0.0000 | 0.0% |
| review | $3.4896 | 4.0% |
| **total** | **$87.6965** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $84.2069, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $87.6965  
cost per file touched: $14.6161

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 2950.1 | $84.2069 | $0.0285 |
| ↳ acceptance tests | 5.5 |  |  |
| ↳ implementation | 15.5 |  |  |
| ↳ gate | 2.4 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 10.2 | $3.4896 | $0.3415 |
| **total** | **2960.3** | **$87.6965** | $0.0296 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **41.2 min** from 2026-09-06T15:24:03+00:00 to 2026-09-06T16:05:16+00:00, PR opened 2026-09-06T16:05:16+00:00.
Passes: review 10.3. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 10.2 min over 1 run(s).

## Cold-start tax

118458 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 38 | $3.4896 | 10.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 86-review-opus | 9 | 6 | 1.50 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 86-review-opus | 144 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 86-review-opus | README.md, self/BACKLOG.md, self/features/README.md, self/features/stream-capture-file-first/NOTES.md, self/review-report.md, self/tests/stream-capture.sh | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
