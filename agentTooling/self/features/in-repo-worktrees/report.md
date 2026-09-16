# in-repo-worktrees — cost and waste report

Generated 2026-09-11T15:14:43.940061+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $23.3872 | 94.7% |
| verify | $0.0000 | 0.0% |
| review | $1.3053 | 5.3% |
| **total** | **$24.6925** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $23.3872, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $24.6925  
cost per file touched: $12.3462

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 84.0 | $23.3872 | $0.2784 |
| ↳ acceptance tests | 5.2 |  |  |
| ↳ implementation | 8.3 |  |  |
| ↳ gate | 2.2 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 2.8 | $1.3053 | $0.4673 |
| **total** | **86.8** | **$24.6925** | $0.2845 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **19.8 min** from 2026-09-11T14:40:17+00:00 to 2026-09-11T15:00:03+00:00, PR opened 2026-09-11T15:00:03+00:00.
Passes: review 3.0. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 2.8 min over 1 run(s).

## Cold-start tax

70188 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 23 | $1.3053 | 2.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 100-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 100-review-opus | 121 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 100-review-opus | analysis/README.md, self/review-report.md | — |

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
