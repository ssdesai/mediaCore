Verdict: clean

# Review — cloud-checkpoint-push

## What the batch was supposed to do

In a Claude Code cloud container the session's `claude/…` branch is the feature's branch,
and the container is thrown away when the session ends, so any commit that was never
pushed is lost. Before this feature, only the close pushed. The batch was to:

1. push the feature's branch (`branches[0]`) after `feature-start.sh`'s start commit and
   after `run-review.sh`'s round and stamps commits, under the `cloud` profile only. These
   pushes are advisory: a failure prints one warning line and the exit status stays the same;
2. move the capture's push into one shared function in `plan-runner-roots.sh` that the
   capture and the checkpoints both call, with no retry;
3. leave the `local` profile unchanged, with no new push and no new output;
4. have `hooks/allow-repo-commands.sh` approve, in the cloud only, a plain
   `git [-C <path>] push [-u|--set-upstream] origin <B>` when `<B>` is both the current
   branch and a tracked manifest's `branches[0]`. Every other push keeps the answer it gets
   today;
5. document the in-flight queue state without changing it.

## Does it do it

Yes. I checked the diff against the rulings in `NOTES.md` (1–5, plus 6–11 taken during the
build):

- **Shared push function.** `push_feature_branch` in `plan-runner-roots.sh` is the only
  `git push` in the lifecycle scripts. It prints nothing and returns 0, `PUSH_RC_NO_REMOTE`
  or `PUSH_RC_FAILED`. The capture turns those codes back into the same three outputs it
  had before (pushed, skipped with no origin, or refuse), with the same text.
  `checkpoint_push` is the advisory wrapper and always returns 0.
- **Profile check.** Both new push sites check the profile first: `feature-start.sh`
  through `profile_is_cloud` (`env-profile.sh` was already sourced there), and
  `run-review.sh`'s `push_round` through `declare -F profile_is_cloud && profile_is_cloud`.
  `push_round` also requires the checkout to be on `branches[0]`, and not on the base or a
  detached HEAD. I checked that sourcing `env-profile.sh` into `run-review.sh` reuses none
  of the names the runner already defines; the only overlap is `feature_branch`, which is a
  local variable in `push_round` while `env-profile.sh` defines a function of that name,
  and bash keeps the two apart.
- **Hook approval.** `own_push_allowed` runs only after `git_allowed` fails, and after
  `token_confined` and the deny paths. Those deny paths are unchanged, so force pushes,
  pushes to `main` and cloud pushes to another branch are still refused before it runs. It
  reads the words first and the profile second, compares the remote word exactly to
  `origin`, rejects `+`, `:`, `HEAD`/`@`, `refs/heads/` and `main` through a strict regex,
  and requires git's current branch, a toplevel that contains the root, and a tracked
  manifest whose `branches[0]` is that branch. Any exception approves nothing. `policy.py`
  is untouched, so `.claude/settings.json` does not need regenerating.
- **Tests.** Each required test fails without the change:
  - `hook-cloud-profile.sh`, table T: the push is approved in the cloud and prompts
    locally, while force pushes, other branches, other remotes, extra flags and refspec
    spellings are not approved;
  - `hook-cloud-profile.sh`, section Q: the branch is listed second in a manifest, only
    mentioned in prose, named by no manifest, on a detached HEAD, or in no repo, and none
    is approved;
  - `cloud-checkpoint-push.sh`, C1–C5: the cloud round leaves the bare origin at the local
    head, local pushes and prints nothing, an unreachable origin gives one warning with
    exit status 0, no origin prints nothing, and a branch the manifest does not name is
    not pushed;
  - `cloud-start.sh`: A1i covers the cloud start push and P1e confirms nothing is pushed
    locally.

  All fixtures are generic.
- **Docs.** These agree with the code: `LIFECYCLE.md` steps 2 and 5 and rule 2,
  `hooks/README.md`, `CONVENTIONS.md`, the root `README.md` rows, `self/PROJECT_FACTS.md`,
  `self/tests/README.md` and `NOTES.md`.
- **Gate.** `self/gate-report.txt` is green and skipped nothing.

## Fixed in this pass

- `feature-capture.sh:135`: the comment above `ORIGIN_REMOTE="$PUSH_REMOTE"` stopped
  mid-sentence ("…: the push function's"). I finished it so it names
  `plan-runner-roots.sh`'s `PUSH_REMOTE`. This changes a comment only.

## Escalated to the next round

None.

The one open question was already raised by the build: whether `run-plans.sh` should push
after each plan (ruling 3). It is the owner's decision, not a defect, and is recorded in
`self/BACKLOG.md`.
