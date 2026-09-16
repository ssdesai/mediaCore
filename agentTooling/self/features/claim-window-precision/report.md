# claim-window-precision — cost and waste report

Generated 2026-09-09T22:12:21.449996+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $48.1818 | 93.5% |
| verify | $0.0000 | 0.0% |
| review | $3.3303 | 6.5% |
| **total** | **$51.5121** | 100.0% |

Sessions this feature shares: `ed76cd6f-477a-4b4e-84fd-c7a340538f14` (this feature's share $6.9848 of $38.4832), also claimed by agentTooling/shared-session-share. The shares of all claimants sum to the session's own cost, so summing these features' totals now counts it once, not once per feature.

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $48.1818, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $51.5121  
cost per file touched: $17.1707

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 943.2 | $48.1818 | $0.0511 |
| ↳ acceptance tests | 5.4 |  |  |
| ↳ implementation | 17.1 |  |  |
| ↳ gate | 4.6 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 8.4 | $3.3303 | $0.3980 |
| **total** | **951.6** | **$51.5121** | $0.0541 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **72.7 min** from 2026-09-09T14:09:34+00:00 to 2026-09-09T15:22:15+00:00, PR opened 2026-09-09T14:48:32+00:00.
Passes: review 8.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 8.4 min over 1 run(s).

## Cold-start tax

121099 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 35 | $3.3303 | 8.4 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 97-review-opus | 4 | 3 | 1.33 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 97-review-opus | 64 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 97-review-opus | analysis/README.md, analysis/capture_planning.py, self/review-report.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
