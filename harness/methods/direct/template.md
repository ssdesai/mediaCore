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
2. Commit on `@@BRANCH@@`, push to `origin`, and open the PR against `main` with
   `gh pr create --base main --head @@BRANCH@@`. Title: `@@SLUG@@`. The body's **first
   line** must read: *one arm of an experiment — do not merge until it picks a winner*.
   Then summarise what landed and every design call you made.

## Final report, terse

The PR URL; the gate's verdict line and its test counts; files added/changed; each
design call and where you recorded it; anything in scope you did not finish and why.
