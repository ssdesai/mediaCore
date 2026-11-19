# 01 — review: harness-scorecard-time

Review the diff below against the spec in this brief. "No findings" is a legitimate
verdict; report only defects you can demonstrate.

## What the feature was supposed to do

`harness/scorecard.py` shows time as plainly as cost, from the existing row fields
`t_setup_start`, `t_method_start`, `t_pr_open`, `t_rework_end`, `t_green` (no new row
fields, no change to `run.sh`'s timestamps):

- Runs table keeps "Wall to PR" (method start → PR open) and adds "Wall to green"
  (method start → green) and "Total" (setup start → green), in minutes via the existing
  `minutes_between`; a missing timestamp prints the NA marker.
- "Per cell" table gains mean "Wall to PR" and mean "Total" per (fixture, method, arm),
  next to the cost means. Rows with `method_failed` are left out of the time means, with a
  footnote line saying so. The section still appears under exactly the same condition as before.
- Programs section is unchanged unless the same columns fit without a contract change.
- `harness/README.md` (and `SPEC.md` where it lists scorecard columns) name the new
  columns and say times are wall-clock, including any wait or interruption inside a stage
  (a `--from` resume after a dead container spans the dead time).
- Tests in `harness/tests/`, registered in `self/gate.sh`, with no model spend: known
  values in the per-row columns and per-cell means; a failed row excluded from the time
  means; a missing timestamp renders NA.

Excluded: new row fields, `run.sh` timestamp changes, any consumer repo.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Changes only under `harness/` (code, tests, docs), the `self/gate.sh` registration and
  `self/features/harness-scorecard-time/`.
- Named constants for every literal (CONVENTIONS.md); `minutes_between` reused, not copied.
- Means are computed correctly over the non-failed rows only, and a mean over nothing or
  over unmeasurable timestamps renders NA rather than 0m or a crash.
- The ordinary-cell expected scorecard `harness/tests/scorecard-programs.cells.md` is
  regenerated (the Runs table header changed), and the other scorecard tests still pass.
- READMEs of touched folders (`harness/`, `harness/tests/`) describe the new files, columns
  and the wall-clock caveat; `./self/gate.sh` is green.

## Verdict
