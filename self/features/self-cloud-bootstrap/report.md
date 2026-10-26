# self-cloud-bootstrap — cost and waste report

Generated 2026-10-06T05:33:27.618797+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: skipped — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $34.4623 | 94.3% |
| verify | $0.0000 | 0.0% |
| review | $2.0970 | 5.7% |
| **total** | **$36.5593** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $34.4623, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $18.2797  
cost per file touched: $12.1864

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 856.5 | $34.4623 | $0.0402 |
| ↳ acceptance tests | 4.2 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 3.0 | $2.0970 | $0.7078 |
| **total** | **859.5** | **$36.5593** | $0.0425 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **438.5 min** from 2026-10-05T22:14:56+00:00 to 2026-10-06T05:33:26+00:00, PR opened 2026-10-06T05:33:26+00:00.
Passes: review 3.0. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 3.0 min over 2 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $34.4623 † | 856.5 † | $0.0000 | 0.0 | $1.2296 | 1.5 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.8674 | 1.5 | 02-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and its `checkpoint` stamps span rounds 1, 2 — one figure cannot be divided between them, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

148871 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 2 | 58 | $2.0970 | 3.0 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 1 | 1 | 1.00 |
| 02-review-opus | 3 | 3 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 74 | 77 |
| 02-review-opus | 45 | 60 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agenttooling/self/gate-report.txt` | Read | 01-review-opus, 02-review-opus |
| `/home/user/agenttooling/self/tests/README.md` | Read | 01-review-opus, 02-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | self/review-report.md | — |
| 02-review-opus | /tmp/plan-capture.VpHu74/scratch/markers.sh, self/gate.sh, self/review-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-02 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
