# tooling-backlog-2026-09-06 — cost and waste report

Generated 2026-09-09T22:37:00.511575+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $31.6041 | 89.4% |
| verify | $0.0000 | 0.0% |
| review | $3.7493 | 10.6% |
| **total** | **$35.3534** | 100.0% |

Sessions this feature shares: `ed088063-7aea-498e-84b1-7503d4bd88e1` (this feature's share $4.3552 of $70.4968), also claimed by agentTooling/recovered-duration-lower-bound, humanNetworkMap/delete-error-surface, humanNetworkMap/error-surface-completion, humanNetworkMap/mediacore-0-3-0, humanNetworkMap/validation-and-fetch-error-surface, musicMap/integration-test-database, musicMap/mediacore-0-3-0, musicMap/ruff-format-gate, vinylCatalogue/backlog-assertions-2026-09, vinylCatalogue/bundle-track-artist, vinylCatalogue/fold-duplicated-rows, vinylCatalogue/keyed-promotion-pairing, vinylCatalogue/show-selected-and-refetch-flake, vinylCatalogue/staged-commit-journal. The shares of all claimants sum to the session's own cost, so summing these features' totals now counts it once, not once per feature.

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $31.6041, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $35.3534  
cost per file touched: $11.7845

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 231.1 | $31.6041 | $0.1368 |
| ↳ acceptance tests | 12.4 |  |  |
| ↳ implementation | 333.4 |  |  |
| ↳ gate | 2.0 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 7.3 | $3.7493 | $0.5168 |
| **total** | **238.3** | **$35.3534** | $0.1483 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **369.5 min** from 2026-09-06T22:32:55+00:00 to 2026-09-07T04:42:23+00:00, PR opened 2026-09-07T04:29:53+00:00.
Passes: review 7.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 7.3 min over 1 run(s).

## Cold-start tax

141720 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 40 | $3.7493 | 7.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 87-review-opus | 3 | 3 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 87-review-opus | 90 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 87-review-opus | self/BACKLOG.md, self/review-report.md, sync-plans.sh | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
