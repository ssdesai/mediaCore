# tooling-backlog-2026-09 — cost and waste report

Generated 2026-09-02T13:16:06.307068+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $10.3128 | 63.8% |
| verify | $0.0000 | 0.0% |
| review | $5.8496 | 36.2% |
| **total** | **$16.1624** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $10.3128, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $16.1624  
cost per file touched: $2.6937

$2.6254 of the total above is **derived**, not measured — priced from session transcripts by recover_attempts.py for attempts the CLI itself never reported a cost for.

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 21.8 | $10.3128 | $0.4731 |
| ↳ gate | 2.2 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 7.3 | $5.8496 | $0.7990 |
| **total** | **29.1** | **$16.1624** | $0.5550 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **21.5 min** from 2026-09-02T12:54:00+00:00 to 2026-09-02T13:15:30+00:00, PR opened 2026-09-02T13:15:30+00:00.
Passes: review 13.0. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 7.3 min over 1 run(s).

## Cold-start tax

110447 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 46 | $3.2242 | 7.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 71-review-opus | 9 | 6 | 1.50 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 71-review-opus | 81 | 135 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 71-review-opus | README.md, self/features/tooling-backlog-2026-09/NOTES.md, self/review-report.md, templates/README.md, templates/plans/.gitignore, templates/plans/README.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/review-report.md | 71-review-opus | 71-review-opus | 85 |
| self/review-report.md | 71-review-opus | 71-review-opus | 87 |
| self/review-report.md | 71-review-opus | 71-review-opus | 139 |

## Warnings

- plan 71-review-opus has 1 attempt(s) priced from session transcripts rather than reported by the CLI (sessions: 11675eec-5e12-4f16-9ab0-58faf6dd3d54)

---

Rates last verified 2026-08-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
