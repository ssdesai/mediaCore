# 04 — docs: long runs, reset, several `--only`

Feature: `harness-long-runs` — plan 4 of 4 build plans (6 in the batch). `harness/run.sh`
learns to stop safely before the 2-hour background-command kill (time budget, exit 75,
a `resume:` line), to reset a killed cell non-destructively (`--reset`), to take several
`--only` specs, and to refuse a `--from` whose earlier outputs are missing.

Document what plans 02–03 built, in the harness docs and the facts file, and record the
two exclusions in the backlog.

Depends on: 02-run-cells-budget-sonnet.md, 03-run-reset-lock-sonnet.md. Read the
behaviour from `harness/run.sh` (its header comment, `budget_allows_cell`,
`cell_estimate_seconds`, the `--reset` branch, the lock) and the constants in
`harness/lib.sh` (`HARNESS_BUDGET_STOP_RC` and its neighbours) — document what the code
does, by constant name and value; where code and this plan disagree, the code wins and you
say so in a one-line comment at the end of your final message.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- Every file here ships to every consuming repo. Never name a model. Never write a
  repo-specific path (vinylCatalogue etc.) into these files; "a real run" is enough.
- Why the reset is inside `run.sh`: a consumer's permission hook denies an agent's direct
  `git worktree move` / `git branch -m` (`LIFECYCLE.md` rule 2, lines 599-611);
  `run.sh` is one invocation the human approves, as every `run.sh` call already is (the
  hook has no rule for it and asks), and the git it runs — setup's `git worktree add`,
  `--reset`'s move and rename — is harness-run git, which the standing rules allow.
- Resuming a killed cell on its partial tree is wrong for an experiment: it invalidates
  the cold-start reading metrics (`read_files_before_edit`, `read_bytes_before_edit`,
  `readme_bytes_read`). That is why reset moves the tree aside rather than resuming.

## Files

- `harness/README.md`
- `harness/SPEC.md`
- `harness/EXPERIMENTS.md`
- `LIFECYCLE.md` (one sentence)
- `self/PROJECT_FACTS.md` (one list)
- `self/BACKLOG.md` (two entries)

## `harness/README.md`

- "Running one" (line 111): the flags — `--only` repeatable (one spec per flag; an
  unmatched spec refused), `--time-budget <minutes>` (default, `0` = off), `--reset
  <spec>` (alone, with `--consumer` only), `--from` refusing a cell whose worktree or
  setup state is missing and naming `--reset`.
- A new `## Exit codes` section after "Running one": 0, 1, 75 — what each means, and that
  75 prints the `resume:` line to run next.
- A new `## Resetting a killed cell` section: what moves where (paths and the `Killed<ts>`
  suffix), the fresh state carrying `cost_lost_usd`, what it refuses and why, the lock
  (where it lives, stale-pid takeover, dry runs skip it), that nothing is deleted or
  pushed, that `results.jsonl` rows stay as history, and the harness-run-git paragraph
  from the pinned facts. Program cells are not reset (exclusion).
- "Contents" (18-51): no new file in `harness/` except the test, which
  `harness/tests/README.md` already lists; touch it only if it lists tests one by one.

## `harness/SPEC.md`

- §2 "Command surface" (line 146): the new flags.
- A new `## 17. Long runs: the time budget, reset, several --only (added 2026-11-04)` at
  the end, mirroring §16's shape (line 800 on): the problem (fixed 2-hour kill, ~50-minute
  cells), the four behaviours, the estimate rule (longest finished cell by summed stage
  durations, default 60 minutes), exit 75, the lock's location and why not `state/`, and
  the exclusions (program-cell reset and `--from` preconditions; `run-batch.sh` — it has
  no between-plans loop, plan iteration is in `plan-runner-lib.sh`, and a killed batch
  already resumes on re-run per `RUNNER.md`).

## `harness/EXPERIMENTS.md`

A short `## Long cells` section after "Running" (line 190): when a cell runs close to an
hour, run one `run.sh` invocation per cell or per arm (`--only` each); a budget stop exits
75 and its `resume:` line is the next command; a cell killed anyway is reset with
`run.sh <exp> --reset <spec>` and re-run with `--only <spec>` — never resumed on its partial
tree (the reading-metrics reason), and never cleaned up with hand-run git.

## `LIFECYCLE.md`

At the end of rule 2's first sentence block (after "…prunes the worktree and the branch.",
line 604), add one sentence: the experiment harness is the one other way in for its own
cells — `harness/run.sh`'s setup adds a cell's worktree and `--reset` moves a killed one
aside, git the harness runs under one approved `run.sh` invocation (`harness/README.md` →
"Resetting a killed cell").

## `self/PROJECT_FACTS.md`

Lines 181-186: add `harness/tests/long-runs.sh` to the list of harness tests.

## `self/BACKLOG.md`

Read its first 30 lines for the entry shape, then append two entries (feature
`harness-long-runs`): `--reset` and the `--from` preconditions for program cells; a time
budget in `run-plans.sh` between plans (why it was left out, as in SPEC §17).
