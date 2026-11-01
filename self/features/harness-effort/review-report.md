Verdict: clean

# Review — harness-effort

## What the batch was supposed to do

Add one environment variable, `HARNESS_EFFORT`, to the experiment harness:
- validate it when `lib.sh` is sourced (empty, or one of `low medium high xhigh max`)
- append `--effort <level>` to every model call at the single seam, `harness_claude`
- show it on the dry-run lines
- record it as `effort` (a string, or JSON `null`) in both ledger row shapes
- assert all of this in `harness/tests/smoke.sh`
- document it.

## Does it do it

Yes. Checked against the diff (`git diff origin/main...HEAD`):

- **Seam.** `lib.sh` defaults `HARNESS_EFFORT` to empty and keeps the levels in a named constant, `HARNESS_EFFORT_LEVELS`. It validates right after `harness_die` is defined, at source time and before any work. The error message names the bad value and all five levels. `harness_claude` builds `effort_args` and expands it Bash-3.2-safe (`${effort_args[@]+"${effort_args[@]}"}`). The batch adds no `set -e`.
- **No bypass.** Every `claude` invocation under `harness/` goes through `harness_claude` or its session wrappers (lines 831–841): `run.sh` review and rework, `methods/direct`, `methods/plans`, and the `program-stages.sh` implementer and orchestrator turns. The method scripts are subprocesses that source `lib.sh` again. They inherit `HARNESS_EFFORT` the same way they already inherit `HARNESS_MODEL` (an environment prefix or an `export`).
- **Unset changes nothing.** `harness_effort_dry` prints nothing and `harness_claude` adds no flag. Both rows write `(if $effort == "" then null else $effort end)`, so the field is `null` when unset and never an empty string.
- **Dry runs.** The cell's method, review and rework lines and the program's orchestrator, implementer, collect, review and rework lines all carry `$(harness_effort_dry)`.
- **Tests.** `smoke.sh` covers:
  - (a) no `--effort` and `effort == null` on an ordinary dry run, an ordinary row and a program row
  - (b) `--effort max` on the method, review and rework dry-run lines, at least 6 hits on the program dry run, and a real `--from rework` run whose argv log carries `--effort max` and whose row records `"max"`
  - (c) `HARNESS_EFFORT=huge` exits non-zero and names the value and the levels.

  The gate report shows every check green, including `harness smoke test`, and no check is SKIPPED.
- **Docs.** `harness/README.md` covers the `lib.sh` entry, the environment-variable paragraph, and both row shapes plus the `effort` gloss. `harness/SPEC.md` covers the cell row field list and the program cell. `harness/tests/README.md` describes the new assertions. They all name the same five levels and the same empty default as the code.
- **Scope.** `scorecard.py` does not print `model`, so it correctly did not change. The batch added no model identifier and touched nothing under `.claude/`, `self/orchestrations/` or another feature's folder.

## Fixed in this pass

- `harness/SPEC.md` §"`claude -p` flags present in this install" listed the CLI flags the harness relies on but not the new `--effort`. I added `--effort <level>` to that list and noted that `harness_claude` supplies it from `HARNESS_EFFORT`. This is a doc-only change.

## Escalated

None.

## Notes (not findings, nothing to act on)

- The full-run assertion is `grep -q -- '--effort max'` over the argv log, so it shows that at least one call carried the flag, not that every call did. Under `--from rework` the null method makes no model call, so the log holds only the harness's own calls. Every call does carry the flag, because the flag is added at the single seam that all calls go through. A tighter assertion ("no logged line lacks `--effort max`") would be cheap if a later batch touches this test.
- That assertion picks the row with `sed -n 4p`, which ties it to the row count earlier in the script. It holds today, because the gate is green.
