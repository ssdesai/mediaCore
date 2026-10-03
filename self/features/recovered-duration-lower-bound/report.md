# recovered-duration-lower-bound — cost and waste report

Generated 2026-09-09T22:37:00.070776+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $22.3554 | 87.5% |
| verify | $0.0000 | 0.0% |
| review | $3.1853 | 12.5% |
| **total** | **$25.5408** | 100.0% |

Sessions this feature shares: `ed088063-7aea-498e-84b1-7503d4bd88e1` (this feature's share $3.6693 of $70.4968), also claimed by agentTooling/tooling-backlog-2026-09-06, humanNetworkMap/delete-error-surface, humanNetworkMap/error-surface-completion, humanNetworkMap/mediacore-0-3-0, humanNetworkMap/validation-and-fetch-error-surface, musicMap/integration-test-database, musicMap/mediacore-0-3-0, musicMap/ruff-format-gate, vinylCatalogue/backlog-assertions-2026-09, vinylCatalogue/bundle-track-artist, vinylCatalogue/fold-duplicated-rows, vinylCatalogue/keyed-promotion-pairing, vinylCatalogue/show-selected-and-refetch-flake, vinylCatalogue/staged-commit-journal. The shares of all claimants sum to the session's own cost, so summing these features' totals now counts it once, not once per feature.

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $22.3554, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $25.5408  
cost per file touched: $6.3852

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 88.0 | $22.3554 | $0.2542 |
| ↳ acceptance tests | 5.5 |  |  |
| ↳ implementation | 13.5 |  |  |
| ↳ gate | 1.9 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 7.0 | $3.1853 | $0.4558 |
| **total** | **94.9** | **$25.5408** | $0.2690 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **210.8 min** from 2026-09-07T16:18:18+00:00 to 2026-09-07T19:49:07+00:00, PR opened 2026-09-07T19:30:08+00:00.
Passes: review 7.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 7.0 min over 2 run(s).

## Cold-start tax

135231 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 44 | $3.1853 | 7.0 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 88-review-opus | 5 | 4 | 1.25 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 88-review-opus | 65 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 88-review-opus | analysis/README.md, analysis/report.py, self/features/recovered-duration-lower-bound/NOTES.md, self/review-report.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
