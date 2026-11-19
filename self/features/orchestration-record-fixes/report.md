# orchestration-record-fixes — cost and waste report

Generated 2026-11-16T01:36:55.277855+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $32.7786 | 48.9% |
| verify | $0.0000 | 0.0% |
| review | $34.2550 | 51.1% |
| **total** | **$67.0336** | 100.0% |

3 planning rows carried from the captures of 2026-11-11, 2026-11-14: the capture could not reach their transcripts (an earlier round's container, or expired), so the planning figure chains that capture's dollars with this one's.

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $32.7786, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $2.4827  
cost per file touched: $0.4754

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 1016.0 | $32.7786 | $0.0323 |
| verify | 0.0 | $0.0000 |  |
| review | 110.5 | $34.2550 | $0.3100 |
| **total** | **1126.5** | **$67.0336** | $0.0595 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record.

Wall clock, as the runner saw it: **3553.3 min** from 2026-11-11T16:20:11+00:00 to 2026-11-14T03:33:30+00:00, PR opened 2026-11-14T03:33:30+00:00.
Passes: review 111.7. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 139.8 min over 27 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $32.7786 † | 1016.0 † | $0.0000 | 0.0 | $0.6419 | 1.4 | 01-review-opus | clean | — |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $0.3557 | 0.5 | 02-review-opus | clean | — |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $1.4107 | 3.8 | 03-review-opus | escalated | escalations/03-review-opus.md |
| 4 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $3.8358 | 10.8 | 04-review-opus | escalated | escalations/04-review-opus.md |
| 5 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.0798 | 6.6 | 05-review-opus | escalated | escalations/05-review-opus.md |
| 6 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.1771 | 6.2 | 06-review-opus | escalated | escalations/06-review-opus.md |
| 7 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.4218 | 7.7 | 07-review-opus | escalated | escalations/07-review-opus.md |
| 8 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $3.1478 | 10.8 | 08-review-opus | escalated | escalations/08-review-opus.md |
| 9 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $3.2906 | 22.9 | 09-review-opus | clean | — |
| 10 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.1656 | 6.0 | 10-review-opus | clean | — |
| 11 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.2900 | 6.6 | 11-review-opus | clean | — |
| 12 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $3.2838 | 9.5 | 12-review-opus | clean | — |
| 13 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.0941 | 5.5 | 13-review-opus | escalated | escalations/13-review-opus.md |
| 14 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.7378 | 6.4 | 14-review-opus | clean | — |
| 15 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.3227 | 5.9 | 15-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and this feature stamped no `checkpoint` event — nothing divides it by round, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

1867836 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 27 | 802 | $34.2550 | 110.5 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 3 | 3 | 1.00 |
| 02-review-opus | 2 | 2 | 1.00 |
| 03-review-opus | 12 | 10 | 1.20 |
| 04-review-opus | 14 | 9 | 1.56 |
| 04-audit-opus | 7 | 7 | 1.00 |
| 05-review-opus | 2 | 2 | 1.00 |
| 05-audit-opus | 10 | 9 | 1.11 |
| 06-review-opus | 3 | 3 | 1.00 |
| 06-audit-opus | 9 | 7 | 1.29 |
| 07-review-opus | 5 | 4 | 1.25 |
| 07-audit-opus | 12 | 10 | 1.20 |
| 08-review-opus | 6 | 4 | 1.50 |
| 08-audit-opus | 21 | 17 | 1.24 |
| 09-review-opus | 7 | 5 | 1.40 |
| 09-audit-opus | 13 | 10 | 1.30 |
| 10-review-opus | 3 | 3 | 1.00 |
| 10-audit-opus | 11 | 10 | 1.10 |
| 11-review-opus | 4 | 3 | 1.33 |
| 11-audit-opus | 11 | 9 | 1.22 |
| 12-review-opus | 4 | 4 | 1.00 |
| 12-audit-opus | 13 | 12 | 1.08 |
| 13-review-opus | 2 | 2 | 1.00 |
| 13-audit-opus | 6 | 6 | 1.00 |
| 14-review-opus | 5 | 2 | 2.50 |
| 14-audit-opus | 11 | 10 | 1.10 |
| 15-review-opus | 1 | 1 | 1.00 |
| 15-audit-opus | 9 | 7 | 1.29 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 51 | 81 |
| 02-review-opus | 31 | 47 |
| 03-review-opus | 42 | not computed: streams unavailable |
| 04-review-opus | 43 | not computed: streams unavailable |
| 04-audit-opus | 42 | not computed: streams unavailable |
| 05-review-opus | 40 | not computed: streams unavailable |
| 05-audit-opus | 42 | not computed: streams unavailable |
| 06-review-opus | 40 | not computed: streams unavailable |
| 06-audit-opus | 42 | not computed: streams unavailable |
| 07-review-opus | 43 | not computed: streams unavailable |
| 07-audit-opus | 42 | not computed: streams unavailable |
| 08-review-opus | 45 | not computed: streams unavailable |
| 08-audit-opus | 42 | not computed: streams unavailable |
| 09-review-opus | 51 | 227 |
| 09-audit-opus | 42 | 584 |
| 10-review-opus | 41 | 154 |
| 10-audit-opus | 42 | 409 |
| 11-review-opus | 43 | 163 |
| 11-audit-opus | 42 | 474 |
| 12-review-opus | 49 | 173 |
| 12-audit-opus | 41 | 634 |
| 13-review-opus | 47 | 123 |
| 13-audit-opus | 41 | 403 |
| 14-review-opus | 59 | 147 |
| 14-audit-opus | 41 | 607 |
| 15-review-opus | 25 | 58 |
| 15-audit-opus | 41 | 508 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/hooks/README.md` | Read | 10-review-opus, 14-audit-opus |
| `/home/user/agentTooling/hooks/allow-repo-commands.sh` | Read | 09-audit-opus, 09-review-opus, 10-audit-opus, 10-review-opus, 11-audit-opus, 11-review-opus, 13-audit-opus, 13-review-opus, 14-audit-opus, 14-review-opus, 15-audit-opus |
| `/home/user/agentTooling/hooks/orchestrator_role.py` | Read | 09-audit-opus, 13-audit-opus |
| `/home/user/agentTooling/self/features/orchestration-record-fixes/NOTES.md` | Read | 14-audit-opus, 14-review-opus |
| `/home/user/agentTooling/self/features/orchestration-record-fixes/audit-report.md` | Read | 10-audit-opus, 11-audit-opus, 13-audit-opus, 14-audit-opus, 15-audit-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | analysis/README.md, analysis/report.py, self/review-report.md | — |
| 02-review-opus | self/features/orchestration-record-fixes/README.md, self/review-report.md | — |
| 03-review-opus | /tmp/plan-capture.t8jhTg/scratch/base.py, /tmp/plan-capture.t8jhTg/scratch/cmds1.txt, /tmp/plan-capture.t8jhTg/scratch/cmds2.txt, /tmp/plan-capture.t8jhTg/scratch/cmds3.txt, /tmp/plan-capture.t8jhTg/scratch/cmds4.txt, /tmp/plan-capture.t8jhTg/scratch/cmds5.txt, /tmp/plan-capture.t8jhTg/scratch/probe.py, hooks/allow-repo-commands.sh, self/features/orchestration-record-fixes/README.md, self/review-report.md | — |
| 04-review-opus | /tmp/plan-capture.JFyHkf/scratch/assign.py, /tmp/plan-capture.JFyHkf/scratch/build_judge.py, /tmp/plan-capture.JFyHkf/scratch/cmds.txt, /tmp/plan-capture.JFyHkf/scratch/cmds2.txt, /tmp/plan-capture.JFyHkf/scratch/cmds3.txt, /tmp/plan-capture.JFyHkf/scratch/extract.py, /tmp/plan-capture.JFyHkf/scratch/probe.py, hooks/README.md, self/review-report.md | — |
| 04-audit-opus | /tmp/plan-capture.MMZErn/scratch/bashcheck.sh, /tmp/plan-capture.MMZErn/scratch/driver.py, /tmp/plan-capture.MMZErn/scratch/malformed.py, /tmp/plan-capture.MMZErn/scratch/p1.json, /tmp/plan-capture.MMZErn/scratch/p2.json, /tmp/plan-capture.MMZErn/scratch/p3.json, self/features/orchestration-record-fixes/audit-report.md | — |
| 05-review-opus | /tmp/plan-capture.mvy9Ey/scratch/drive.py, self/review-report.md | — |
| 05-audit-opus | /tmp/plan-capture.BsH7wj/scratch/bashcheck.sh, /tmp/plan-capture.BsH7wj/scratch/c1.json, /tmp/plan-capture.BsH7wj/scratch/c2.json, /tmp/plan-capture.BsH7wj/scratch/c3.json, /tmp/plan-capture.BsH7wj/scratch/c4.json, /tmp/plan-capture.BsH7wj/scratch/fixture.py, /tmp/plan-capture.BsH7wj/scratch/run.py, /tmp/plan-capture.BsH7wj/scratch/why.py, self/features/orchestration-record-fixes/audit-report.md | — |
| 06-review-opus | /tmp/plan-capture.YEWzCO/scratch/drive.py, /tmp/plan-capture.YEWzCO/scratch/reason.py, self/review-report.md | — |
| 06-audit-opus | /tmp/plan-capture.bvpezK/scratch/bashcheck.sh, /tmp/plan-capture.bvpezK/scratch/bashcheck2.sh, /tmp/plan-capture.bvpezK/scratch/cases1.json, /tmp/plan-capture.bvpezK/scratch/cases2.json, /tmp/plan-capture.bvpezK/scratch/harness.py, /tmp/plan-capture.bvpezK/scratch/malformed.py, self/features/orchestration-record-fixes/audit-report.md | — |
| 07-review-opus | /tmp/plan-capture.rPFQpB/scratch/cases2.txt, /tmp/plan-capture.rPFQpB/scratch/probe.py, hooks/allow-repo-commands.sh, self/review-report.md | — |
| 07-audit-opus | /tmp/plan-capture.hPsVtB/scratch/b1.txt, /tmp/plan-capture.hPsVtB/scratch/b2.txt, /tmp/plan-capture.hPsVtB/scratch/b3.txt, /tmp/plan-capture.hPsVtB/scratch/b4.txt, /tmp/plan-capture.hPsVtB/scratch/bashcheck.sh, /tmp/plan-capture.hPsVtB/scratch/bashcheck2.sh, /tmp/plan-capture.hPsVtB/scratch/harness.py, /tmp/plan-capture.hPsVtB/scratch/malformed.py, /tmp/plan-capture.hPsVtB/scratch/reason.py, self/features/orchestration-record-fixes/audit-report.md | — |
| 08-review-opus | /tmp/plan-capture.3qP1ph/scratch/probe.py, /tmp/plan-capture.3qP1ph/scratch/regex.py, hooks/allow-repo-commands.sh, self/review-report.md | — |
| 08-audit-opus | /tmp/plan-capture.Dck4Sp/scratch/cases1.txt, /tmp/plan-capture.Dck4Sp/scratch/cases2.txt, /tmp/plan-capture.Dck4Sp/scratch/cases3.txt, /tmp/plan-capture.Dck4Sp/scratch/cases4.txt, /tmp/plan-capture.Dck4Sp/scratch/drive.py, /tmp/plan-capture.Dck4Sp/scratch/fuzz.py, /tmp/plan-capture.Dck4Sp/scratch/gt.py, /tmp/plan-capture.Dck4Sp/scratch/mkstub.sh, /tmp/plan-capture.Dck4Sp/scratch/one.py, /tmp/plan-capture.Dck4Sp/scratch/payloads.py, /tmp/plan-capture.Dck4Sp/scratch/probe.py, /tmp/plan-capture.Dck4Sp/scratch/probe1.txt, /tmp/plan-capture.Dck4Sp/scratch/probe2.txt, /tmp/plan-capture.Dck4Sp/scratch/reasons.py, /tmp/plan-capture.Dck4Sp/scratch/setup-base.sh, /tmp/plan-capture.Dck4Sp/scratch/setup.sh, self/features/orchestration-record-fixes/audit-report.md | — |
| 09-review-opus | /tmp/plan-capture.Ioql8Q/scratch/cmp.py, /tmp/plan-capture.Ioql8Q/scratch/probes.txt, /tmp/plan-capture.Ioql8Q/scratch/probes2.txt, hooks/allow-repo-commands.sh, self/review-report.md | — |
| 09-audit-opus | /tmp/plan-capture.28k3NN/scratch/bs.py, /tmp/plan-capture.28k3NN/scratch/cases1.jsonl, /tmp/plan-capture.28k3NN/scratch/cases2.jsonl, /tmp/plan-capture.28k3NN/scratch/cases3.jsonl, /tmp/plan-capture.28k3NN/scratch/cases4.jsonl, /tmp/plan-capture.28k3NN/scratch/fuzz.py, /tmp/plan-capture.28k3NN/scratch/run.py, /tmp/plan-capture.28k3NN/scratch/setup.sh, /tmp/plan-capture.28k3NN/scratch/unreadable.py, self/features/orchestration-record-fixes/audit-report.md | — |
| 10-review-opus | /tmp/plan-capture.8kx58o/scratch/drive.py, /tmp/plan-capture.8kx58o/scratch/judge.py, self/review-report.md | — |
| 10-audit-opus | /tmp/plan-capture.WQPPAi/scratch/build_cases.json, /tmp/plan-capture.WQPPAi/scratch/build_cases2.json, /tmp/plan-capture.WQPPAi/scratch/build_cases3.json, /tmp/plan-capture.WQPPAi/scratch/build_cases4.json, /tmp/plan-capture.WQPPAi/scratch/dbg.py, /tmp/plan-capture.WQPPAi/scratch/driver.py, /tmp/plan-capture.WQPPAi/scratch/git_cases.json, /tmp/plan-capture.WQPPAi/scratch/run.py, /tmp/plan-capture.WQPPAi/scratch/setup.sh, self/features/orchestration-record-fixes/audit-report.md | — |
| 11-review-opus | /tmp/plan-capture.lL03AR/scratch/cmp.py, /tmp/plan-capture.lL03AR/scratch/full.py, self/review-report.md | — |
| 11-audit-opus | /tmp/plan-capture.J0fADf/scratch/bashcheck.sh, /tmp/plan-capture.J0fADf/scratch/build.txt, /tmp/plan-capture.J0fADf/scratch/driver.py, /tmp/plan-capture.J0fADf/scratch/fdcheck.sh, /tmp/plan-capture.J0fADf/scratch/git.txt, /tmp/plan-capture.J0fADf/scratch/more.txt, /tmp/plan-capture.J0fADf/scratch/run_one.py, /tmp/plan-capture.J0fADf/scratch/setup.sh, self/features/orchestration-record-fixes/audit-report.md | — |
| 12-review-opus | /tmp/plan-capture.Eli1ej/scratch/cmds.txt, /tmp/plan-capture.Eli1ej/scratch/drive.py, analysis/README.md, self/review-report.md | — |
| 12-audit-opus | /tmp/plan-capture.WAcSDk/scratch/bashcheck.sh, /tmp/plan-capture.WAcSDk/scratch/build.json, /tmp/plan-capture.WAcSDk/scratch/build2.json, /tmp/plan-capture.WAcSDk/scratch/chdir.json, /tmp/plan-capture.WAcSDk/scratch/direct.py, /tmp/plan-capture.WAcSDk/scratch/flow-build.json, /tmp/plan-capture.WAcSDk/scratch/flow.json, /tmp/plan-capture.WAcSDk/scratch/git.json, /tmp/plan-capture.WAcSDk/scratch/run.py, /tmp/plan-capture.WAcSDk/scratch/setup.sh, /tmp/plan-capture.WAcSDk/scratch/unr/.git, self/features/orchestration-record-fixes/audit-report.md | — |
| 13-review-opus | /tmp/plan-capture.JqwqAl/scratch/probe.py, self/review-report.md | — |
| 13-audit-opus | /tmp/plan-capture.XlhhS3/scratch/bashcheck.py, /tmp/plan-capture.XlhhS3/scratch/cases.json, /tmp/plan-capture.XlhhS3/scratch/drive.py, /tmp/plan-capture.XlhhS3/scratch/gitcases.json, /tmp/plan-capture.XlhhS3/scratch/repeat.py, self/features/orchestration-record-fixes/audit-report.md | — |
| 14-review-opus | /tmp/plan-capture.pPA3sD/scratch/probe.py, self/review-report.md | — |
| 14-audit-opus | /tmp/plan-capture.bib6rk/scratch/cases.txt, /tmp/plan-capture.bib6rk/scratch/cases2.txt, /tmp/plan-capture.bib6rk/scratch/cases3.txt, /tmp/plan-capture.bib6rk/scratch/drive.py, /tmp/plan-capture.bib6rk/scratch/extract.sh, /tmp/plan-capture.bib6rk/scratch/mkcases.py, /tmp/plan-capture.bib6rk/scratch/real.txt, /tmp/plan-capture.bib6rk/scratch/realbash.sh, /tmp/plan-capture.bib6rk/scratch/replay.sh, self/features/orchestration-record-fixes/audit-report.md | — |
| 15-review-opus | self/review-report.md | — |
| 15-audit-opus | /tmp/plan-capture.BoD6v2/scratch/bashcheck.sh, /tmp/plan-capture.BoD6v2/scratch/cases.json, /tmp/plan-capture.BoD6v2/scratch/cases2.json, /tmp/plan-capture.BoD6v2/scratch/cases3.json, /tmp/plan-capture.BoD6v2/scratch/compare.py, /tmp/plan-capture.BoD6v2/scratch/drive.py, self/features/orchestration-record-fixes/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.28k3NN/scratch/run.py | 09-audit-opus | 09-audit-opus | 58 |
| /tmp/plan-capture.28k3NN/scratch/unreadable.py | 09-audit-opus | 09-audit-opus | 86 |
| self/features/orchestration-record-fixes/audit-report.md | 09-audit-opus | 09-audit-opus | 164 |
| /tmp/plan-capture.WQPPAi/scratch/run.py | 10-audit-opus | 10-audit-opus | 80 |
| self/review-report.md | 11-review-opus | 11-review-opus | 133 |
| /tmp/plan-capture.J0fADf/scratch/driver.py | 11-audit-opus | 11-audit-opus | 150 |
| self/features/orchestration-record-fixes/audit-report.md | 11-audit-opus | 11-audit-opus | 58 |
| /tmp/plan-capture.pPA3sD/scratch/probe.py | 14-review-opus | 14-review-opus | 48 |
| /tmp/plan-capture.pPA3sD/scratch/probe.py | 14-review-opus | 14-review-opus | 83 |
| /tmp/plan-capture.bib6rk/scratch/drive.py | 14-audit-opus | 14-audit-opus | 166 |

## Warnings

- priced from LiteLLM live (litellm-live), not from analysis/rates_history.json: claude-fable-5-2 — refresh the history with analysis/refresh_rates.py in an agentTooling self feature, then capture_planning.py --recapture this feature

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
