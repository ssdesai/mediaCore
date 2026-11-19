# 02 — run.sh: several `--only`, `--from` preconditions, the time budget

Feature: `harness-long-runs` — plan 2 of 4 build plans (6 in the batch). `harness/run.sh`
learns to stop safely before the 2-hour background-command kill, to reset a killed cell
(`--reset`, plan 03), to take several `--only` specs, and to refuse a `--from` whose earlier
outputs are missing.

Make `--only` repeatable, enumerate the selected cells before running any, refuse an
unmatched spec and an unmet `--from` up front, and stop with exit 75 and a `resume:` line
when the next cell would not fit the time budget.

Independent of 03 (03 builds on the enumeration this plan adds; it runs after). The
contract is `harness/tests/long-runs.sh` (plan 01) — read it before editing; cases 1–5 are
this plan's.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- bash 3.2, `set -uo pipefail`, no `set -e` (use `if …; then …; fi`, not `cond && cmd`,
  where status matters); no associative arrays, no `mapfile`; empty arrays expand as
  `${a[@]+"${a[@]}"}` (see `harness/lib.sh:648`). Every magic value a named constant.
- `harness/run.sh` today: args 29-56 (`ONLY` is a scalar, so a second `--only` overwrites);
  `--from` validated 74-79; `usage()` 37-40 prints header lines `3,20` of the file — if the
  header grows, update that range; `stage_wanted` 118-127; `resolve_cell` 133-185 (sets
  `BRANCH TREE STATE SLUG REPO_PATH`); `resume_no_pr` 413-416 and `ensure_resume_trees`
  434-451 (the one path that re-creates a missing tree: `--from review` on a cell recorded
  `no-pr`); `run_cell` 878-919; `cell_selected` 921-941; the two cell loops 956-989
  (fixture cells, then program cells via `resolve_program_cell` /
  `run_program_cell` in `harness/program-stages.sh`); summary and exits 991-1002.
- Re-running `run.sh` re-runs every selected cell; nothing skips a finished one. So the
  resume line must name the remaining cells explicitly.
- `harness_utc_now` (`lib.sh:215`) writes `%Y-%m-%dT%H:%M:%SZ`, which jq's
  `fromdateiso8601` parses. State `stages.<name>.start/end` use it
  (`run.sh:129-130`); a finished cell has `.stages.record.outcome == "ok"`.
- Exit codes in use: 0, 1 (`harness_die`, failures), and method-internal 0/1/2
  (`lib.sh:123-125`). 64 is reserved by the plan runners. The budget stop is 75.

## Files

- Modify `harness/lib.sh` — constants only, next to `METHOD_*_RC` (`lib.sh:123-125`):

```bash
# Time budget: a Claude Code background command is killed at 2 hours, so a run stops
# before a cell that would not finish inside the budget (harness/README.md → "Exit codes").
HARNESS_BUDGET_STOP_RC=75
HARNESS_TIME_BUDGET_MINUTES_DEFAULT=110
HARNESS_CELL_ESTIMATE_MINUTES_DEFAULT=60
HARNESS_RESUME_LINE_PREFIX="resume: "
HARNESS_STAGE_OK="ok"
```

- Modify `harness/run.sh`.

## `harness/run.sh`

1. **Arguments.** Replace `ONLY` with an array `ONLY_SPECS=()`; `--only` appends (one spec
   per flag — the spec syntax already uses `:`, so no comma splitting). Add
   `--time-budget <minutes>` → `TIME_BUDGET_MIN` (default the lib constant; must match
   `^[0-9]+$` else `harness_die`; `0` disables the budget). Record
   `RUN_START_EPOCH="$(date -u +%s)"` right after parsing. Update the header comment (lines
   7-9) and the `usage` range.
2. **`cell_selected`** takes the same four arguments, returns 0 when `ONLY_SPECS` is empty
   or any spec matches (factor today's single-spec parse into `spec_matches <spec> …`),
   and marks each matching spec's index in a parallel array `SPEC_HITS`. It must run in
   the main shell (no `$(…)`), or the marks are lost.
3. **Enumerate, then drive.** Turn the two loops (956-989) into one enumeration pass that
   appends a line per selected cell to an array `CELLS`:
   `"<kind> <fixture-or-program> <method> <repeat> <arm_label> <arm_sha>"`, kind `fixture`
   or `program`, keeping the `read -u 3` here-string idiom. Then:
   - any spec with no hit → `harness_die` naming every unmatched spec;
   - a `--from` precondition pass (not in a dry run, `FROM_STAGE` set and not `setup`):
     for each fixture cell, `resolve_cell` and require that `$STATE` exists with a
     non-empty `t_setup_start` and that `$TREE` is a directory — except when
     `FROM_STAGE == review` and `resume_no_pr`, which re-creates the tree. Collect every
     failure, then `harness_die` once with one line per cell naming its branch and what is
     missing, plus: `reset it with: <run.sh> <exp> --reset <spec>, or run it from setup
     (drop --from)`. No state file may be created by this pass (resolve_cell does not
     create one; `run_cell`'s `harness_state_init` does — keep it that way). Program cells
     keep today's `--from` behaviour (excluded — see the manifest);
   - the drive loop over `CELLS` by index: in a non-dry run, call `budget_allows_cell <i>`
     first; then resolve and run exactly as the loops do today.
4. **`cell_spec <kind> <fixture> <method> <repeat> <arm_label>`** prints
   `<fixture>:<method>[:<arm>]:<repeat>` (no arm part when the label is `-`); used for the
   resume line (and by plan 03).
5. **`cell_estimate_seconds`**: the max, over `"$STATE_DIR"/*.json` files (none → the
   default), of those with `.stages.record.outcome == HARNESS_STAGE_OK`, of
   `[.stages[] | select(.start and .end and .start != "" and .end != "") |
   (.end|fromdateiso8601) - (.start|fromdateiso8601)] | add`. One `jq -s` call; a file
   jq cannot parse must not abort the run (fall back to the default, `harness_warn`).
   The sum of stage durations, not `record.end - setup.start`: a `--from` resume rewrites
   only the stages it re-ran, so the span would count the gap between attempts.
6. **`budget_allows_cell <i>`**: returns 0 when `TIME_BUDGET_MIN == 0` or
   `elapsed + estimate <= TIME_BUDGET_MIN*60`. Otherwise it prints, then exits
   `HARNESS_BUDGET_STOP_RC`:
   - `time budget: <elapsed>m elapsed + <estimate>m (longest finished cell, or the
     default) > <budget>m — starting nothing more` (minutes rounded up);
   - `<failures> cell(s) did not finish` when `failures > 0`;
   - one line `${HARNESS_RESUME_LINE_PREFIX}<command>`: `$0`, the experiment argument as
     given, `--consumer <CONSUMER_ROOT>`, `--from` / `--no-cleanup` / `--time-budget` when
     given, then `--only <cell_spec>` for every cell from index `i` on — each word
     `printf '%q'`-quoted, space-joined, on one line.
7. **Summary** (997-1002) unchanged in wording; exits unchanged.
