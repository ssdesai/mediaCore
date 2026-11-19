# shared-hook-rules — cost and waste report

Generated 2026-11-14T02:52:57.618661+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $23.6635 | 74.0% |
| verify | $0.0000 | 0.0% |
| review | $8.3142 | 26.0% |
| **total** | **$31.9777** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $23.6635, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $3.9972  
cost per file touched: $1.2791

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 1383.1 | $23.6635 | $0.0171 |
| ↳ gate | 8.1 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 26.9 | $8.3142 | $0.3088 |
| **total** | **1410.0** | **$31.9777** | $0.0227 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **776.4 min** from 2026-11-13T13:56:35+00:00 to 2026-11-14T02:52:56+00:00, PR opened 2026-11-14T02:52:56+00:00.
Passes: review 27.5. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 31.8 min over 8 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $23.6635 | 1383.1 | $0.0000 | 0.0 | $2.7654 | 5.5 | 01-review-opus | clean | — |
| 2 | $0.0000 | 0.0 | $0.0000 | 0.0 | $1.7447 | 8.2 | 02-review-opus | clean | — |
| 3 | $0.0000 | 0.0 | $0.0000 | 0.0 | $1.4771 | 3.2 | 03-review-opus | clean | — |
| 4 | $0.0000 | 0.0 | $0.0000 | 0.0 | $2.3271 | 10.1 | 04-review-opus | clean | — |

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

551322 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 8 | 170 | $8.3142 | 26.9 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 01-audit-opus | 4 | 3 | 1.33 |
| 02-review-opus | 1 | 1 | 1.00 |
| 02-audit-opus | 6 | 6 | 1.00 |
| 03-review-opus | 2 | 2 | 1.00 |
| 03-audit-opus | 3 | 3 | 1.00 |
| 04-review-opus | 5 | 5 | 1.00 |
| 04-audit-opus | 9 | 9 | 1.00 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 73 | 77 |
| 01-audit-opus | 50 | 471 |
| 02-review-opus | 45 | 40 |
| 02-audit-opus | 50 | 449 |
| 03-review-opus | 43 | 48 |
| 03-audit-opus | 50 | 360 |
| 04-review-opus | 55 | 85 |
| 04-audit-opus | 50 | 516 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/hooks/allow-repo-commands.sh` | Read | 01-audit-opus, 02-audit-opus, 04-audit-opus |
| `/home/user/agentTooling/self/features/shared-hook-rules/NOTES.md` | Read | 01-review-opus, 03-review-opus, 04-review-opus |
| `/home/user/agentTooling/self/tests/hook-orchestrator-role.sh` | Read | 02-audit-opus, 03-audit-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | orchestration-start.sh, self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.P9aCiF/scratch/audit.py, /tmp/plan-capture.P9aCiF/scratch/extra.py, self/features/shared-hook-rules/audit-report.md | — |
| 02-review-opus | self/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.n2Yb6W/scratch/ostart.sh, /tmp/plan-capture.n2Yb6W/scratch/probe.py, /tmp/plan-capture.n2Yb6W/scratch/probe2.py, /tmp/plan-capture.n2Yb6W/scratch/setup.sh, /tmp/plan-capture.n2Yb6W/scratch/wire.py, self/features/shared-hook-rules/audit-report.md | — |
| 03-review-opus | self/features/shared-hook-rules/README.md, self/review-report.md | — |
| 03-audit-opus | /tmp/plan-capture.nCifoj/scratch/audit.py, /tmp/plan-capture.nCifoj/scratch/wire.py, self/features/shared-hook-rules/audit-report.md | — |
| 04-review-opus | /tmp/plan-capture.N7dIE4/scratch/check.sh, /tmp/plan-capture.N7dIE4/scratch/cmp.py, hooks/README.md, self/review-report.md, self/tests/shared-rules.sh | — |
| 04-audit-opus | /tmp/plan-capture.EbAaPC/scratch/ostart.sh, /tmp/plan-capture.EbAaPC/scratch/probe.py, /tmp/plan-capture.EbAaPC/scratch/probe2.py, /tmp/plan-capture.EbAaPC/scratch/probe3.py, /tmp/plan-capture.EbAaPC/scratch/rest.sh, /tmp/plan-capture.EbAaPC/scratch/setup.sh, /tmp/plan-capture.EbAaPC/scratch/variants.py, /tmp/plan-capture.EbAaPC/scratch/wsdump.py, self/features/shared-hook-rules/audit-report.md | — |

## Cross-plan edit overlap

none found.

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
