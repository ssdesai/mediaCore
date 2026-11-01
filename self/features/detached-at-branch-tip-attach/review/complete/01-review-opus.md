# 01 — review: detached-at-branch-tip-attach

feature: agentTooling/detached-at-branch-tip-attach

Review the diff below against the spec. "No findings" is a legitimate verdict: report what
you checked, and escalate only a real defect, not a preference (AGENT_PLANS.md → "Review
plans").

## What the feature was supposed to do

The shape: a cloud session created to CONTINUE an existing feature branch
(`create_session` with `source_revision` and `outcome_branch` both set to the branch) came
up with HEAD **detached exactly at `origin/<branch>`**. The local `<branch>`, cached from
an earlier clone, was a strict ancestor 12 commits behind. The hook refused
`git checkout -B <b> origin/<b>` (LIFECYCLE rule 2), the commit steps refuse a detached
HEAD, and a fresh session reproduced the state, so the session was stuck.
`self/features/detached-at-branch-tip-attach/NOTES.md` §0 has the reproduction.

Required:

1. In the cloud, let the session re-attach when that is provably safe and not a switch.
   That means: HEAD is detached; the target is a manifest's `branches[0]`; HEAD's commit
   IS `origin/<branch>`; the local ref is absent, equal, or a strict ancestor of HEAD.
   Anything that would move the working tree to a commit other than HEAD's stays refused.
   When the container is detached at the tip, the refusal message names the exact
   allowed command instead of "start a fresh session". Every other case keeps its
   refusal.
2. `session-start.sh`: on a cloud detached HEAD equal to a manifest branch's
   `origin/<branch>`, print the attach remedy (instead of, or before, the restart line).
3. Optionally a one-command remedy (a tiny script) instead of teaching agents the git
   incantation, if that is smaller.
4. Tests:
   - `self/tests/hook-cloud-profile.sh`: detached at the tip → allowed; detached
     elsewhere → refused; at a tip that no manifest names → refused; local ref not an
     ancestor → refused.
   - `self/tests/session-start.sh`: the new remedy line.
   - Anything new registered in `self/gate.sh` and `self/tests/README.md`.
5. Docs:
   - `hooks/README.md`;
   - `LIFECYCLE.md` step 2;
   - `ORCHESTRATION.md` "Cloud sessions" (the cached-clone shape, and that a fresh
     session does not cure it);
   - `README.md` rows;
   - the rulings in NOTES.md.

The builder chose a script, `attach-branch.sh`. Read NOTES.md's rulings and hold them to
the spec. In particular:

- the `-B`/`-C`/`branch -f` shapes are left refused (settings prefix deny rules);
- the script prompts rather than being silently approved;
- a detached HEAD's tree-moving switch is newly refused, which reverses
  `cloud-off-branch-remedy` ruling 4.

Judge whether each ruling is sound, not whether you would have chosen it.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **Nothing that moves the working tree is newly allowed.**
  - `attach-branch.sh` acts only in the four-condition state. It changes no ref and no
    file on any refusal.
  - Its `update-ref` is a compare-and-swap. The checkout it then runs is to HEAD's own
    commit, and an uncommitted edit survives it.
  - Try to find a state in which it moves HEAD's commit, discards a local branch's
    commits, or attaches a branch no manifest names.
- **The hook** (`hooks/allow-repo-commands.sh`: `detached_switch_moves`,
  `attachable_branch`, `commit_of`, the reworked `cloud_git_deny_reason`,
  `GIT_CLOUD_ATTACH_TEMPLATE`):
  - Local answers are unchanged, and nothing local runs git (the X tests).
  - The attach reason appears only in the attachable state, and never says to commit or
    push `main` or to start a feature.
  - A file checkout on a detached HEAD is never refused.
  - No exception path turns a refusal into an allow, or crashes the hook.
  - X5's probe counts are unchanged.
- **One reading.** `plan-runner-roots.sh`'s `attachable_branches` and the hook's
  `attachable_branch` must agree on what is attachable. Look for a case where one says
  yes and the other no.
- **session-start.sh** stays read-only, fast, git only and with no network. Its new line
  appears only on a cloud detached HEAD in the attachable state.
- **CONVENTIONS.md**: named constants for meaningful literals; READMEs updated for every
  touched folder (root `README.md`, `hooks/README.md`, `self/tests/README.md`), with field
  lists and cross-layer dependencies named.
- **The gate**: `./self/gate.sh` is green (it runs `self/tests/attach-branch.sh`,
  `self/tests/hook-cloud-profile.sh` and `self/tests/session-start.sh`).

## Verdict

The first line of `self/review-report.md` is `Verdict: clean` or `Verdict: escalated`.
