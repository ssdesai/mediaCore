# detached-at-branch-tip-attach — cost and waste report

Generated 2026-10-28T14:23:24.707225+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $7.5734 | 87.5% |
| verify | $0.0000 | 0.0% |
| review | $1.0808 | 12.5% |
| **total** | **$8.6542** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $7.5734, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $8.6542  
cost per file touched: $1.4424

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 707.2 | $7.5734 | $0.0107 |
| verify | 0.0 | $0.0000 |  |
| review | 2.1 | $1.0808 | $0.5036 |
| **total** | **709.3** | **$8.6542** | $0.0122 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **10.0 min** from 2026-10-28T14:13:24+00:00 to 2026-10-28T14:23:24+00:00, PR opened 2026-10-28T14:23:24+00:00.
Passes: review 2.2. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 2.2 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $7.5734 | 707.2 | $0.0000 | 0.0 | $1.0808 | 2.1 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

75104 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 28 | $1.0808 | 2.1 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 9 | 6 | 1.50 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 94 | 125 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | README.md, attach-branch.sh, plan-runner-roots.sh, self/review-report.md, self/tests/README.md, self/tests/attach-branch.sh | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
