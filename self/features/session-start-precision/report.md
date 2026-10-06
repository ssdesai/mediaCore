# session-start-precision — cost and waste report

Generated 2026-10-05T22:32:24.537708+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $5.7595 | 87.9% |
| verify | $0.0000 | 0.0% |
| review | $0.7946 | 12.1% |
| **total** | **$6.5541** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $5.7595, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $6.5541  
cost per file touched: $3.2770

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 35.4 | $5.7595 | $0.1626 |
| ↳ acceptance tests | 2.2 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 1.2 | $0.7946 | $0.6361 |
| **total** | **36.7** | **$6.5541** | $0.1788 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **13.1 min** from 2026-10-05T22:19:17+00:00 to 2026-10-05T22:32:23+00:00, PR opened 2026-10-05T22:32:23+00:00.
Passes: review 1.3. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 1.3 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $5.7595 | 35.4 | $0.0000 | 0.0 | $0.7946 | 1.2 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

56243 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 23 | $0.7946 | 1.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 2 | 1.50 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 69 | 94 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/DESIGN-2026-10-05-cloud-execution.md, self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/DESIGN-2026-10-05-cloud-execution.md | 01-review-opus | 01-review-opus | 188 |

---

Rates from `analysis/rates_history.json`, last checked 2026-10-02 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
