# hand-start-friction — cost and waste report

Generated 2026-10-28T21:59:16.944583+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $8.6610 | 83.6% |
| verify | $0.0000 | 0.0% |
| review | $1.7015 | 16.4% |
| **total** | **$10.3625** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $8.6610, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $5.1813  
cost per file touched: $3.4542

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 43.5 | $8.6610 | $0.1993 |
| verify | 0.0 | $0.0000 |  |
| review | 3.3 | $1.7015 | $0.5179 |
| **total** | **46.7** | **$10.3625** | $0.2217 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **12.3 min** from 2026-10-28T21:46:57+00:00 to 2026-10-28T21:59:16+00:00, PR opened 2026-10-28T21:59:16+00:00.
Passes: review 3.4. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.4 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $8.6610 † | 43.5 † | $0.0000 | 0.0 | $1.0515 | 1.9 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.6500 | 1.4 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

119140 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 42 | $1.7015 | 3.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 2 | 1.50 |
| 02-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 84 | 107 |
| 02-review-opus | 40 | 81 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/feature-start.sh` | Read | 01-review-opus, 02-review-opus |
| `/home/user/agentTooling/self/tests/cloud-setup-wait.sh` | Read | 01-review-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | feature-start.sh, self/review-report.md | — |
| 02-review-opus | self/review-report.md, self/tests/cloud-setup-wait.sh | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
