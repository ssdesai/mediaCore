# self-corpus-identity — cost and waste report

Generated 2026-09-10T03:28:49.367089+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $16.2434 | 88.9% |
| verify | $0.0000 | 0.0% |
| review | $2.0293 | 11.1% |
| **total** | **$18.2728** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $16.2434, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $18.2728  
cost per file touched: $9.1364

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 353.3 | $16.2434 | $0.0460 |
| ↳ acceptance tests | 5.1 |  |  |
| ↳ implementation | 7.9 |  |  |
| ↳ gate | 1.9 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 5.5 | $2.0293 | $0.3660 |
| **total** | **358.8** | **$18.2728** | $0.0509 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **31.4 min** from 2026-09-09T22:13:22+00:00 to 2026-09-09T22:44:49+00:00, PR opened 2026-09-09T22:34:38+00:00.
Passes: review 5.7. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 5.5 min over 1 run(s).

## Cold-start tax

80000 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 26 | $2.0293 | 5.5 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 98-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 98-review-opus | 66 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 98-review-opus | analysis/README.md, self/review-report.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
