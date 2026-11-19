# consumer-record-guard — cost and waste report

Generated 2026-11-17T04:26:48.758182+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $6.1393 | 65.4% |
| verify | $0.0000 | 0.0% |
| review | $3.2468 | 34.6% |
| **total** | **$9.3860** (partial) | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $6.1393, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

**This total is a lower bound** — at least one input is unavailable, so the real cost is higher and the percentages are skewed toward whatever survived.

**Excluded, though they ran:** 01-audit-opus. Each has a `usage.json` under this feature but no entry in the manifest's `plans` array, so its cost is missing from every figure above. Add the stems and regenerate.

cost per plan: $3.1287  
cost per file touched: $1.3409

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 95.4 | $6.1393 | $0.0644 |
| verify | 0.0 | $0.0000 |  |
| review | 6.0 | $3.2468 | $0.5422 |
| **total** | **101.4** | **$9.3860** | $0.0926 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **32.5 min** from 2026-11-17T03:54:16+00:00 to 2026-11-17T04:26:48+00:00, PR opened 2026-11-17T04:26:48+00:00.
Passes: review 12.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 15.0 min over 4 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $6.1393 † | 95.4 † | $0.0000 | 0.0 | $1.1884 | 1.4 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.0584 | 4.6 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

242684 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 62 | $3.2468 | 6.0 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 3 | 1.00 |
| 02-review-opus | 4 | 3 | 1.33 |
| 02-audit-opus | 4 | 2 | 2.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 72 | 84 |
| 02-review-opus | 90 | 82 |
| 02-audit-opus | 85 | 296 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/self/gate-report.txt` | Read | 01-review-opus, 02-review-opus |
| `/home/user/agentTooling/self/tests/consumer-record-guard.sh` | Read | 01-review-opus, 02-audit-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | analysis/orchestration_capture.py, analysis/report.py, self/review-report.md | — |
| 02-review-opus | self/review-report.md, self/tests/README.md, self/tests/consumer-record-guard.sh | — |
| 02-audit-opus | /tmp/plan-capture.G3hRPg/scratch/attack.sh, self/features/consumer-record-guard/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.G3hRPg/scratch/attack.sh | 02-audit-opus | 02-audit-opus | 45 |
| /tmp/plan-capture.G3hRPg/scratch/attack.sh | 02-audit-opus | 02-audit-opus | 241 |

## Warnings

- usage.json for 01-audit-opus exists but the manifest does not list it in `plans` — its cost is EXCLUDED from this roll-up; add the stem and re-run

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
