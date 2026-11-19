Verdict: clean

# Review: harness-long-runs, round 2

## What the batch was supposed to do

Round 1 delivered four things in `harness/run.sh`:

- a time budget that exits 75 and prints a `resume:` line;
- `--reset <spec>`, behind a per-experiment lock;
- a repeatable `--only`;
- a `--from` refusal when earlier outputs are missing.

The review escalated two findings:

1. **The budget stop could loop forever.** When a cell's estimate alone exceeded the budget, the run started nothing, exited 75 and printed a `resume:` line equal to the command just run. The existing test asserted that loop.
2. **A test was missing** for round 1's local fix: `--from record` on a finished fixture cell with no worktree must not be refused.

The coordinator ruled that the first cell of every invocation always starts, with a warning when its estimate exceeds the budget. Round 2 implements that ruling, fixes the tests and updates the docs. This review covers the rework (`68ddb88..HEAD`) only.

## Does it do it

Yes.

- **The first-cell rule.** In `budget_allows_cell` (`harness/run.sh:1008`), when `i == 0` the run warns and returns 0. Otherwise it stops and builds the resume line from `CELLS[i..]`.
  - `i` is the index into the enumerated `CELLS`, the same array the main loop walks (`run.sh:1278`). No cell in that loop is skipped before `run_cell`, so `i == 0` is always the invocation's first started cell.
  - A stop therefore happens only at `i ≥ 1`. The resume line names a strict suffix of this invocation's cells: every cell not started, and none that started. It can never equal the invocation that printed it, and repeated resumes terminate.
  - The warning names the estimate and the budget.
  - Dry runs and `--time-budget 0` still bypass the check.
- **Tests.** In `harness/tests/long-runs.sh`:
  - Section 4 uses a 1-minute budget with a seeded 200-minute finished cell. It asserts that the first cell starts, the warning is printed, the run exits 75 without starting the second cell, and the resume line names only the second cell. Running the resume line with `--dry-run` appended names only the second cell.
  - Section 5 asserts the same with the 150-minute budget, and that the warning names `200` and `150m`.
  - The new section 3b asserts that `--from record` on a cell with no worktree, whose state records only a setup start, is not refused and prints no `--reset` hint. It also asserts that a row is appended. The fixture now has `facts.md`, `review-brief.md` and a gate that prints its green string, so the record stage can complete.
- **Docs.** `harness/README.md` ("Time budget"), `SPEC.md` §17 and `EXPERIMENTS.md` "Long cells" all state the first-cell rule and the warning, and they match the code. The feature README lists plan 07 and the round-2 rework.
- **Round 1's contracts.** The rework does not touch reset, the lock, exit 75 or the `--from` check. Nothing changed under `hooks/` or `.claude/`. No harness file in the rework names a model.
- **Gate.** `self/gate-report.txt` was generated at 22:36:07Z, two seconds after the rework commit (22:36:05Z). Every check passed, including `harness long-runs self-test`, and nothing was skipped. The report's captured output for that test shows only its later sections, so the individual lines for sections 3b, 4 and 5 are not visible there. The test exited 0 with "all checks passed".

## Fixed in this pass

None.

## Escalated to the next round

None.

One minor note that does not block the close: the check in section 3b named "reaches the record stage" (`out_has "record"`) would also match the words `--from record` in a refusal message, so it proves nothing by itself. The two checks around it (no refusal message, and a row appended) cover what it was meant to show.
