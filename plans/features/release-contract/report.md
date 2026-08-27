# release-contract — cost and waste report

Generated 2026-08-27T21:09:50.359570+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $80.0006 | 93.6% |
| build | $1.5126 | 1.8% |
| verify | $1.4503 | 1.7% |
| review | $2.5300 | 3.0% |
| **total** | **$85.4934** | 100.0% |

cost per plan: $7.1245  
cost per file touched: $3.8861

## Cold-start tax

471247 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | flags |
|---|---|---|---|---|
| haiku | 4 | 26 | $0.3087 | plan 05-package-core-haiku took 10 turns on haiku (> 8, may have needed more judgment than haiku gives) |
| opus | 1 | 41 | $2.5300 |  |
| sonnet | 7 | 106 | $2.6542 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-acceptance-tests-sonnet | 3 | 3 | 1.00 |
| 02-tests-core-haiku | 2 | 2 | 1.00 |
| 03-tests-release-haiku | 1 | 1 | 1.00 |
| 04-tests-bundle-sonnet | 2 | 1 | 2.00 |
| 05-package-core-haiku | 4 | 4 | 1.00 |
| 06-package-release-haiku | 1 | 1 | 1.00 |
| 07-package-bundle-sonnet | 5 | 5 | 1.00 |
| 08-level-core-sonnet | 1 | 1 | 1.00 |
| 09-fixture-script-sonnet | 3 | 3 | 1.00 |
| 10-level-fixture-sonnet | 1 | 1 | 1.00 |
| 12-review-opus | 9 | 5 | 1.80 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-acceptance-tests-sonnet | 285 | not computed: streams unavailable |
| 02-tests-core-haiku | 129 | not computed: streams unavailable |
| 03-tests-release-haiku | 112 | not computed: streams unavailable |
| 04-tests-bundle-sonnet | 107 | not computed: streams unavailable |
| 05-package-core-haiku | 259 | not computed: streams unavailable |
| 06-package-release-haiku | 161 | not computed: streams unavailable |
| 07-package-bundle-sonnet | 271 | not computed: streams unavailable |
| 08-level-core-sonnet | 15 | not computed: streams unavailable |
| 09-fixture-script-sonnet | 328 | not computed: streams unavailable |
| 10-level-fixture-sonnet | 17 | not computed: streams unavailable |
| 11-verify-sonnet | 68 | not computed: streams unavailable |
| 12-review-opus | 61 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 08-level-core-sonnet | tests/test_refs.py | — |
| 10-level-fixture-sonnet | scripts/make_fixture_its_saxy.py | — |
| 12-review-opus | fixtures/README.md, plans/features/release-contract/README.md, plans/review-report.md, src/mediacore/README.md, tests/test_fixture.py | — |

## Cross-plan edit overlap

not computed: streams unavailable

## Warnings

- plan 11-verify-sonnet has 0 files_edited; excluded from churn ratio

---

Rates last verified 2026-08-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
