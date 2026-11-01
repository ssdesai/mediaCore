# cloud-self-gate — cost and waste report

Generated 2026-10-05T15:39:08.344491+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $8.4664 | 100.0% |
| verify | $0.0000 | 0.0% |
| review | $0.0000 | 0.0% |
| **total** | **$8.4664** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $8.4664, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $0.0000  
cost per file touched: $0.0000

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 587.6 | $8.4664 | $0.0144 |
| verify | 0.0 | $0.0000 |  |
| review | 0.0 | $0.0000 |  |
| **total** | **587.6** | **$8.4664** | $0.0144 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

No wall clock: this feature has no `timing.jsonl`, so its batch ran on a runner that predates stamping. Only the executors' own durations are known.

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $8.4664 | 587.6 | $0.0000 | 0.0 | $0.0000 | 0.0 | — | — | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

0 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|

## Re-hunting

not computed: streams unavailable

## Plan drift

none found.

## Cross-plan edit overlap

not computed: streams unavailable

---

Rates from `analysis/rates_history.json`, last checked 2026-10-02 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
