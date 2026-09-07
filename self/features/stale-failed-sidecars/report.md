# stale-failed-sidecars — cost and waste report

Generated 2026-09-06T15:28:10.685125+00:00.

## Cost

| bucket | usd | % of total |
|---|---|---|
| planning | $0.0000 | 0.0% |
| build | $63.6692 | 96.0% |
| verify | $0.0000 | 0.0% |
| review | $2.6316 | 4.0% |
| **total** | **$66.3008** | 100.0% |

Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), $63.6692, read from `planning.json`; there are no build plans, and the coordinator's minutes on the brief are not separated from it.

cost per plan: $66.3008  
cost per file touched: $0.0000

$2.6316 of the total above is **derived**, not measured — priced from session transcripts by recover_attempts.py for attempts the CLI itself never reported a cost for.

## Time

| bucket | minutes | usd | usd per minute |
|---|---|---|---|
| build: implementer | 2822.4 | $63.6692 | $0.0226 |
| ↳ acceptance tests | 3.2 |  |  |
| ↳ implementation | 4.9 |  |  |
| ↳ gate | 2.4 |  |  |
| verify | 0.0 | $0.0000 |  |
| review | 0.0 | $2.6316 |  |
| **total** | **2822.4** (partial) | **$66.3008** |  |

The implementer's minutes are its transcript span — its working time, since a delegate runs start to finish. Verify and review minutes are summed over plans; the wall clock below is the review runner's own record. The indented rows split that span at the implementer's own checkpoint milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry minutes and no separate dollars.

**This total is a lower bound** — at least one time input is unavailable. Missing durations for: 84-review-opus.

Wall clock, as the runner saw it: **18.2 min** from 2026-09-06T14:07:47+00:00 to 2026-09-06T14:26:01+00:00, PR opened 2026-09-06T14:26:01+00:00.
Passes: review 6.6. Gates: 0.0 min over 0 run(s). Plans as timed by the runner: 6.5 min over 1 run(s).

## Cold-start tax

0 cache-creation tokens across build/verify/review plans.

## Model fit

| model | plan count | total turns | total cost usd | minutes | flags |
|---|---|---|---|---|---|
| opus | 1 | 0 | n/a | n/a |  |

## Churn

| plan | edit count | files edited | churn ratio |
|---|---|---|---|

## Plan length vs LoC changed

| plan | plan.md lines | LoC changed |
|---|---|---|
| 84-review-opus | 117 | not computed: streams unavailable |

## Re-hunting

not computed: streams unavailable

## Plan drift

none found.

## Cross-plan edit overlap

not computed: streams unavailable

## Warnings

- plan 84-review-opus has 1 attempt(s) priced from session transcripts rather than reported by the CLI (sessions: 2e9ce097-2707-4206-9b1b-448cd112f6f9)
- no duration_ms for plan(s) 84-review-opus; excluded from the time roll-up
- plan 84-review-opus has 0 files_edited; excluded from churn ratio

---

Rates last verified 2026-09-04 (fresh as of report generation). This footnote is display-only and does not affect any figure above.
