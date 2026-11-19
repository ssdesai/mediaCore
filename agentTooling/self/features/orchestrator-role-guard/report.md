# orchestrator-role-guard — cost and waste report

Generated 2026-11-05T17:31:10.779088+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $14.3123 | 91.5% |
| verify | $0.0000 | 0.0% |
| review | $1.3218 | 8.5% |
| **total** | **$15.6341** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $14.3123, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $15.6341  
cost per file touched: $3.1268

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 71.2 | $14.3123 | $0.2011 |
| ↳ acceptance tests | 3.0 |  |  |
| ↳ implementation | 16.1 |  |  |
| ↳ gate | 0.1 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 2.7 | $1.3218 | $0.4929 |
| **total** | **73.9** | **$15.6341** | $0.2117 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **35.6 min** from 2026-11-05T16:53:56+00:00 to 2026-11-05T17:29:32+00:00, PR opened 2026-11-05T17:29:32+00:00.
Passes: review 2.7. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 2.7 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $14.3123 | 71.2 | $0.0000 | 0.0 | $1.3218 | 2.7 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

71962 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 33 | $1.3218 | 2.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 6 | 5 | 1.20 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 121 | 115 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | README.md, self/review-report.md, self/tests/README.md, self/tests/orchestrator-role.sh, templates/plans/ORCHESTRATOR_SESSION_BRIEF.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
