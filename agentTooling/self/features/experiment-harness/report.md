# experiment-harness — cost and waste report

Generated 2026-09-10T03:53:24.500015+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $18.2448 | 100.0% |
| verify | $0.0000 | 0.0% |
| review | $0.0000 | 0.0% |
| **total** | **$18.2448** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $18.2448, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $0.0000  
cost per file touched: $0.0000

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 34.7 | $18.2448 | $0.5255 |
| verify | 0.0 | $0.0000 |  |
| review | 0.0 | $0.0000 |  |
| **total** | **34.7** | **$18.2448** | $0.5255 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

No wall clock: this feature has no `timing.jsonl`, so its batch ran on a runner that predates stamping. Only the executors' own durations are known.

## Cold-start tax

0 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|

## Re-hunting

not computed: streams unavailable

## Plan drift

none found.

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
