Verdict: clean

# Review — harness-ablation-methods

## What the batch was supposed to do

Get the experiment harness ready for a tooling-ablation experiment. The methods now form a ladder: `vanilla` → `vanilla-conv` → `direct-bare` → `direct` → `plans`. The batch adds:

- two new methods. `vanilla-conv` is a minimal brief with no doctrine, run with the tree's conventions and hook live. `vanilla` uses the same brief, with the `CONVENTIONS.md` imports and the `.claude/settings.json` `hooks`/`permissions` taken out for the build. Those files are kept skip-worktree, verified against the build's commits, and restored on exit.
- a drift guard, `self/tests/vanilla-pair.sh`.
- an acceptance probe at PR-open (`accept_pr_open_pass` / `accept_pr_open_lines`).
- scorecard changes: failed runs are left out of cost means and band lines, and the Per cell table gains Failed, Spend and Mean wall to green. There is a new `## Acceptance` section.
- updates to the docs that describe all of this.

## Does it do it

Yes. I checked the diff (`origin/main...HEAD`, 24 files) against each contract in the brief:

- **Method contract.** Both `run.sh` take `<tree> <brief> <slug>` and exit 0/1/2. Each makes one `harness_claude` call with `$TREE` as the working directory. `vanilla-conv/run.sh` is `direct/run.sh` with only the name changed. `vanilla/run.sh` is `vanilla-conv/run.sh` plus its `# vanilla-only` lines. Test 2b/2c holds both pairs.
- **Neutralization.**
  - The `EXIT` trap is installed before `vanilla_neutralize`, so a neutralize that fails partway is still restored. `TERM`/`INT` become exits, so the trap runs on those too.
  - The list of changed files is kept per worktree, in the git dir (`git rev-parse --git-path`). A leftover list is restored before a new neutralization starts.
  - `vanilla_restore` clears the bits and checks the files out from HEAD.
  - Program cells don't go through `settle_pr`, so program feature rows are unchanged, as specified.
- **Templates.** The two are byte-identical, every placeholder fills, and both contain no doctrine (1a–1e). They are also added to `arm-spec.sh`'s template list.
- **`accept_pr_open_pass` false vs null.** `state_json_or_null` now uses `has($k)` instead of `// null`, so a `false` reaches the row as `false`. Its other three callers are the reading-metrics integers, and the change has no effect on them.
- **Scorecard.** `finished()` removes `method_failed` rows from the cost means, spreads and both comparison loops. `mean_minutes` already did the same for time. In the discogsPrefillStructure shape (one failed $0 row in an arm), the band line is now a tie (scorecard-accept). `scorecard-programs.cells.md` is unchanged, and its byte-identity check passes.
- **Gate and docs.**
  - `self/gate.sh` runs both new tests, and `bash -n` now covers `harness/methods/*/*.sh`.
  - Every new file is listed in its folder's README.
  - The SPEC, README, EXPERIMENTS and methods README entries match the code.
  - New magic values are named constants.

`self/gate-report.txt` has no SKIPPED or failing check.

## Fixed in this pass

1. **The Acceptance section rendered for an experiment run with the accept stage off, showing "Pass at green 0/N".**
   - **Where:** `harness/scorecard.py`, `render_accept`.
   - **Cause:** it decided to render the section on whether the `accept_pr_open_pass` key was present. Every row `run.sh` now writes carries that key, as `null` when accept is off. Such rows also carry `accept_pass: false` (its initial value, not a measured result).
   - **Effect:** a `--no-accept` experiment got an Acceptance section reporting every run as failing at green.
   - **Fix:** the section now renders only when some row has a boolean `accept_pr_open_pass` value. That is what the docstring and `harness/README.md` ("when any row measured PR-open") already said.
   - **Test:** a new case in `harness/tests/scorecard-accept.sh` uses a ledger whose rows carry the fields as `null` and expects no section. It fails on the old code. Its entry in `harness/tests/README.md` is updated.
2. **Two contract clauses had no test.** Both are added to `self/tests/vanilla-pair.sh` and to its entry in `self/tests/README.md`:
   - **4g:** a build that clears the bit and commits a neutralized file makes `vanilla/run.sh` exit 1, name the file, and leave no bit or list behind. Before this, test 2d only counted the `# vanilla-only` lines, so deleting the `vanilla_verify … || exit` line kept the gate green.
   - **4h:** when `run.sh` gets TERM during the build, it exits 143 and the tree is still restored. The fake `claude` signals its grandparent rather than using `setsid`, which macOS does not ship (the same reason `gate-resume.sh` avoids it).

I re-ran the two edited tests and `scorecard-programs.sh`, and all passed. I did not re-run the whole gate.

## Escalated to the next round

None.

## Note (not a finding)

`vanilla_restore` runs only when `run.sh` exits or on the next neutralization. Suppose a `vanilla` method is killed with SIGKILL, so no trap runs, and the cell is then forced past the method with `--from review`. The review would then run on a neutralized tree. That combination takes a manual `--from` after a hard kill, and the next `vanilla` run of that tree restores it first. It belongs to the operator's runbook, not to this batch.
