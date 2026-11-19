# hook-audit-gaps — cost and waste report

Generated 2026-11-16T03:50:02.591622+00:00.

Profile: cloud — where the feature was started (env-profile.sh).
Gate: green — the base gate at the start (green, or skipped: --no-gate or no gate script).

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $327.3647 | 92.8% |
| verify | $0.0000 | 0.0% |
| review | $25.4622 | 7.2% |
| **total** | **$352.8269** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $327.3647, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $25.2019  
cost per file touched: $3.7140

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 5412.8 | $327.3647 | $0.0605 |
| ↳ acceptance tests | 2.9 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 71.3 | $25.4622 | $0.3572 |
| **total** | **5484.0** | **$352.8269** | $0.0643 |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

Wall clock, as the runner saw it: **2947.5 min** from 2026-11-14T02:42:28+00:00 to 2026-11-16T03:50:00+00:00, PR opened 2026-11-16T03:50:00+00:00.
Passes: review 72.0. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 89.0 min over 14 run(s).

## Rounds

| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $327.3647 † | 5412.8 † | $0.0000 | 0.0 | $5.1793 | 15.1 | 01-review-opus | escalated | escalations/01-review-opus.md |
| 2 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $4.1851 | 10.4 | 02-review-opus | escalated | escalations/02-review-opus.md |
| 3 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $3.2755 | 9.0 | 03-review-opus | clean | — |
| 4 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $3.6264 | 11.1 | 04-review-opus | clean | — |
| 5 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $4.6200 | 15.2 | 05-review-opus | clean | — |
| 6 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.1734 | 4.4 | 06-review-opus | escalated | escalations/06-review-opus.md |
| 7 | $0.0000 † | 0.0 † | $0.0000 | 0.0 | $2.4025 | 6.2 | 07-review-opus | clean | — |

† build: the build is the implementer's transcript, priced as one figure, and its `checkpoint` stamps span rounds 1, 2 — one figure cannot be divided between them, so all of it sits in round 1

A round is build → gate → verify → review, ending in that review's verdict (`agentTooling/LIFECYCLE.md`). Dollars and minutes are the same figures the Cost and Time tables carry, partitioned by the `round` each stamp in `timing.jsonl` records; a stamp written before rounds existed is round 1. The verdict is the review plan's own `plan_end` stamp, and an escalated round links the brief the rework was written from.

## Cold-start tax

1370000 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 14 | 529 | $25.4622 | 71.3 |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|
| 01-review-opus | 9 | 5 | 1.80 |
| 01-audit-opus | 15 | 15 | 1.00 |
| 02-review-opus | 6 | 4 | 1.50 |
| 02-audit-opus | 14 | 10 | 1.40 |
| 03-review-opus | 1 | 1 | 1.00 |
| 03-audit-opus | 16 | 13 | 1.23 |
| 04-review-opus | 1 | 1 | 1.00 |
| 04-audit-opus | 18 | 14 | 1.29 |
| 05-review-opus | 2 | 2 | 1.00 |
| 05-audit-opus | 30 | 23 | 1.30 |
| 06-review-opus | 3 | 3 | 1.00 |
| 06-audit-opus | 8 | 7 | 1.14 |
| 07-review-opus | 1 | 1 | 1.00 |
| 07-audit-opus | 13 | 9 | 1.44 |

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 01-review-opus | 99 | 107 |
| 01-audit-opus | 39 | 1022 |
| 02-review-opus | 79 | 205 |
| 02-audit-opus | 39 | 568 |
| 03-review-opus | 81 | 103 |
| 03-audit-opus | 39 | 646 |
| 04-review-opus | 76 | 83 |
| 04-audit-opus | 39 | 820 |
| 05-review-opus | 88 | 88 |
| 05-audit-opus | 39 | 780 |
| 06-review-opus | 79 | 117 |
| 06-audit-opus | 39 | 283 |
| 07-review-opus | 98 | 90 |
| 07-audit-opus | 39 | 356 |

## Re-hunting

| target | tool | plans |
|---|---|---|
| `/home/user/agentTooling/hooks/README.md` | Read | 01-review-opus, 02-review-opus, 05-audit-opus, 05-review-opus, 06-audit-opus, 06-review-opus |
| `/home/user/agentTooling/hooks/allow-repo-commands.sh` | Read | 01-review-opus, 02-review-opus, 03-review-opus, 04-review-opus, 05-review-opus, 06-audit-opus, 06-review-opus |
| `/home/user/agentTooling/self/BACKLOG.md` | Read | 03-audit-opus, 07-audit-opus |
| `/home/user/agentTooling/self/features/hook-audit-gaps/NOTES.md` | Read | 02-review-opus, 03-audit-opus, 03-review-opus, 04-review-opus |
| `/home/user/agentTooling/self/features/hook-audit-gaps/audit-report.md` | Read | 03-audit-opus, 05-review-opus, 06-audit-opus, 07-audit-opus |
| `/home/user/agentTooling/self/gate-report.txt` | Read | 02-review-opus, 03-review-opus, 05-review-opus, 06-review-opus |
| `/home/user/agentTooling/self/tests/allow-repo-commands.sh` | Read | 01-audit-opus, 01-review-opus, 04-audit-opus, 05-audit-opus, 06-review-opus |
| `/home/user/agentTooling/self/tests/hook-cloud-profile.sh` | Read | 01-audit-opus, 03-audit-opus, 07-audit-opus |

## Plan drift

| plan | edited not listed | listed not edited |
|---|---|---|
| 01-review-opus | /tmp/plan-capture.T3Oeht/scratch/b.sh, /tmp/plan-capture.T3Oeht/scratch/probe.py, hooks/allow-repo-commands.sh, self/review-report.md, self/tests/allow-repo-commands.sh | — |
| 01-audit-opus | /tmp/plan-capture.jxnxd2/scratch/attack.py, /tmp/plan-capture.jxnxd2/scratch/broken-main/.git, /tmp/plan-capture.jxnxd2/scratch/c1.json, /tmp/plan-capture.jxnxd2/scratch/c2.json, /tmp/plan-capture.jxnxd2/scratch/c3.json, /tmp/plan-capture.jxnxd2/scratch/c4.json, /tmp/plan-capture.jxnxd2/scratch/c5.json, /tmp/plan-capture.jxnxd2/scratch/c6.json, /tmp/plan-capture.jxnxd2/scratch/c7.json, /tmp/plan-capture.jxnxd2/scratch/cloud.py, /tmp/plan-capture.jxnxd2/scratch/funcs.py, /tmp/plan-capture.jxnxd2/scratch/orch.py, /tmp/plan-capture.jxnxd2/scratch/setup.sh, /tmp/plan-capture.jxnxd2/scratch/table.py, self/features/hook-audit-gaps/audit-report.md | — |
| 02-review-opus | /tmp/plan-capture.ZpsxqO/scratch/probe.py, /tmp/plan-capture.ZpsxqO/scratch/probe2.py, /tmp/plan-capture.ZpsxqO/scratch/probe3.py, self/review-report.md | — |
| 02-audit-opus | /tmp/plan-capture.1N7PKN/scratch/c1.py, /tmp/plan-capture.1N7PKN/scratch/c2.py, /tmp/plan-capture.1N7PKN/scratch/c3.py, /tmp/plan-capture.1N7PKN/scratch/c4.py, /tmp/plan-capture.1N7PKN/scratch/c5.py, /tmp/plan-capture.1N7PKN/scratch/drive.py, /tmp/plan-capture.1N7PKN/scratch/fakegit.sh, /tmp/plan-capture.1N7PKN/scratch/oracle.py, /tmp/plan-capture.1N7PKN/scratch/setup.sh, self/features/hook-audit-gaps/audit-report.md | — |
| 03-review-opus | self/review-report.md | — |
| 03-audit-opus | ../../../tmp/plan-capture.f6AOGg/scratch/head/.git/agenttooling-orchestrators, /tmp/plan-capture.f6AOGg/scratch/cases_a.py, /tmp/plan-capture.f6AOGg/scratch/cases_b.py, /tmp/plan-capture.f6AOGg/scratch/cases_c.py, /tmp/plan-capture.f6AOGg/scratch/cases_d.py, /tmp/plan-capture.f6AOGg/scratch/cases_e.py, /tmp/plan-capture.f6AOGg/scratch/cases_f.py, /tmp/plan-capture.f6AOGg/scratch/cases_g.py, /tmp/plan-capture.f6AOGg/scratch/drive.py, /tmp/plan-capture.f6AOGg/scratch/main/.git/agenttooling-orchestrators, /tmp/plan-capture.f6AOGg/scratch/manifest_attack.py, /tmp/plan-capture.f6AOGg/scratch/setup.sh, self/features/hook-audit-gaps/audit-report.md | — |
| 04-review-opus | self/review-report.md | — |
| 04-audit-opus | /tmp/plan-capture.gWC4xo/scratch/a8.cmd, /tmp/plan-capture.gWC4xo/scratch/a8.sh, /tmp/plan-capture.gWC4xo/scratch/c1.py, /tmp/plan-capture.gWC4xo/scratch/c2.py, /tmp/plan-capture.gWC4xo/scratch/c3.py, /tmp/plan-capture.gWC4xo/scratch/c4.py, /tmp/plan-capture.gWC4xo/scratch/dbg.py, /tmp/plan-capture.gWC4xo/scratch/filt.py, /tmp/plan-capture.gWC4xo/scratch/gen.py, /tmp/plan-capture.gWC4xo/scratch/h.py, /tmp/plan-capture.gWC4xo/scratch/orch.py, /tmp/plan-capture.gWC4xo/scratch/own.py, /tmp/plan-capture.gWC4xo/scratch/setup.sh, self/features/hook-audit-gaps/audit-report.md | — |
| 05-review-opus | hooks/README.md, self/review-report.md | — |
| 05-audit-opus | /tmp/plan-capture.2JOmcw/scratch/brun.py, /tmp/plan-capture.2JOmcw/scratch/c1.py, /tmp/plan-capture.2JOmcw/scratch/c10.py, /tmp/plan-capture.2JOmcw/scratch/c11.py, /tmp/plan-capture.2JOmcw/scratch/c2.py, /tmp/plan-capture.2JOmcw/scratch/c3.py, /tmp/plan-capture.2JOmcw/scratch/c4.py, /tmp/plan-capture.2JOmcw/scratch/c5.py, /tmp/plan-capture.2JOmcw/scratch/c6.py, /tmp/plan-capture.2JOmcw/scratch/c7.py, /tmp/plan-capture.2JOmcw/scratch/c8.py, /tmp/plan-capture.2JOmcw/scratch/c9.py, /tmp/plan-capture.2JOmcw/scratch/cmp.sh, /tmp/plan-capture.2JOmcw/scratch/drive.py, /tmp/plan-capture.2JOmcw/scratch/evaltest.sh, /tmp/plan-capture.2JOmcw/scratch/fakebin/gh, /tmp/plan-capture.2JOmcw/scratch/fakebin/git, /tmp/plan-capture.2JOmcw/scratch/fuzz.py, /tmp/plan-capture.2JOmcw/scratch/ledger.py, /tmp/plan-capture.2JOmcw/scratch/o1.json, /tmp/plan-capture.2JOmcw/scratch/orch.py, /tmp/plan-capture.2JOmcw/scratch/run/run-plans.sh, self/features/hook-audit-gaps/audit-report.md | — |
| 06-review-opus | /tmp/plan-capture.LhElCj/scratch/probe.py, hooks/README.md, self/review-report.md | — |
| 06-audit-opus | /tmp/plan-capture.16MsYN/scratch/cases/c1.json, /tmp/plan-capture.16MsYN/scratch/cases/c2.json, /tmp/plan-capture.16MsYN/scratch/cases/c3.json, /tmp/plan-capture.16MsYN/scratch/cases/c4.json, /tmp/plan-capture.16MsYN/scratch/run.py, /tmp/plan-capture.16MsYN/scratch/setup.sh, self/features/hook-audit-gaps/audit-report.md | — |
| 07-review-opus | self/review-report.md | — |
| 07-audit-opus | /tmp/plan-capture.RfRNpw/scratch/c1.txt, /tmp/plan-capture.RfRNpw/scratch/c2.txt, /tmp/plan-capture.RfRNpw/scratch/c3.txt, /tmp/plan-capture.RfRNpw/scratch/c4.txt, /tmp/plan-capture.RfRNpw/scratch/c5.txt, /tmp/plan-capture.RfRNpw/scratch/raw.py, /tmp/plan-capture.RfRNpw/scratch/run.py, /tmp/plan-capture.RfRNpw/scratch/variants.py, self/features/hook-audit-gaps/audit-report.md | — |

## Cross-plan edit overlap

| file | earlier plan | later plan | overlap chars |
|---|---|---|---|
| /tmp/plan-capture.T3Oeht/scratch/probe.py | 01-review-opus | 01-review-opus | 346 |
| self/tests/allow-repo-commands.sh | 01-review-opus | 01-review-opus | 352 |
| /tmp/plan-capture.ZpsxqO/scratch/probe3.py | 02-review-opus | 02-review-opus | 45 |
| /tmp/plan-capture.ZpsxqO/scratch/probe.py | 02-review-opus | 02-review-opus | 51 |
| /tmp/plan-capture.1N7PKN/scratch/drive.py | 02-audit-opus | 02-audit-opus | 223 |
| /tmp/plan-capture.1N7PKN/scratch/drive.py | 02-audit-opus | 02-audit-opus | 71 |
| /tmp/plan-capture.1N7PKN/scratch/drive.py | 02-audit-opus | 02-audit-opus | 264 |
| /tmp/plan-capture.1N7PKN/scratch/drive.py | 02-audit-opus | 02-audit-opus | 56 |
| /tmp/plan-capture.f6AOGg/scratch/drive.py | 03-audit-opus | 03-audit-opus | 50 |
| /tmp/plan-capture.f6AOGg/scratch/drive.py | 03-audit-opus | 03-audit-opus | 87 |
| /tmp/plan-capture.2JOmcw/scratch/drive.py | 05-audit-opus | 05-audit-opus | 122 |
| /tmp/plan-capture.2JOmcw/scratch/drive.py | 05-audit-opus | 05-audit-opus | 67 |
| /tmp/plan-capture.2JOmcw/scratch/fuzz.py | 05-audit-opus | 05-audit-opus | 49 |
| /tmp/plan-capture.2JOmcw/scratch/fuzz.py | 05-audit-opus | 05-audit-opus | 88 |
| /tmp/plan-capture.2JOmcw/scratch/drive.py | 05-audit-opus | 05-audit-opus | 45 |
| /tmp/plan-capture.RfRNpw/scratch/run.py | 07-audit-opus | 07-audit-opus | 139 |
| /tmp/plan-capture.RfRNpw/scratch/run.py | 07-audit-opus | 07-audit-opus | 41 |

## Warnings

- priced from LiteLLM live (litellm-live), not from analysis/rates_history.json: claude-fable-5-2 — refresh the history with analysis/refresh_rates.py in an agentTooling self feature, then capture_planning.py --recapture this feature

---

Rates from `analysis/rates_history.json`, last checked 2026-10-13 (stale as of report generation). This footnote is display-only and does not affect any figure above.
