# 01 — review: program-cells

## What the feature was supposed to do

Add the driver that produces `kind: "program"` ledger rows for the experiment harness. A
program cell is one headless orchestrator session (`claude -p --session-id S`, then
`--resume` once per feature and once for the record) plus one top-level implementer
`claude -p` per feature, each run by the harness in that feature's own worktree with the
orchestrator's brief as its prompt. The harness starts every feature itself. The contract
it must satisfy is already merged: `harness/README.md` → "The program row" and
`harness/tests/scorecard-programs.sh`. Rulings that must hold:

- The orchestrator model is `HARNESS_MODEL`; every model call goes through `harness_claude`
  (the single seam), via `harness_claude_new_session` / `harness_claude_resume`.
- A dependent feature's branch is cut at the previous feature's branch tip as it stood when
  that implementer finished; its PR targets that branch (`pr_base`); `dependency_ok` is a
  boolean from `git merge-base --is-ancestor` for a dependent feature and absent/null
  otherwise; a dependent feature still runs after a failed predecessor.
- `cost_overhead_usd` is the orchestrator session(s) priced in `[t_method_start,
  t_method_end]` with the driver's analysis copy (`harness/program_cost.py`); the arm's own
  `report.py --orchestration` output is only `record_report`, a cross-check.
- Version floor: an arm lacking `orchestration-start.sh` or
  `templates/plans/ORCHESTRATOR_BRIEF.md` is refused at `new-experiment.sh` and at setup.
- The method name `orchestrator` is reserved; no `methods/orchestrator/`.
- A usage limit on the orchestrator waits once then resumes the same session.
- An experiment without `programs` and a ledger of ordinary cells behave byte-for-byte as before.
- No PR for the program branch; it is pushed.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

1. Every field `harness/README.md` → "The program row" lists is produced by
   `build_program_row` in `harness/program-stages.sh`, with the stated arithmetic
   (`cost_group_usd`, `cost_group_green_usd`, `overhead_pct`), JSON numbers for every dollar
   field, `features[]` in run order with 1-based `position`.
2. The ordinary-cell path is unchanged in behaviour: read the `run.sh` refactor
   (`resolve_cell` split, `setup_tree`, `START_POINT`, `GATE_RED_FATAL`) for any change a
   cell can observe. Hunt for a `$BASE`/`$START_POINT` mix-up, a global a program feature
   leaves set for the next one, and `--from` handling for ordinary cells.
3. State resume: `--from <stage>` in a fresh process re-derives everything from
   `program.json`, `experiment.json` and the state files; nothing reads an in-memory value
   of a killed process. Check the orchestrator session-id chain (most recent reported id,
   per-id first-call start for pricing).
4. Isolation: no stage reads across feature worktrees; the orchestrator is given only
   facts, specs and prior reports, never another arm's tree; the isolation paragraph is in
   the program brief. The implementer is not told to run `feature-start.sh`/`feature-close.sh`.
5. `program.json` rules are enforced wherever it is read (`harness_program_check`):
   first feature not dependent, a fixture once, same repo identity, fixture bases ignored
   with one warning, gate fallback; `new-experiment.sh` refuses existing program and
   feature branches like cells, program name disjoint from fixture names.
6. Shell conventions (`self/PROJECT_FACTS.md`): bash 3.2 (no associative arrays, empty
   arrays under `set -u`), no `set -e`, named constants for every magic value, no
   `cond && cmd` whose status matters.
7. Docs match the code: `harness/README.md`, `SPEC.md` §13, `EXPERIMENTS.md` "Program
   cells", `templates/README.md`, `tests/README.md`, `methods/README.md` — state keys,
   stage names, file shapes (field lists complete), and the three unverified assumptions.
8. The smoke sections test what they claim (a check that cannot fail is a finding).

Local findings you fix in the pass; structural ones you escalate. "No findings" is a
legitimate verdict.

## Verdict

First line of the report: `Verdict: clean` or `Verdict: escalated`.
