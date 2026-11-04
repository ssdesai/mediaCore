# rates-haiku-live-warning — cost and waste report

Generated 2026-10-13T18:54:29.215716+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $7.6176 | 80.5% |
| verify | $0.0000 | 0.0% |
| review | $1.8438 | 19.5% |
| **total** | **$9.4614** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $7.6176, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $4.7307  
cost per file touched: $1.8923

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 73.6 | $7.6176 | $0.1035 |
| verify | 0.0 | $0.0000 |  |
| review | 3.3 | $1.8438 | $0.5668 |
| **total** | **76.8** | **$9.4614** | $0.1231 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **44.0 min** from 2026-10-13T18:10:25+00:00 to 2026-10-13T18:54:28+00:00, PR opened 2026-10-13T18:54:28+00:00.
Passes: review 3.4. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.4 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $7.6176 † | 73.6 † | $0.0000 | 0.0 | $0.6595 | 1.3 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.1843 | 1.9 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

130047 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 46 | $1.8438 | 3.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 4 | 3 | 1.33 |
| 02-review-opus | 4 | 3 | 1.33 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 69 | 70 |
| 02-review-opus | 67 | 85 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md, self/tests/README.md, self/tests/rates-history.sh | — |
| 02-review-opus | README.md, self/PROJECT_FACTS.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
