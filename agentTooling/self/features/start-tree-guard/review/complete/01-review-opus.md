# 01 — review: start-tree-guard

Review the feature below against its spec and the contracts listed. "No findings" is a
legitimate verdict; report only defects you can show.

## What the feature was supposed to do

`feature-start.sh` had two defects in the cloud layout. (1) The `<slug>: start` commit ran
`git add <feature dir> && git commit`, and a plain commit takes the WHOLE index, so
anything an implementer had staged landed inside it, contradicting the header's own claim
that the start commit only ever adds the feature directory. (2) Nothing noticed a tree that
changed while the base gate ran, so the gate could judge a tree that no longer existed.

The feature must deliver:

1. The start commit is made with the feature directory as its pathspec
   (`git commit -q -m "<slug>: start" -- <feature dir>`), so anything else staged or
   modified before the commit is exactly as staged or modified after it, in both profiles.
2. `git status --porcelain` of the worktree is snapshotted just before the setup hook and
   gate, compared after the gate and before the manifest is written. A difference outside
   the feature directory (the gate report excluded by name) is a refusal, in the fresh AND
   the resumed start, naming up to `DIRTY_PATHS_NAMED` paths, saying the gate judged a tree
   that no longer exists and that the changes are to be committed with a `<slug>:` subject
   or edited back, then the start run again (it resumes). The lock stays, as every refusal
   leaves it; the existing `refuse` helper and message style are kept.
3. `self/tests/start-tree-guard.sh` (C1–C4: resumed start keeps staged/modified files out of
   the commit; a gate editing a tracked file is refused naming it, no commit, lock left;
   the same command resumes after the change is committed; a gate touching only the
   feature directory or the gate report is not refused), registered in `self/gate.sh` and
   `self/tests/README.md`.
4. `templates/plans/ORCHESTRATOR_BRIEF.md` → "Branch" tells the implementer to run the
   start in the background, output captured to a file in the scratchpad, and wait for its
   exit notification before touching the tree ("Your first command in the repo is exactly"
   and the refusal sentence kept); `self/tests/orchestrator-brief.sh` asserts it;
   `feature-start.sh`'s header, `LIFECYCLE.md`'s cloud-start paragraph, `ORCHESTRATION.md`
   → "Cloud sessions" and `self/tests/README.md` describe it.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- bash 3.2, no `set -e`, named constants, no `$NAME` shapes the PreToolUse hook denies in
  the scripts' own docs; `bash -n feature-start.sh` clean.
- The snapshot comparison must not refuse a start whose only change is inside the feature
  directory (a gate writing there) or the gate report, and must not be skipped on RESUME.
  Check the path filtering against git's porcelain forms: untracked directories reported
  with a trailing slash, renames (`R  old -> new`), quoted paths with spaces, and a
  worktree whose repo is a subdirectory of the checkout (`REL_REPO`).
- Known limit to judge, not necessarily fix: `git status --porcelain` shows status, not
  content, so a file modified before the hook and modified further during the gate is not
  detected. Say whether the spec's wording requires more.
- The pathspec commit must work when the feature directory holds only new, untracked files
  (it is `git add`ed first) and in the local profile's worktree.
- The refusal leaves the lock and exits `REFUSED_RC` through `refuse`; nothing deleted.
- The new test must fail without the fix: reason through C1 (without the pathspec the
  staged file lands in the start commit) and C2 (without the snapshot the start succeeds).
- READMEs of every touched folder still describe their folder (`self/tests/README.md`
  entries for `start-tree-guard.sh` and `orchestrator-brief.sh`; Rule 2 dependency named).
- `self/gate.sh` ends `=== gate: done — all checks passed ===` on the branch.

## Verdict

State `Verdict: clean` or `Verdict: escalated` on its own line, followed by the findings
(file:line, the failing input, the wrong output) for an escalation.
