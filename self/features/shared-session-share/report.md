# shared-session-share — cost and waste report

Generated 2026-09-09T22:11:55.128236+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $14.4291 | 45.2% |
| build | $9.9668 | 31.2% |
| verify | $3.1181 | 9.8% |
| review | $4.4039 | 13.8% |
| **total** | **$31.9179** | 100.0% |

Sessions this feature shares: `ed76cd6f-477a-4b4e-84fd-c7a340538f14` (this feature's share $14.4291 of $38.4832), also claimed by agentTooling/claim-window-precision. The shares of all claimants sum to the session's own cost, so summing these features' totals now counts it once, not once per feature.

cost per plan: $3.9897  
cost per file touched: $2.4552

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| planning: sessions | 297.8 | $14.4291 | $0.0485 |
| planning: delegates | 0.0 | $0.0000 |  |
| build | 52.1 | $9.9668 | $0.1912 |
| verify | 15.4 | $3.1181 | $0.2026 |
| review | 10.9 | $4.4039 | $0.4025 |
| **total** | **376.2** | **$31.9179** | $0.0848 |

Planning minutes are transcript spans: a delegate's span is its working time, a session's includes every minute nobody was typing, so the delegates row is the planning figure for a feature planned by delegates and the sessions row for one planned by hand. Build, verify and review minutes are summed over plans, so a parallel pair counts twice — the wall clock below does not.

Wall clock, as the runner saw it: **272.0 min** from 2026-09-08T19:15:33+00:00 to 2026-09-08T23:47:31+00:00, PR opened 2026-09-08T23:47:31+00:00.
Passes: build 53.6, verify 15.4, review 11.1. Gates: 4.3 min over 3 run(s). Plans as timed by the runner: 78.7 min over 9 run(s).

## Cold-start tax

1168698 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 60 | $4.4039 | 10.9 |  |
| sonnet | 7 | 241 | $13.0849 | 67.5 | plan 91-share-pricing-sonnet took 64 turns (> 60); scope, not model — split it next time (AGENT_PLANS.md, 'Sizing plans for executor cost') |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 89-share-arithmetic-tests-sonnet | 6 | 4 | 1.50 |
| 90-claim-set-tests-sonnet | 5 | 3 | 1.67 |
| 91-share-pricing-sonnet | 24 | 3 | 8.00 |
| 92-level-capture-sonnet | 3 | 2 | 1.50 |
| 93-report-tests-sonnet | 3 | 2 | 1.50 |
| 94-report-share-sonnet | 10 | 4 | 2.50 |
| 96-review-opus | 4 | 3 | 1.33 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 89-share-arithmetic-tests-sonnet | 202 | not computed: streams unavailable |
| 90-claim-set-tests-sonnet | 127 | not computed: streams unavailable |
| 91-share-pricing-sonnet | 260 | not computed: streams unavailable |
| 92-level-capture-sonnet | 16 | not computed: streams unavailable |
| 93-report-tests-sonnet | 72 | not computed: streams unavailable |
| 94-report-share-sonnet | 91 | not computed: streams unavailable |
| 95-verify-sonnet | 40 | not computed: streams unavailable |
| 96-review-opus | 70 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 92-level-capture-sonnet | self/tests/session-claims.sh, self/tests/session-share.sh | — |
| 96-review-opus | analysis/README.md, analysis/report.py, self/review-report.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

## Warnings

- plan 95-verify-sonnet has 0 files_edited; excluded from churn ratio

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
