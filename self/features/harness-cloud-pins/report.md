# harness-cloud-pins — cost and waste report

Generated 2026-10-30T21:41:25.157333+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $29.0117 | 89.2% |
| verify | $0.0000 | 0.0% |
| review | $3.5272 | 10.8% |
| **total** | **$32.5389** | 100.0% |

Sessions this feature shares: `2483ee85-6358-53d1-b3fe-c7f1f895ab08` (this feature's share $21.6286 of $69.3437), also claimed by agentTooling/claude-md-chain. The shares of all claimants sum to the session's own cost, so summing these features' totals now counts it once, not once per feature.

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $29.0117, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $10.8463  
cost per file touched: $5.4231

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 143.8 | $29.0117 | $0.2018 |
| verify | 0.0 | $0.0000 |  |
| review | 6.8 | $3.5272 | $0.5152 |
| **total** | **150.6** | **$32.5389** | $0.2160 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **40.4 min** from 2026-10-30T13:54:46+00:00 to 2026-10-30T14:35:11+00:00, PR opened 2026-10-30T14:35:11+00:00.
Passes: review 7.0. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 7.0 min over 3 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $29.0117 † | 143.8 † | $0.0000 | 0.0 | $1.3972 | 3.1 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.3058 | 2.8 | 02-review-opus | escalated | escalations/02-review-opus.md |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.8242 | 1.0 | 03-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

255550 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 86 | $3.5272 | 6.8 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 8 | 5 | 1.60 |
| 02-review-opus | 2 | 2 | 1.00 |
| 03-review-opus | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 40 | 131 |
| 02-review-opus | 40 | 102 |
| 03-review-opus | 40 | 91 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/self/features/harness-cloud-pins/NOTES.md` | Read | 01-review-opus, 02-review-opus, 03-review-opus |
| `/home/user/agentTooling/self/features/harness-cloud-pins/README.md` | Read | 01-review-opus, 02-review-opus, 03-review-opus |
| `/home/user/agentTooling/self/gate-report.txt` | Read | 02-review-opus, 03-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | harness/README.md, harness/SPEC.md, harness/lib.sh, harness/run.sh, self/review-report.md | — |
| 02-review-opus | self/features/harness-cloud-pins/README.md, self/review-report.md | — |
| 03-review-opus | self/features/harness-cloud-pins/README.md, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
