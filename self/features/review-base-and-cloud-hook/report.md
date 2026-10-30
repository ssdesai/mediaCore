# review-base-and-cloud-hook — cost and waste report

Generated 2026-10-12T04:49:50.579980+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $53.9852 | 93.0% |
| verify | $0.0000 | 0.0% |
| review | $4.0907 | 7.0% |
| **total** | **$58.0760** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $53.9852, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $11.6152  
cost per file touched: $9.6793

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 7814.4 | $53.9852 | $0.0069 |
| ↳ acceptance tests | 9.3 |  |  |
| ↳ implementation | 123.0 |  |  |
| ↳ gate | 2.9 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 6.9 | $4.0907 | $0.5932 |
| **total** | **7821.3** | **$58.0760** | $0.0074 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **6480.1 min** from 2026-10-07T16:49:41+00:00 to 2026-10-12T04:49:49+00:00, PR opened 2026-10-12T04:49:49+00:00.
Passes: review 7.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 7.1 min over 5 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $53.9852 † | 7814.4 † | $0.0000 | 0.0 | $1.5558 | 2.4 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.1215 | 1.9 | 02-review-opus | escalated | escalations/02-review-opus.md |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.1267 | 0.2 | 03-review-sonnet | clean | — |
| 4 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.1288 | 1.9 | 04-review-opus | clean | — |
| 5 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.1579 | 0.4 | 05-review-sonnet | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and its `checkpoint` stamps span rounds 1, 2, 4 — one figure cannot be divided between them, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

312530 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 3 | 83 | $3.8062 | 6.3 |  |
| sonnet | 2 | 12 | $0.2846 | 0.6 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 2 | 1.50 |
| 02-review-opus | 4 | 3 | 1.33 |
| 03-review-sonnet | 1 | 1 | 1.00 |
| 04-review-opus | 4 | 3 | 1.33 |
| 05-review-sonnet | 1 | 1 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 154 | 88 |
| 02-review-opus | 64 | 156 |
| 03-review-sonnet | 36 | 29 |
| 04-review-opus | 59 | 94 |
| 05-review-sonnet | 36 | 30 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/self/tests/hook-cloud-profile.sh` | Read | 01-review-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | env-profile.sh, self/review-report.md | — |
| 02-review-opus | /tmp/plan-capture.cqYG0s/scratch/probe.py, hooks/README.md, self/review-report.md | — |
| 03-review-sonnet | self/review-report.md | — |
| 04-review-opus | LIFECYCLE.md, feature-capture.sh, self/review-report.md | — |
| 05-review-sonnet | self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-02 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
