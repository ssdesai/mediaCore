# hook-hash-chained-cd — cost and waste report

Generated 2026-10-02T01:59:05.768142+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $24.9721 | 94.2% |
| verify | $0.0000 | 0.0% |
| review | $1.5445 | 5.8% |
| **total** | **$26.5166** | 100.0% |

Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), $24.9721, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $6.6292  
cost per file touched: $5.3033

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: by hand | 225.6 | $24.9721 | $0.1107 |
| verify | 0.0 | $0.0000 |  |
| review | 11.9 | $1.5445 | $0.1301 |
| **total** | **237.5** | **$26.5166** | $0.1116 |

The build's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **202.2 min** from 2026-10-01T22:36:49+00:00 to 2026-10-02T01:59:03+00:00, PR opened 2026-10-02T01:59:03+00:00.
Passes: review 12.1. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 12.1 min over 4 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $24.9721 † | 225.6 † | $0.0000 | 0.0 | $0.9244 | 2.6 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.1879 | 0.7 | 02-review-sonnet | escalated | escalations/02-review-sonnet.md |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.1727 | 2.9 | 03-review-sonnet | clean | — |
| 4 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.2595 | 5.7 | 04-review-sonnet | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

161027 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 19 | $0.9244 | 2.6 |  |
| sonnet | 3 | 31 | $0.6200 | 9.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 5 | 3 | 1.67 |
| 02-review-sonnet | 4 | 3 | 1.33 |
| 03-review-sonnet | 1 | 1 | 1.00 |
| 04-review-sonnet | 2 | 2 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 55 | 132 |
| 02-review-sonnet | 38 | 32 |
| 03-review-sonnet | 32 | 27 |
| 04-review-sonnet | 64 | 60 |

## Re-hunting

none found.

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | /var/folders/w1/sjvnhgn11ml_fj_s_kch9xv40000gn/T/plan-capture.CnX0x3/scratch/probe.py, hooks/allow-repo-commands.sh, self/review-report.md | — |
| 02-review-sonnet | hooks/allow-repo-commands.sh, self/review-report.md, self/tests/allow-repo-commands.sh | — |
| 03-review-sonnet | self/review-report.md | — |
| 04-review-sonnet | /var/folders/w1/sjvnhgn11ml_fj_s_kch9xv40000gn/T/plan-capture.esOI6Q/scratch/probe.py, self/review-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| self/review-report.md | 01-review-opus | 01-review-opus | 347 |
| self/tests/allow-repo-commands.sh | 02-review-sonnet | 02-review-sonnet | 126 |

---

Rates from `analysis/rates_history.json`, last checked 2026-09-22 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
