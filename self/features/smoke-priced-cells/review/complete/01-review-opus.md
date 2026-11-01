# 01 — review: smoke-priced-cells

Review the diff against the spec below. Do not trust any builder report; read the code.
"No findings" is a legitimate verdict.

## What the feature was supposed to do

Two assertions added to `harness/tests/smoke.sh`, nothing in the harness itself changing
(unless an assertion found a real defect — then the fix and a note in `NOTES.md`):

1. **An ordinary cell priced end to end.** A section on an experiment directory of its own
   runs the same cell shape as the ordinary full run (not a program), under the priced HOME
   with `SMOKE_PRICED_TRANSCRIPTS=1` and the `SMOKE_COST_*` variables, so the fake `claude`
   leaves a billed transcript for the implementer call and for the review and rework calls.
   It asserts on the ledger row: `cost_method_usd > 0`, `cost_review_usd > 0`,
   `cost_rework_usd > 0`; `cost_green_usd == cost_method_usd + cost_review_usd +
   cost_rework_usd` within the shared tolerance constant (renamed off its program-only
   name); `cost_method_reported_usd` equal to what the fake reported; no unpriced warning;
   and no "cannot claim" / `launched_elsewhere` line in the cell's capture log. It must
   fail if the capture's claim root (`capture_planning.py` `claim_roots`, the
   `<primary>-<branch>` tree) regresses. The program section's existing figures must still
   pass.
2. **`stages {review: false}` as a run.** An experiment on its own directory is run (the dry
   run stays) and asserts what `harness/run.sh` records when the review stage is not
   wanted: read `do_review`, `do_rework`, `do_capture` and `build_ledger_row` and check each
   asserted value (absent `stages.review`, `cost_review_usd == 0`, `review_escalated` and
   `review_fixed` at 0, `rework_ran == false`, no review prompt/manifest/findings, rework
   not run) is what the code really does, not a guess. It must fail if
   `harness_stage_enabled` regresses to `jq '.stages.x // true'`.
3. **Docs**: `harness/tests/README.md`, `harness/README.md`, `harness/EXPERIMENTS.md` (the
   rehearsal list's item 3 reworded, not deleted) describe what the smoke now proves and
   nothing false.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- The fake `claude`'s heredoc is unquoted: every runtime `$` and backtick in it is escaped,
  every build-time constant is expanded. Check each new line for the wrong one.
- The existing ordinary full run still asserts 0s and is unaffected: the new billing is
  gated on `SMOKE_PRICED_TRANSCRIPTS=1`, and the implementer branch of the fake matches
  only the `direct` brief.
- The new priced cell must price through the real paths (a pinned arm, a real vendored
  copy: an unpinned symlinked `agentTooling/` cannot be priced), not by a shortcut that
  would pass with the claim root broken.
- Named constants for every magic value (`CONVENTIONS.md` → Code style); bash 3.2, no
  `set -e`; no `$NAME` of a path variable in a form the shell policy refuses in committed
  scripts' docs.
- README rules (`CONVENTIONS.md` → READMEs): each folder touched has its README accurate;
  `harness/tests/README.md` names the new sections and the env variables the fake reads.
- No model identifier in any committed file; nothing under `.claude/` or another feature
  changed.

## Verdict

First line of the report: `Verdict: clean` or `Verdict: escalated`. Fix local findings in
the pass; escalate structural ones.
