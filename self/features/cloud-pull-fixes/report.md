# cloud-pull-fixes — cost and waste report

Generated 2026-10-13T00:32:57.337206+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $9.5314 | 77.0% |
| verify | $0.0000 | 0.0% |
| review | $2.8402 | 23.0% |
| **total** | **$12.3715** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $9.5314, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.1238  
cost per file touched: $2.0619

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 34.9 | $9.5314 | $0.2732 |
| ↳ acceptance tests | 2.7 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 5.2 | $2.8402 | $0.5487 |
| **total** | **40.1** | **$12.3715** | $0.3088 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **45.3 min** from 2026-10-12T23:47:40+00:00 to 2026-10-13T00:32:56+00:00, PR opened 2026-10-13T00:32:56+00:00.
Passes: review 5.3. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 5.3 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $9.5314 | 34.9 | $0.0000 | 0.0 | $1.6925 | 2.6 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 | 0.0 | $0.0000 | 0.0 | $0.6056 | 1.5 | 02-review-opus | escalated | escalations/02-review-opus.md |
| 3 | $0.0000 | 0.0 | $0.0000 | 0.0 | $0.5421 | 1.1 | 03-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

186299 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 67 | $2.8402 | 5.2 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 4 | 4 | 1.00 |
| 02-review-opus | 2 | 2 | 1.00 |
| 03-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 101 | 73 |
| 02-review-opus | 81 | 74 |
| 03-review-opus | 41 | 66 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | /tmp/plan-capture.jqyTK1/scratch/tv.sh, LIFECYCLE.md, self/review-report.md, update.sh | — |
| 02-review-opus | self/review-report.md, self/tests/template-versions.sh | — |
| 03-review-opus | self/review-report.md, self/tests/template-version-bump.sh | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-02 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
