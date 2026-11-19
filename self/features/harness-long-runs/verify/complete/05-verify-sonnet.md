# 05 — verify: harness long runs

Feature: `harness-long-runs` — verify pass (plan 5 of 6). `harness/run.sh` gained a time
budget (exit 75 and a `resume:` line), `--reset <spec>`, a per-experiment lock, repeatable
`--only`, and `--from` preconditions.

Read `self/gate-report.txt` first; do not re-run the gate's checks. Then read
`harness/tests/long-runs.sh` (the batch's contract) before checking anything, and check
only what it leaves uncovered. Fix what is local; anything needing a new function or a
signature change is an escalation, written in your report.

1. If `long-runs.sh` or `smoke.sh` is red in the report, triage and fix that first; then
   re-run only the failing script. `chmod +x harness/tests/long-runs.sh` if its siblings
   are executable.
2. Uncovered by the test, and worth a case in `long-runs.sh` if each is cheap (a few
   lines, no model stage):
   - reset of a cell whose worktree holds an **open** manifest `session_window` — the
     pricing runs before the move and the carried `cost_lost_usd` is a number; mirror how
     `harness/tests/smoke.sh` stages a killed window (grep it for `cost_lost`);
   - a run whose first cell fits and whose second does not (a finished-cell state file
     making the estimate large only after the first cell is out of reach without a model
     stage — if so, say so and skip);
   - the budget stop's `resume:` line actually resumes: run it (it is one line) with
     `--dry-run` appended and confirm it names exactly the remaining cells.
3. The consumer hook: feed `hooks/allow-repo-commands.sh` a PreToolUse payload (write it
   to your scratch directory) for `./agentTooling/harness/run.sh plans/experiments/x
   --reset fooNull:null:1` and for the same with `--only` instead; confirm both get the
   same decision. Report it; do not change `hooks/`.
4. `git diff origin/main...HEAD -- hooks/ .claude/` must be empty; no committed file
   names a model.
5. `README.md` files of every touched folder name each new file
   (`python3 -B check-readme-index.py` is in the gate report — read it there).

Passing: the gate report green with `harness long-runs self-test` recorded, smoke green,
and the hook check reported.
