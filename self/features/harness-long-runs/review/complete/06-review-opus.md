# 06 — review: harness-long-runs

Read the diff against the spec below and judge it. Do not re-run tests, start a server or
build fixtures: the gate and the verify pass already ran (`self/gate-report.txt`). If a
question can only be settled by running something, say so and move on. **"No findings" is
a legitimate verdict** — report `Verdict: clean` when the escalated list is empty; do not
invent speculative findings. Phrase every finding you can as a missing assertion (the
test that would hold it forever), and keep two lists: fixed here, escalated.

## What the feature was supposed to do

A background command in a Claude Code session is killed at a fixed 2 hours; harness cells
run ~50 minutes, so a multi-cell experiment cannot finish in one `harness/run.sh`
invocation. A real run (vinylCatalogue, discogsPrefillStructure) was killed mid-implementer
and left a cell that could only be cleaned up by hand-run, ref-moving git. The feature:

1. **Time budget in `harness/run.sh`.** It notes its start time; before starting each
   cell it checks elapsed + estimated cell duration against a budget. When that does not
   fit it starts nothing, prints the exact command that resumes the remaining cells, and
   exits with a distinct, documented exit code (not 0 and not the failed-cell code).
   Budget defaults to about 110 minutes and is overridable by a flag. The estimate is the
   longest duration among this experiment's already-completed cells, falling back to a
   documented default (about 60 minutes). The same rule applies to `run-batch.sh` between
   plans only if it fits naturally — the manifest says whether it was done and why.
2. **`run.sh <exp> --reset <cell-id>`.** Moves the cell's worktree aside to a sibling path
   with a `Killed<UTC timestamp>` suffix, renames the cell's branch the same way, and
   moves the cell's state file aside so the next `--only <cell>` run starts from setup. It
   never deletes and never pushes. It refuses when the cell has a completed record row,
   when a harness run for this experiment is in progress (existing lock), or when the cell
   does not exist. Rows already in `results.jsonl` stay as history; unpriced cost from the
   killed window stays reachable the way `cost_lost_usd` already works. The reset lives
   inside the harness and is reached only as a `run.sh` invocation — the consumer's hook
   denies an agent's direct `git worktree move` / `git branch -m`, and the hook must not
   be widened to allow it.
3. **`--only` accepts several cells** (repeated or comma-separated, one chosen and
   documented); anything it cannot apply is refused, never silently dropped.
4. **`--from <stage>` refuses** a cell whose earlier stages' outputs are missing (e.g. no
   worktree for `--from method`), naming `--reset` or a run from setup, instead of
   recording a failed row.

Excluded (the manifest's "Deliberately excluded" says why): any change to `hooks/` (the
policy), any change to `plans/experiments/` in any repo, any deletion of a worktree,
branch or row; `--reset` and the `--from` preconditions for **program** cells (refused /
unchanged); a time budget in `run-batch.sh` / `run-plans.sh`. Design choices the batch
made, to judge rather than re-litigate: `--only` is repeated (not comma-separated);
`--reset` takes the same `<fixture>:<method>[:<arm>]:<n>` spec as `--only` and must match
exactly one cell; the budget-stop code is 75; the lock is a `mkdir` lock under the
consumer's git common dir (`harness-locks/<experiment>.lock/pid`), not `state/`, because
`state/` is committed; the cell estimate sums stage durations; the reset prices an open
killed window before the move (transcripts are filed by tree path) and carries
`cost_lost_usd` into a fresh state file.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **Exit codes**: the budget-stop code is distinct from 0, from the failed-cell code and
  from every code `harness/run.sh` already used; it is named as a constant and documented
  in `harness/README.md`. The resume command printed is copy-pasteable and resumes exactly
  the cells not yet run (no completed cell re-run, none dropped).
- **Reset is non-destructive and harness-run**: no `rm`, `git worktree remove`,
  `git branch -D`, `git push` or `git reset` on the reset path; `git worktree move` and
  `git branch -m` run by `run.sh` itself; refusals happen before any move; a partial
  failure (worktree moved, branch rename failed) is reported, not hidden.
- **The lock**: `--reset` takes or checks the same lock an ordinary run takes, and does not
  leave it held.
- **`--only`**: every requested cell either runs or is refused with its name; an unknown
  cell id is an error, as before.
- **`--from` refusal** writes no row to `results.jsonl`.
- **No regression** of the existing run path: `--from setup` behaviour,
  `HARNESS_ALLOW_EXISTING_BRANCH`, program cells, the record stage's worktree removal.
- **bash 3.2, `set -uo pipefail` without `set -e`**, named constants for every magic value
  (budget minutes, default estimate, exit code, the `Killed` suffix) —
  `self/PROJECT_FACTS.md` → "Conventions and gotchas" and `CONVENTIONS.md` → "Named
  constants".
- **Tests**: a new `harness/tests/` script using throwaway git repos, registered in
  `self/gate.sh`, that runs the reset **through `run.sh`** (not raw git) and covers each
  refusal, the multi-cell `--only`, the `--from` refusal and the budget stop's exit code
  and resume line. It is listed in `harness/tests/README.md`.
- **Docs**: `harness/README.md` (flags, exit codes, reset), `harness/SPEC.md`,
  `harness/EXPERIMENTS.md` ("long cells": one invocation per cell or per arm, how to
  resume and reset; and that a `--reset` run by a session is harness-run git, which the
  standing rules allow). `self/PROJECT_FACTS.md` updated if a fact it pins changed. No
  committed file names a model.

## Verdict
