# hook-opaque-commands-and-audit — cost and waste report

Generated 2026-09-17T17:46:48.272297+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $24.1375 | 90.3% |
| verify | $0.0000 | 0.0% |
| review | $2.6068 | 9.7% |
| **total** | **$26.7443** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $24.1375, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $26.7443  
cost per file touched: $4.4574

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 55.6 | $24.1375 | $0.4344 |
| ↳ acceptance tests | 17.6 |  |  |
| ↳ implementation | 15.8 |  |  |
| ↳ gate | 3.6 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 3.2 | $2.6068 | $0.8146 |
| **total** | **58.8** | **$26.7443** | $0.4551 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **134.0 min** from 2026-09-17T15:22:07+00:00 to 2026-09-17T17:36:07+00:00, PR opened 2026-09-17T16:04:07+00:00.
Passes: review 3.4. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.2 min over 1 run(s).

## Cold-start tax

118561 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 30 | $2.6068 | 3.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 108-review-opus | 7 | 6 | 1.17 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 108-review-opus | 136 | 194 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 108-review-opus | /var/folders/w1/sjvnhgn11ml_fj_s_kch9xv40000gn/T/plan-capture.02fcDK/scratch/probe.py, hooks/README.md, hooks/allow-repo-commands.sh, review-probe.tmp.py, self/review-report.md, self/tests/allow-repo-commands.sh | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/tests/allow-repo-commands.sh | 108-review-opus | 108-review-opus | 245 |

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
