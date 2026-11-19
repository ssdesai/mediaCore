# 01 — tests: harness long runs

Feature: `harness-long-runs` — plan 1 of 4 build plans (6 in the batch). `harness/run.sh`
learns to stop safely before the 2-hour background-command kill (a time budget with a
resume line and exit 75), to reset a killed cell non-destructively (`--reset`), to take
several `--only` specs, and to refuse a `--from` whose earlier outputs are missing.

Write the black-box test for all of it as a new `harness/tests/long-runs.sh`, driven only
through `harness/run.sh`, and register it in the gate. It is red until plans 02–03 land;
that is expected.

Independent of other plans (02 and 03 implement what this asserts).

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- Shell: bash 3.2, `set -uo pipefail`, no `set -e`; no associative arrays; empty arrays
  expand as `${a[@]+"${a[@]}"}`. Named constants at the top of the file for every magic
  value (`CONVENTIONS.md` → "Named constants").
- Mirror the house test shape of `harness/tests/arm-base.sh:1-58` (header, constants,
  `pass`/`fail`/`check` helpers, `WORK` from `mktemp -d "${TMPDIR:-/tmp}/long-runs.XXXXXX"`,
  cleanup trap, final `=== long-runs: all checks passed ===` line, exit 1 on any failure).
- The throwaway consumer: mirror the minimum of `harness/tests/smoke.sh` 300-442 (consumer
  repo with `plans/experiments/fixtures/<fixture>/fixture.json`, a spec, an experiment
  dir with `experiment.json` including a `prediction`, `git init`, commit, bare remote,
  `agentTooling` symlinked to this checkout) and the exports at 558-568
  (`HARNESS_CLAUDE_BIN`, `HARNESS_FORGE_BIN`, `HARNESS_AGENT_TOOLING_URL`,
  `HARNESS_TEST_EXTERNAL_DRIVER=1`). No test case runs a model stage, so the stub
  `claude` can be a script that exits 1. Use method `null`, no arms, `repeats: 2`: the
  experiment then has two cells, specs `<fixture>:null:1` and `<fixture>:null:2`.
- Cell identity: branch `harness_branch_name <stem> null <n> 2 ""` (`harness/lib.sh:250-260`
  — compute it by sourcing nothing; read that function and write the two expected names
  as constants), worktree `<consumer repo path>-<branch>` (`lib.sh:616`), state file
  `<experiment-dir>/state/<branch>.json`, ledger `<experiment-dir>/results.jsonl`, a row's
  cell key is `.branch`.
- Contracts plans 02–03 implement (assert exactly these):
  - budget stop exit code **75**; it prints one line beginning `resume: ` holding a
    command with one `--only <fixture>:null:<n>` per cell not yet started; flag
    `--time-budget <minutes>` (`0` = no budget); default estimate 60 minutes when no cell
    has finished; a finished cell is a state file with `.stages.record.outcome == "ok"`,
    its duration the sum over `.stages[]` of `end - start` (ISO `YYYY-MM-DDTHH:MM:SSZ`).
  - `--only` may be repeated; a spec that matches no cell is refused (non-zero exit, the
    spec named in the output) before any cell starts.
  - `--from <stage>` other than `setup` on a cell with no worktree is refused before any
    cell starts: non-zero exit, output contains `--reset`, no row appended.
  - lock: directory `<git common dir of the consumer>/harness-locks/<basename of the
    experiment dir>.lock/` holding a file `pid`; a live pid refuses a run or a reset
    (non-zero, output contains `in progress`); a dead pid is stale and taken over; the
    lock is gone after the process exits; `--dry-run` ignores it.
  - `--reset <spec>`: spec must match exactly one cell; moves worktree to
    `<repo>-<branch>Killed<YYYYMMDDTHHMMSSZ>`, renames the branch to
    `<branch>Killed<same ts>`, moves the state file to
    `<experiment-dir>/state/killed/<branch>Killed<ts>.json`, then writes a fresh
    `state/<branch>.json` holding only `cost_lost_usd` (the old state's value carried, a
    number) and `interventions` (one entry). Never deletes, never pushes, leaves
    `results.jsonl` byte-for-byte unchanged. Refuses (non-zero, nothing moved) when a row
    in `results.jsonl` has that `.branch` and `.method_failed != true`; when the lock is
    held live; when the spec matches no cell or several; when the cell has no worktree, no
    branch and no state ("nothing to reset"). `--reset` with `--only`, `--from`,
    `--dry-run` or `--time-budget` is a usage error.

## Files

- Create `harness/tests/long-runs.sh` (executable bit is set by the verify pass; write
  the shebang `#!/usr/bin/env bash`).
- Modify `self/gate.sh`.
- Modify `harness/tests/README.md`.

## `harness/tests/long-runs.sh`

One `setup_consumer` function builds a fresh consumer under `WORK/<case>` so cases do not
share state; a `make_cell_on_disk <n>` helper creates the branch with one commit and its
worktree via `git worktree add -b`, one untracked file in it, and a state file
`{"t_setup_start":"…","cost_lost_usd":1.25,"stages":{"setup":{…}}}`. Run `run.sh` as
`"$RUN" "$EXP" --consumer "$REPO" … > "$out" 2>&1; rc=$?`. Cases, one `check` or more each:

1. `--dry-run --only F:null:1 --only F:null:2` exits 0 and its output names both branches;
   `--dry-run --only F:null:1` names only the first.
2. `--only F:null:1 --only nosuch` (not a dry run) exits non-zero, output contains
   `nosuch`, no `state/` file for either cell exists afterwards.
3. `--from method --only F:null:1` with a state file but no worktree: non-zero, output
   contains `--reset`, `results.jsonl` absent (or unchanged if pre-seeded), state file
   byte-identical.
4. `--time-budget 59`, no state files: exit 75, a `resume: ` line containing
   `--only F:null:1` and `--only F:null:2`, no state file created, lock dir gone.
5. A finished cell's state file (any name, e.g. `state/doneNull.json`, stages summing to
   200 minutes, record outcome `ok`) and `--time-budget 150`: exit 75 (60 would fit), and
   the output contains `200`.
6. `--reset F:null:1` on a cell from `make_cell_on_disk 1`, with `results.jsonl` holding
   one row `{"branch":"<branch1>","method_failed":true}`: exit 0; old worktree path gone;
   exactly one `<repo>-<branch1>Killed*` dir, holding the untracked file and on branch
   `<branch1>Killed*` (`git -C … branch --show-current`); no local `<branch1>`; the
   commit still reachable; `state/killed/<branch1>Killed*.json` exists; new
   `state/<branch1>.json` has `.cost_lost_usd == 1.25`, no `.t_setup_start`, no `.stages`,
   one intervention; `results.jsonl` unchanged (`cmp` with a copy); lock dir gone.
7. Reset refused when `results.jsonl` has `{"branch":"<branch1>","method_failed":false}`:
   non-zero, worktree and branch untouched.
8. Reset refused under a live lock (write the test's own `$$` as the pid): non-zero,
   output contains `in progress`, nothing moved. With a dead pid (start `true &`, `wait`,
   use `$!`): exit 0.
9. Ordinary run refused under a live lock: `--only F:null:1` non-zero, no state created;
   the same with `--dry-run` exits 0.
10. Reset refusals: `--reset nosuch:null:1` (no cell), `--reset F:null` (two cells —
    output names both branches), `--reset F:null:2` with nothing on disk (output contains
    `nothing to reset`) — each non-zero.
11. `--reset F:null:1 --only F:null:1` and `--reset F:null:1 --from method`: non-zero.

## `self/gate.sh`

Add `record "harness long-runs self-test" bash harness/tests/long-runs.sh` beside the other
harness tests (lines 539-551, before smoke), and correct the stale count in the comment
above them (it says "five tests") to the real number.

## `harness/tests/README.md`

Add a row to the file table (lines 3-12) for `long-runs.sh`: what it asserts, offline, a
few seconds. Update the gate paragraph (14-18) — the count and the step name.
