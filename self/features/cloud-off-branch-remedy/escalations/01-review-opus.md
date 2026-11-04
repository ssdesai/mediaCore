Verdict: escalated

# Review: cloud-off-branch-remedy

## What the batch was supposed to do

Fix the advice a cloud session gets when its container was reclaimed and restarted on
`main`, without changing what the hook allows or refuses:

- the hook's cloud refusal of `git switch`/`git checkout <feature-branch>` from `main` or a
  detached HEAD now prints an off-branch reason (`GIT_CLOUD_OFF_BRANCH_TEMPLATE`): the
  container is off the feature's branch, and the fix is a fresh session on that branch or
  the human checking it out. It no longer says "Commit on `main`, push only `main`";
- `session-start.sh` prints one fixed restart line in the cloud on `main` or a detached HEAD;
- tests (`hook-cloud-profile.sh` O block, `session-start.sh` C4b–C4d) and docs
  (`hooks/README.md`, root `README.md`, `LIFECYCLE.md`, `ORCHESTRATION.md`, `NOTES.md`),
  plus the docs-only model-tiering bullet for child sessions.

## Does it do it

Mostly yes. The gate is green, and the O1–O7, C4b–C4d and X1–X4 checks all pass.

- **The allow / deny / prompt answers are unchanged.** `git_denial` hands `args` through
  to the reason and nothing more. The refusal decision (`git_mutates`,
  `names_protected_push`, `cloud_refuses`) is untouched, and the T table is unchanged.
  No carve-out was added, and `NOTES.md` ruling 1 says why.
- **The reason text is right.** The off-branch reason names the target branch, the slug, the
  manifest, a fresh session and the human. It contains neither "push only" nor
  "Commit on" (O5 asserts this).
- **The widened lookup is correct and bounded.** `started_feature(..., tree)` searches the
  target commit's tree as well as the checkout's tracked manifests. It filters
  `git grep` hits by the `<tree>:` prefix, keeps the same depth check, and reads each file
  with `git show` through the same fence reader (`manifest_lines_first_branch`). The match
  for a `checkout x` that resolves only through `origin/x` requires exactly one remote
  component. Each switch name costs at most two `rev-parse` calls, one `for-each-ref` per
  call, and up to four greps plus a `show` per hit. Each probe has the existing timeout,
  failures return None, and the whole block sits in a `try` that falls back to the
  ordinary cloud reason. Names come from the command's words, so none starts with `-`
  and none is read as a git option. The worst a manifest on a remote branch can do is
  change the reason text, never the answer.
- **`session-start.sh` stays cheap:** one fixed string, no manifest scan, read-only.
- **The docs are accurate.** One small exception goes with the finding below.

## Fixed in this pass

Nothing. I tried the one local fix below, but the write to `hooks/allow-repo-commands.sh`
was not granted in this pass, so it is listed as an escalation instead.

## Escalated to the next round

1. **The off-branch block runs a git probe on every cloud refusal, not only on a
   switch or checkout.** `hooks/allow-repo-commands.sh:1416-1424`
   (`cloud_git_deny_reason`) calls `project_root()`, `repo_shape()` and
   `checkout_state(git_location(...))` before it checks whether `args` is a switch or
   checkout. That is one `git rev-parse` subprocess, and it is a duplicate, because the
   second `try` block repeats it. Only after that does `cloud_off_branch_reason` call
   `switch_target_names(args)` and find nothing to do. So every refused cloud `git push`,
   `git reset`, `git branch -D`, … now pays one more git call. That breaks the plan's
   contract that "the new probes run only on the cloud, refused, switch/checkout path".
   It also makes the claims in `hooks/README.md` ("The extra probes run only on that
   refused path") and `NOTES.md` ruling 2 slightly untrue. The answer is not affected.
   **Fix:** a one-line guard. Wrap the body of the first `try` in
   `if switch_target_names(args):` (add the comment "Only a switch/checkout naming a
   branch is probed"). `switch_target_names(None)` already returns `[]`.
   **Missing test:** add an X-block check to `self/tests/hook-cloud-profile.sh`: under the
   logging `git` stub, a refused cloud non-switch command (e.g. `git push origin other`
   on an assigned branch) runs the same number of git calls as on `origin/main`. Today
   nothing pins that count, which is how this went in green.
