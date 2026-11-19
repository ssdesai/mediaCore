feature: @@SLUG@@

Implement one feature in the repository at the worktree below, make its gate pass, commit,
push, and open the PR. **One shot — you will not be resumed.** Nobody is listening while
you work: decide anything the spec leaves open yourself and do not stop to ask.

- Worktree: `@@TREE@@`, branch `@@BRANCH@@`, off `@@BASE@@`. Call it `<tree>`. This is
  **not** the cwd you start in — use absolute paths or `cd` inside each bash call.

@@ISOLATION@@

## The spec

`@@SPEC_TREE@@/@@SPEC_PATH@@`, sections **@@SPEC_SECTIONS@@** — read-only, @@SPEC_PROVENANCE@@. This is what to build.

## The facts of this feature and this worktree

@@FACTS@@

## Finish

1. `cd <tree> && @@GATE_COMMAND@@`, re-run until the verdict line is green (about
   @@GATE_MINUTES@@ minutes per run). A SKIPPED check is not green.
2. Commit on `@@BRANCH@@`, push to `origin`, and open the PR against `main`: write the body
   to a file outside the tree, then
   `<tree>/agentTooling/forge.sh pr-open @@BRANCH@@ main '@@SLUG@@' <body file>` — it works
   on a laptop and in a Claude Code cloud container alike, where `gh pr create` is refused.
   Title: `@@SLUG@@`. The body's **first line** must read:
   *one arm of an experiment — do not merge until it picks a winner*.

## Final report, terse

The PR URL; the gate's verdict line; anything in scope you did not finish and why.
