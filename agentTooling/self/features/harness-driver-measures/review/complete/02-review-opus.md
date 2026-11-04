# 02 — review: harness-driver-measures (round 2)

Round 1 (`review-report.md` before this round, `escalations/01-review-opus.md`) ended
`Verdict: escalated`: the implementation was sound, it fixed a leftover variable
replacement in `harness_gate_counts` and added the `T1e` guard, and it escalated one gap —
nothing tested that a `no-pr` resume re-captures the method's cost. Judge this round
against the spec below, not against the builder's report. "No findings" is a legitimate
verdict (AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

Principle: the arm's own `agentTooling/` only builds; the harness (the driver — the copy
`harness/run.sh` lives in) does all measuring and bookkeeping. Items: (1) literal template
fill under bash 5.2 `patsub_replacement`, no `${x//pat/$var}` left in the harness;
(2) cost capture and report from the driver's `analysis/` via `--arm-root`, old arms'
feature directories not breaking it; (3) driver's `forge.sh` pointed at the arm's origin
(`FORGE_CHECKOUT`), harness opens a missing PR for a built, pushed branch and records
`pr_opened_by_harness` plus an intervention, a failed or empty method is still
`method_failed`; (4) an unresolved `base` is fetched once by sha in `check-fixture.sh` and
`run.sh` setup; (5) `run.sh <exp> --from review` on a cell recorded `no-pr`/`method_failed`
runs only the PR step, never the method, records the field and intervention, and
re-captures the method's cost with the driver's rates, with a test.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff. The round-2 change is the commit `test that a no-pr resume
recaptures the method cost`: a log line in `capture_one` (`harness/run.sh`) and two
assertions in `harness/tests/smoke.sh` section 9c2c.

## Contracts to hold it to

- The round-1 escalation is closed: the resume's cost re-capture is asserted, and the
  assertion fails if `RECAPTURE_METHOD` or the `elif` branch in `capture_one` is removed.
  (The fake sessions price nothing, so no frozen record exists to compare; the log line
  naming the method's slug, and only that slug, is the observable. Judge whether that is
  enough, and whether the log text could be produced without the `--recapture` flag
  actually being passed — if so say how to tie them.)
- Everything round 1 held to still holds: `forge.sh` backward compatible; `--arm-root`
  only the ordinary artifact root, usage error with `--self`; bash 3.2 rules; READMEs
  current for `harness/`, `harness/tests/`, `analysis/`, `self/tests/`; out-of-scope files
  (method templates) untouched; tests non-vacuous.
- Known limitation, not a finding: `git fetch origin <abbreviated sha>` generally fails
  against GitHub.

## Verdict

The first line of the report is `Verdict: clean` or `Verdict: escalated`, followed by
findings (file, line, gap, fix).
