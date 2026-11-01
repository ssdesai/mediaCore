# 01 — review: harness-effort

Review the branch against the spec below, not against any builder's report. "No findings"
is a legitimate verdict; report only what you can show from the diff.

## What the feature was supposed to do

The experiment harness (`harness/`) passes `--model "$HARNESS_MODEL"` on model calls but had
no effort seam. The feature adds one environment variable, `HARNESS_EFFORT`, applied at the
single seam every model call goes through and recorded in both ledger row shapes:

1. `harness/lib.sh`: `HARNESS_EFFORT="${HARNESS_EFFORT:-}"` beside `HARNESS_MODEL`; empty
   means the CLI default. When non-empty it must be one of `low medium high xhigh max` (a
   named constant); anything else is a `harness_die` naming the value and the levels, at
   the point the harness first reads it. `harness_claude` appends `--effort "$HARNESS_EFFORT"`
   to every call when set, so no call site changes. The dry-run lines in `harness/run.sh`
   and `harness/program-stages.sh` show `--effort <level>` when set and nothing when not.
2. The cell row (`run.sh`) and the program row (`program-stages.sh`) gain `effort` beside
   `model`: the level as a string, or `null` when unset. `harness/README.md` ("File
   shapes", "The program row") and `harness/SPEC.md` say so. `scorecard.py` changes only
   if it already prints `model` beside rows.
3. `harness/tests/smoke.sh` asserts: (a) an ordinary dry run shows no `--effort` and the
   row's `effort` is `null`; (b) a dry run under `HARNESS_EFFORT=max` shows `--effort max`
   on the method, review and rework lines, and a full run under it writes a row with
   `effort == "max"`; (c) `HARNESS_EFFORT=huge` makes the dry run exit non-zero naming the
   levels. Every pre-existing assertion still passes.
4. Docs: `harness/README.md` environment-variable paragraph, `harness/SPEC.md`,
   `harness/tests/README.md`, and the README of every folder touched.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Bash 3.2; `set -uo pipefail` with no `set -e`; no unguarded empty-array expansion under
  `set -u` (use `${a[@]+"${a[@]}"}`); named constants for the level list.
- Unset or empty `HARNESS_EFFORT` changes nothing: no flag on any call, `effort: null`.
- Every call that goes through `harness_claude` (method, orchestrator turns, implementers,
  review, rework) carries the flag; check there is no direct `claude` invocation that
  bypasses the seam within `harness/`.
- Validation runs once the harness is sourced, before any work, and the message names the
  bad value and all five levels.
- The row field is JSON `null` when unset, a string otherwise — not an empty string.
- Docs list the same five levels and the same default as the code; no README or SPEC row
  shape omits `effort`.
- No model identifier is added to any committed file beyond `HARNESS_MODEL`'s existing
  default.
- Nothing under `.claude/`, another feature's folder, or `self/orchestrations/` is touched.

## Verdict

First line of the report: `Verdict: clean` or `Verdict: escalated`. Fix local findings in
the pass; escalate structural ones.
