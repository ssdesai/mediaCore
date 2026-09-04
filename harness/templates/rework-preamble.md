# Harness rework pass — @@FIXTURE@@

feature: @@SLUG@@-rework

You are the rework pass of an experiment harness. A review of this tree escalated the
items below. Fix every one of them, nothing else.

- Worktree: `@@TREE@@` (branch `@@BRANCH@@`) — `cd` there; this is not the cwd you
  start in, so use absolute paths or `cd` inside each bash call.
- The findings file is `@@FINDINGS@@`. It is the **only** input to this pass. It was
  written from this tree alone; no other tree was read to produce it, and you must not
  read one either.
- The spec is `@@SPEC_TREE@@/@@SPEC_PATH@@`, sections @@SPEC_SECTIONS@@ (read-only) —
  consult it when a finding's `fix:` line needs the contract to be precise.

@@ISOLATION@@

## What to do

1. Read `CLAUDE.md`, the repo's `plans/PROJECT_FACTS.md` if it has one, and the READMEs
   of every folder you will touch. This repo's conventions — named constants, README
   field lists, tests mirroring the source tree — are binding on your changes.
2. **Fix every item under `## Escalated`. Fix nothing else.** Do not refactor beyond
   them. Do not fix items under `## Fixed` — they are already done. If you notice a
   defect nobody listed, name it in your report and leave it alone.
3. A finding phrased as a missing assertion is a test to write, not a comment to add.
4. Update the READMEs for whatever you change.
5. Run the gate — `cd @@TREE@@ && @@GATE_COMMAND@@` (about @@GATE_MINUTES@@ minutes) —
   until its verdict line is green. A skipped check is not green.
6. Commit everything as **one commit** on `@@BRANCH@@` with the message
   `rework: @@FIXTURE@@`, then `git push`. No PR: one is already open for this branch.
7. Never mutate repo-wide VCS state: no `git stash`, `git checkout`, `git reset`,
   `git clean`, no branch switch, no rebase.

## Report back, terse

The commit sha; the gate's final counts; one line per finding id saying what you did;
anything you noticed and left alone.

---

## The findings

@@FINDINGS_TEXT@@
