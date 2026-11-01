# program-scorecard — cost and waste report

Generated 2026-10-30T22:26:45.526993+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $1.6831 | 52.9% |
| verify | $0.0000 | 0.0% |
| review | $1.5000 | 47.1% |
| **total** | **$3.1831** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $1.6831, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $3.1831  
cost per file touched: $0.5305

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 19.4 | $1.6831 | $0.0868 |
| verify | 0.0 | $0.0000 |  |
| review | 2.3 | $1.5000 | $0.6580 |
| **total** | **21.7** | **$3.1831** | $0.1469 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **3.1 min** from 2026-10-30T22:23:38+00:00 to 2026-10-30T22:26:44+00:00, PR opened 2026-10-30T22:26:44+00:00.
Passes: review 2.3. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 2.3 min over 1 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $1.6831 | 19.4 | $0.0000 | 0.0 | $1.5000 | 2.3 | 01-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

96151 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 32 | $1.5000 | 2.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 11 | 6 | 1.83 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 98 | 150 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | /tmp/plan-capture.bo9myX/scratch/oldcheck.sh, harness/README.md, harness/scorecard.py, harness/tests/README.md, harness/tests/scorecard-programs.sh, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
