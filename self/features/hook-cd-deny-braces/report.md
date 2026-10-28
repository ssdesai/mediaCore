# hook-cd-deny-braces — cost and waste report

Generated 2026-09-16T14:57:28.058484+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $6.3424 | 51.2% |
| build | $2.2758 | 18.4% |
| verify | $1.9221 | 15.5% |
| review | $1.8486 | 14.9% |
| **total** | **$12.3889** | 100.0% |

cost per plan: $3.0972  
cost per file touched: $0.7743

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| planning: sessions | 46.9 | $6.3424 | $0.1353 |
| planning: delegates | 0.0 | $0.0000 |  |
| build | 9.4 | $2.2758 | $0.2421 |
| verify | 12.8 | $1.9221 | $0.1496 |
| review | 3.9 | $1.8486 | $0.4702 |
| **total** | **73.0** | **$12.3889** | $0.1696 |

Planning minutes are transcript spans: a delegate's span is its working time, a session's includes every minute nobody was typing, so the delegates row is the planning figure for a feature planned by delegates and the sessions row for one planned by hand. Build, verify and review minutes are summed over plans, so a parallel pair counts twice — the wall clock below does not.

Wall clock, as the runner saw it: **28.2 min** from 2026-09-16T14:22:30+00:00 to 2026-09-16T14:50:45+00:00, PR opened 2026-09-16T14:50:45+00:00.
Passes: build 9.4, verify 12.9, review 4.1. Gates: 1.9 min over 1 run(s). Plans as timed by the runner: 26.3 min over 4 run(s).

## Cold-start tax

386379 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 51 | $3.0848 | 7.0 |  |
| sonnet | 2 | 57 | $2.9617 | 19.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 101-hook-tests-sonnet | 6 | 3 | 2.00 |
| 102-hook-deny-and-braces-opus | 9 | 5 | 1.80 |
| 103-verify-sonnet | 6 | 6 | 1.00 |
| 104-review-opus | 14 | 6 | 2.33 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 101-hook-tests-sonnet | 162 | not computed: streams unavailable |
| 102-hook-deny-and-braces-opus | 194 | not computed: streams unavailable |
| 103-verify-sonnet | 58 | not computed: streams unavailable |
| 104-review-opus | 69 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 101-hook-tests-sonnet | — | allow-repo-commands.sh, tests/ |
| 102-hook-deny-and-braces-opus | — | hooks/ |
| 103-verify-sonnet | self/features/hook-cd-deny-braces/verify/inprogress/_scratch_brace_probe.py, self/features/hook-cd-deny-braces/verify/inprogress/_scratch_brace_probe2.py, self/features/hook-cd-deny-braces/verify/inprogress/_scratch_check_bashlex.py, self/features/hook-cd-deny-braces/verify/inprogress/_scratch_deny_probe.py, self/features/hook-cd-deny-braces/verify/inprogress/_scratch_deny_probe2.py, self/features/hook-cd-deny-braces/verify/inprogress/_scratch_probe_access.py | — |
| 104-review-opus | hooks/README.md, hooks/allow-repo-commands.sh, self/features/hook-cd-deny-braces/review/inprogress/_scratch_hash_probe.py, self/review-report.md, self/tests/README.md, self/tests/allow-repo-commands.sh | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
