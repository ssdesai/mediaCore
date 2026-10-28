Verdict: clean

# Review — detached-at-branch-tip-attach

## What the batch was supposed to do

A cloud session created to continue an existing feature branch came up with HEAD detached
exactly at `origin/<branch>`, with the cached local `<branch>` a stale ancestor. The hook
refused `git checkout -B` (rule 2), the commit steps refuse a detached HEAD, and a fresh
session reproduced the state, so the session was stuck. The feature lets the session
re-attach only when doing so moves nothing. It adds `attach-branch.sh`, a matching
`attachable_branches` reading in `plan-runner-roots.sh` and `attachable_branch` in the
hook, an attach remedy in the hook's cloud refusal reasons and in `session-start.sh`,
tests, and docs.

## Does it do it

Yes. What I checked against the brief's contracts:

- **`attach-branch.sh`** acts only when all four conditions hold: HEAD is detached, the
  branch is a tracked manifest's `branches[0]`, `origin/<branch>` is HEAD's commit, and
  the local ref is absent or an ancestor of HEAD. The `update-ref` is a compare-and-swap,
  including when the ref is absent (an empty old value means "must not exist"). The
  checkout then goes to HEAD's own commit, so the working tree and any uncommitted edit
  stay as they are (T1d asserts the edit survives). Every other refusal happens before any
  ref is written. I found one state where it did move a ref, the worktree case under
  "Fixed in this pass", and fixed it.
- **The hook.**
  - The local path is unchanged and runs no git: `profile_is_cloud()` is checked before
    any probe in `git_denial`.
  - `detached_switch_moves` is reached only through `cloud_refuses`, so only in the
    cloud.
  - A file checkout is never refused there: `checkout_leaves` returns False for `--`, a
    path flag, or more than one positional.
  - A target git cannot resolve is not refused.
  - Exceptions in `cloud_refuses` still read as "not refused". The reworked
    `cloud_git_deny_reason` wraps every probe and always returns a reason. No exception
    path turns a refusal into an allow.
  - The attach reason is returned only when `attachable_branch` finds a branch. It names
    only the feature branch and never mentions `main` or a start (A1/A5–A7 assert both
    directions).
- **One reading.** `attachable_branches` (shell) and `attachable_branch` (Python) use the
  same candidate source:
  - `for-each-ref --points-at HEAD refs/remotes/origin`, with `lstrip=3` and `HEAD`
    skipped;
  - the same manifest lookup (`started_features_on` / `started_feature`, both over
    tracked manifests' `branches[0]`);
  - the same check on the local ref: exists, then `merge-base --is-ancestor`.

  The only difference is sort order (`sort` follows the locale, `sorted` does not). It
  changes only which candidate is named first when there are several. Both callers then
  pass the branch explicitly, so it is harmless.
- **The rulings in NOTES.md** are sound.
  - Leaving `-B`/`-C`/`branch -f` refused is correct: they are prefix deny rules in the
    settings, which the hook cannot override.
  - The script prompts rather than being auto-approved, which follows the entry-point
    list's own rule (anything that moves a ref prompts).
  - Reversing `cloud-off-branch-remedy` ruling 4 is an amended invariant, and it is
    stated as one. It is narrow: on a detached HEAD, only a switch whose target resolves
    to another commit is refused. O7 was flipped to assert the new behaviour, and O7b
    keeps the local answer.
- **`session-start.sh`** still uses git only and no network. The probe runs only on a
  detached HEAD in the cloud, after the "started on this branch" check. C7a–c and R1
  (fixtures stay clean) cover it.
- **The gate**: `self/gate-report.txt` is green and lists no SKIPPED checks. The new
  `attach-branch.sh` and its test are registered in `self/gate.sh` and
  `self/tests/README.md`.

## Fixed in this pass

1. **`attach-branch.sh` could move a branch another worktree has checked out.**
   `git update-ref` is plumbing and does not check worktrees. Suppose the stale local
   `<branch>` was checked out in a second worktree, which is a valid ancestor state. The
   script would move that worktree's branch ref under it, leaving its files behind its
   HEAD. The following `git checkout` would then fail ("already checked out"), so the
   script would refuse after a ref had moved. That breaks the contract "changes no ref
   and no file on any refusal".
   - **The fix:** before the `update-ref`, the script refuses when
     `git worktree list --porcelain` shows `branch refs/heads/<target>`. The prefix is a
     named constant, `WORKTREE_BRANCH_LINE_PREFIX`.
   - **New test:** R6 in `self/tests/attach-branch.sh` builds that state and asserts the
     script refuses with HEAD, the ref and the current branch unmoved. I ran the test
     file after the change: all assertions pass, R6 included.
   - **Docs:** `self/tests/README.md` (R1–R6) and the root `README.md` `attach-branch.sh`
     row.
2. **A stale cross-reference.** The comment on `plan-runner-roots.sh`'s
   `attachable_branches` named the hook's twin as `attachable()`. The function is
   `attachable_branch`, and the comment now says so.

## Escalated

None.

One thing I am noting rather than escalating. Because of the new worktree guard, the
script refuses a state that `attachable_branches` and the hook still call attachable. In
that rare case the hook's reason sends the agent to the script, and the script refuses
with a clear reason and changes nothing. Folding the worktree check into both readings
would add a probe to the hook's refusal path, which the X5 probe counts pin. That is a
design choice for a later round if the case is ever seen, not a defect.
