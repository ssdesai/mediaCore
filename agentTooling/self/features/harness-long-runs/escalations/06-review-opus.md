Verdict: escalated

# Review: harness-long-runs

## What the batch was supposed to do

Make `harness/run.sh` survive Claude Code's 2-hour kill on background commands. That meant
four things:

- a time budget that stops before a cell that will not fit, exits 75 and prints a `resume:` line;
- `--reset <spec>`, which moves a killed cell's worktree, branch and state aside under a
  `Killed<UTC ts>` suffix, run by `run.sh` itself under a per-experiment lock;
- a repeatable `--only`;
- a `--from` refusal for cells whose earlier outputs are missing.

The docs, a new `harness/tests/long-runs.sh` and its registration in the gate were part of
the same scope.

## Does it do it

Mostly, yes. I reviewed the code changes as uncommitted working-tree changes against `HEAD`.
`origin/main...HEAD` holds only the plan files.

- **Reset.** It deletes nothing. There is no `rm` of a tree, no `worktree remove`, no
  `branch -D`, no `push` and no `reset`. All refusals happen before any move. A partial
  failure reports what moved and what did not, through `reset_stop`. The lock is taken
  before the checks and released by the EXIT trap. An open window is priced before the
  move, and `cost_lost_usd` is carried into the fresh state.
- **Lock.** It sits under the git common dir and is shared by real runs and resets. Dry
  runs skip it. A stale lock is replaced.
- **`--only`.** It is a union, and a spec that matches nothing is refused by name.
- **Exit code and constants.** 75 is a named constant and is documented. The `Killed`
  suffix, budget and estimate are also named constants. The code stays within bash 3.2:
  no `"${arr[@]}"` on an array that can be empty.
- **Docs and tests.** `harness/README.md`, `SPEC.md` §17, `EXPERIMENTS.md` "Long cells",
  `tests/README.md`, `PROJECT_FACTS.md`, the `self/gate.sh` registration and the backlog
  entries for program cells and `run-plans.sh` are all present. The gate is green, with
  `harness long-runs self-test` passing.

## Fixed in this pass

1. **Regression: `--from record` on a finished fixture cell was refused.**
   - *What was wrong.* The new `--from` check in `harness/run.sh` required a worktree for
     every stage past setup. The `record` stage rebuilds the row from the state file alone:
     `build_ledger_row` reads only `$STATE`, and its cleanup only warns when the tree is
     missing. A finished cell's own record stage removes the tree by default, so
     `--from record` on such a cell used to work and was now refused.
   - *Why it was a dead end.* The refusal pointed at `--reset`, and `--reset` refuses any
     cell with a completed row.
   - *Fix.* `record` is now exempt from the worktree requirement only. The state file and
     the setup start are still required. `harness/README.md` and `SPEC.md` §17 say so.
2. **The `next:` line after a reset was not copy-pasteable from another directory.**
   Neither was the `reset it with:` hint in the `--from` refusal: both left out
   `--consumer`. They now carry `--consumer <root>`, as the budget stop's `resume:` line
   already did. The README wording is updated to match.
3. **Doc drift on exit 75.** A budget stop exits 75 even when an earlier cell of the same
   run failed (it prints `<n> cell(s) did not finish`). The "Exit codes" section said
   nothing about this, so 75 read as "everything before the stop succeeded". The README
   now says otherwise.

The edits were syntax-checked (`bash -n harness/run.sh`). The gate was not re-run after
them.

## Escalated to the next round

1. **The budget stop can loop forever before the first cell.** *(Design decision.)*
   - *What happens.* `budget_allows_cell` runs before cell 0 as well. If the estimate alone
     exceeds the budget, the run starts nothing, exits 75 and prints a `resume:` line equal
     to the command that was just run. Re-running that line repeats the same stop forever,
     and a driver that treats 75 as "run the resume line" never makes progress.
   - *How it arises in normal use.* The estimate is the longest finished cell. Any of these
     is enough:
     - a cell that starts at elapsed ≈ 0 and finishes in 111–119 minutes (allowed under
       the 2-hour kill);
     - a cell finished across two invocations with `--from`, whose summed stage durations
       pass 110;
     - a `--time-budget` smaller than the longest cell.
   - *The test asserts the loop.* `harness/tests/long-runs.sh` section 5 builds exactly
     this case: a 200-minute cell, a 150-minute budget, and the run is expected to exit 75
     with no cell started.
   - *Options.* Either always start the first cell of an invocation, with a warning that
     it may be killed, or die with a distinct message and no `resume:` line (for example
     "the longest cell, Nm, exceeds the budget; pass `--time-budget 0` or a larger
     budget").
   - *Missing assertion.* When the estimate is larger than the budget and no cell has run
     in this invocation, `run.sh` does not exit 75 with a `resume:` line identical to its
     own arguments. Section 5 then needs a second finished cell, or an elapsed-time setup,
     to keep testing a mid-run stop.
2. **Missing assertion for fix 1 above.** Add to `harness/tests/long-runs.sh`: a fixture
   cell with a state file that has `t_setup_start` and no worktree, run with
   `--from record --only <spec>`, is not refused by the precondition. No `--reset` hint is
   printed, and the record stage runs, appending a row. No test covers `--from record` on a
   fixture cell today; `smoke.sh` covers it only for program cells, which the check skips.
   I did not run this case, per this pass's rules.

## Not verified

Nothing was skipped in the gate. The gate's verdict covers the code before the three local
edits above. The next gate run covers them.
