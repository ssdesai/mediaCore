# hook-role-hardening — cost and waste report

Generated 2026-11-12T02:44:48.199415+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $170.3419 | 94.7% |
| verify | $0.0000 | 0.0% |
| review | $9.5528 | 5.3% |
| **total** | **$179.8947** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $170.3419, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $22.4868  
cost per file touched: $4.2832

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 837.5 | $170.3419 | $0.2034 |
| verify | 0.0 | $0.0000 |  |
| review | 36.7 | $9.5528 | $0.2605 |
| **total** | **874.2** | **$179.8947** | $0.2058 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **112.2 min** from 2026-11-12T00:52:35+00:00 to 2026-11-12T02:44:46+00:00, PR opened 2026-11-12T02:44:46+00:00.
Passes: review 37.0. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 54.4 min over 8 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $170.3419 † | 837.5 † | $0.0000 | 0.0 | $3.4358 | 8.3 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $3.0284 | 11.9 | 02-review-opus | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.7626 | 13.1 | 03-review-opus | clean | — |
| 4 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.3260 | 3.4 | 04-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

556205 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 8 | 214 | $9.5528 | 36.7 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 2 | 2 | 1.00 |
| 01-audit-opus | 10 | 10 | 1.00 |
| 02-review-opus | 1 | 1 | 1.00 |
| 02-audit-opus | 15 | 14 | 1.07 |
| 03-review-opus | 3 | 3 | 1.00 |
| 03-audit-opus | 13 | 10 | 1.30 |
| 04-review-opus | 2 | 2 | 1.00 |
| 04-audit-opus | 8 | 7 | 1.14 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 71 | 58 |
| 01-audit-opus | 49 | 587 |
| 02-review-opus | 39 | 69 |
| 02-audit-opus | 50 | 471 |
| 03-review-opus | 37 | 88 |
| 03-audit-opus | 50 | 277 |
| 04-review-opus | 32 | 47 |
| 04-audit-opus | 50 | 282 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling-delegate-cost-claims/hooks/allow-repo-commands.sh` | Read | 02-audit-opus, 02-review-opus, 03-audit-opus, 04-audit-opus |
| `/home/user/agentTooling-delegate-cost-claims/self/features/hook-role-hardening/README.md` | Read | 01-audit-opus, 02-audit-opus, 04-audit-opus |
| `/home/user/agentTooling-delegate-cost-claims/self/features/hook-role-hardening/audit-report.md` | Read | 02-audit-opus, 03-audit-opus, 04-audit-opus |
| `/home/user/agentTooling-delegate-cost-claims/self/tests/hook-orchestrator-role.sh` | Read | 01-review-opus, 03-audit-opus, 03-review-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | hooks/allow-repo-commands.sh, self/review-report.md | — |
| 01-audit-opus | /tmp/plan-capture.WwybPB/scratch/auditpaths.sh, /tmp/plan-capture.WwybPB/scratch/p1.txt, /tmp/plan-capture.WwybPB/scratch/p2.txt, /tmp/plan-capture.WwybPB/scratch/payloads.py, /tmp/plan-capture.WwybPB/scratch/probe.py, /tmp/plan-capture.WwybPB/scratch/role.sh, /tmp/plan-capture.WwybPB/scratch/setup.sh, /tmp/plan-capture.WwybPB/scratch/uniq-demo.sh, /tmp/plan-capture.WwybPB/scratch/unreadable.sh, self/features/hook-role-hardening/audit-report.md | — |
| 02-review-opus | self/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.s5rBl2/scratch/audit-paths.sh, /tmp/plan-capture.s5rBl2/scratch/cases1.json, /tmp/plan-capture.s5rBl2/scratch/cases2.json, /tmp/plan-capture.s5rBl2/scratch/cases3.json, /tmp/plan-capture.s5rBl2/scratch/date-probe.sh, /tmp/plan-capture.s5rBl2/scratch/deep.sh, /tmp/plan-capture.s5rBl2/scratch/deep2.sh, /tmp/plan-capture.s5rBl2/scratch/drive.py, /tmp/plan-capture.s5rBl2/scratch/effects.sh, /tmp/plan-capture.s5rBl2/scratch/one.sh, /tmp/plan-capture.s5rBl2/scratch/plant.sh, /tmp/plan-capture.s5rBl2/scratch/setup.sh, /tmp/plan-capture.s5rBl2/scratch/textplant.sh, self/features/hook-role-hardening/audit-report.md | — |
| 03-review-opus | /tmp/plan-capture.Nb3Qa2/scratch/nested.sh, self/review-report.md, self/tests/hook-orchestrator-role.sh | — |
| 03-audit-opus | /tmp/plan-capture.c3uUBc/scratch/cmds0.txt, /tmp/plan-capture.c3uUBc/scratch/cmds1.txt, /tmp/plan-capture.c3uUBc/scratch/cmds2.txt, /tmp/plan-capture.c3uUBc/scratch/mkfiles.sh, /tmp/plan-capture.c3uUBc/scratch/mklink.sh, /tmp/plan-capture.c3uUBc/scratch/run.py, /tmp/plan-capture.c3uUBc/scratch/setup.sh, /tmp/plan-capture.c3uUBc/scratch/verify.sh, /tmp/plan-capture.c3uUBc/scratch/verify2.sh, self/features/hook-role-hardening/audit-report.md | — |
| 04-review-opus | self/review-report.md, self/tests/hook-orchestrator-role.sh | — |
| 04-audit-opus | /tmp/plan-capture.kHk6GV/scratch/cmds1.txt, /tmp/plan-capture.kHk6GV/scratch/cmds2.txt, /tmp/plan-capture.kHk6GV/scratch/cmds3.txt, /tmp/plan-capture.kHk6GV/scratch/probe.py, /tmp/plan-capture.kHk6GV/scratch/realdate.sh, /tmp/plan-capture.kHk6GV/scratch/setup.sh, self/features/hook-role-hardening/audit-report.md | — |

## Cross-plan edit overlap

none found.

## Warnings

- priced from LiteLLM live (litellm-live), not from analysis/rates_history.json: claude-fable-5-2 — refresh the history with analysis/refresh_rates.py in an agentTooling self feature, then capture_planning.py --recapture this feature

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
