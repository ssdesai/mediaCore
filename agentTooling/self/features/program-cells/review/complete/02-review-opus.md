# 02 — review: program-cells (round 2)

## What the feature was supposed to do

The driver for `kind: "program"` ledger rows in the experiment harness: a headless
orchestrator session (`--session-id`, `--resume` per feature and once for the record), one
top-level implementer `claude -p` per feature in its own worktree, dependent features cut at
the previous feature's branch tip, `cost_overhead_usd` priced with the driver's analysis copy,
a version floor, `orchestrator` a reserved method name, the ordinary-cell path unchanged.
The contract is `harness/README.md` → "The program row" and
`harness/tests/scorecard-programs.sh`.

Round 1 escalated three items (`escalations/01-review-opus.md`); this round judges whether
each is fixed, and re-reads the whole diff for anything the fixes broke:

1. `features[].unpriced_reason` must be produced when a feature's captured cost cannot be
   trusted (manifest absent; captured far below the cost `claude` reported), and null
   otherwise; docs must say what the code does; a smoke assertion proves it.
2. The smoke test must check the program row's arithmetic with non-zero figures
   (`cost_group_usd`, `cost_group_green_usd`, per-feature `cost_green_usd`, `overhead_pct`).
   A check whose figures are all zero proves nothing — say so if that is what was built.
3. A killed first orchestrator call must be resumable: a persisted marker, a fresh session
   id on re-entry, the old id still priced, an intervention recorded, and the behaviour
   listed among the assumptions to rehearse.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Everything round 1's brief held it to (the row's fields and arithmetic, ordinary cells
  byte-for-byte, state resume, isolation, `program.json` rules, bash 3.2 and no `set -e`,
  named constants, docs matching code, smoke assertions that can fail).
- The new state keys are in the README field lists (Rule 1) and the SPEC §13 state-key list.
- No test the previous round passed has been weakened or removed.

Local findings you fix in the pass; structural ones you escalate. "No findings" is a
legitimate verdict.

## Verdict

First line of the report: `Verdict: clean` or `Verdict: escalated`.
