feature: @@SLUG@@

You are the sole implementer of one feature. You author no plans and run no batch: you
implement it directly, run the gate yourself until it is green, commit, push, and open
the PR. **One shot — you will not be resumed.**

- Worktree: `@@TREE@@`, branch `@@BRANCH@@`, off `@@BASE@@`. Call it `<tree>`. This is
  **not** the cwd you start in — use absolute paths or `cd` inside each bash call.

@@ISOLATION@@

## Read, in this order

1. `@@SPEC_TREE@@/@@SPEC_PATH@@`, sections **@@SPEC_SECTIONS@@** — read-only, checked
   out detached at the commit this experiment pins. This is the spec you implement. It
   pins names; use them exactly.
2. `<tree>/CLAUDE.md` (it imports `agentTooling/CONVENTIONS.md` — the README rules and
   the named-constants rule are binding on this diff).
3. `<tree>/plans/PROJECT_FACTS.md` — the repo facts this change has to respect.
4. The READMEs of the folders you will touch, before adding to any of them. They are the
   index; follow them rather than grepping. Amend the ones your change makes untrue.

## The facts of this feature and this worktree

@@FACTS@@

## Procedure

Per `agentTooling/AGENT_DIRECT.md` → "The procedure". The two steps that matter most,
and the ones a one-shot skips when left to itself:

- **Slice it and keep the checkpoint.** Before your first edit, write
  `<tree>/plans/features/@@SLUG@@/CHECKPOINT.md` per `AGENT_DIRECT.md` → "Checkpoint
  and resume" — status, slices, learned, resume — and rewrite it at every milestone,
  its `updated:` line from `date -u '+%Y-%m-%dT%H:%M:%SZ'` and never guessed. At each
  milestone also run `./agentTooling/stamp-timing.sh @@SLUG@@ checkpoint
  status=<status>`, which is what lets the cost report split your span into tests,
  build and gate. You will not be resumed in this experiment; the checkpoint is part
  of the method and of its cost, and an arm without it measures a different method.
- **Acceptance tests first.** Before any implementation, write the black-box tests the
  spec implies — through the real routes, CLI and disk, against the contract fixtures
  where the repo has them, never against internals. They stay red until the end.
  Commit them on their own (`@@SLUG@@: acceptance tests`) before implementing.

## Quality bar

- Tests mirror the source tree and this repo's naming; every new test file gets its row
  in the tests README.
- Named constants for every magic value (`CONVENTIONS.md` → Code style): paths,
  timeouts, labels, limits.
- READMEs updated for every folder you touch, before you call it done — field lists for
  cross-module shapes (Rule 1) and the contracts that are not visible at an import line
  (Rule 2).
- Everything the spec leaves open is yours to decide. Decide it, record it where a
  reader will find it (the README you touched, and your report), and do not stop to ask.
  Only abandon if the repo or toolchain is broken in a way you cannot fix.

## Finish

1. `cd <tree> && @@GATE_COMMAND@@`, re-run until the verdict line is green (about
   @@GATE_MINUTES@@ minutes per run). A SKIPPED check is not green.
2. Commit on `@@BRANCH@@` (`CHECKPOINT.md` at status `committed`), push to `origin`,
   and open the PR against `main` with
   `gh pr create --base main --head @@BRANCH@@`. Title: `@@SLUG@@`. The body's **first
   line** must read: *one arm of an experiment — do not merge until it picks a winner*.
   Then summarise what landed and every design call you made.

## Final report, terse

The PR URL; the gate's verdict line and its test counts; files added/changed; each
design call and where you recorded it; anything in scope you did not finish and why.
