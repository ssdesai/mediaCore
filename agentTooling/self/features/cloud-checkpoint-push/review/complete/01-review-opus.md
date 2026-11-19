# 01 — review: cloud-checkpoint-push

Review the diff against the spec below — the manifest's opening paragraph and the rulings
in `NOTES.md` — never against the builder's report. "No findings" is a legitimate verdict.

## What the feature was supposed to do

In a Claude Code cloud container (`env-profile.sh` says `cloud`) the session's assigned
`claude/…` branch is the feature's branch and the container is reclaimed when the session
ends, so a commit that is not pushed can be lost. Before this feature only the close pushed.

1. **Checkpoint pushes, cloud only.** Every lifecycle script that commits on the feature's
   branch pushes that branch (`branches[0]`) to `origin` after its commit when the profile
   is `cloud`: `feature-start.sh` after `<slug>: start`, and `run-review.sh` after the
   round's commits (`<slug>: review round N`, `<slug>: review stamps`) — the remote ends at
   the local head. A checkpoint push is advisory: a failure prints one line and never
   changes the script's exit status. `feature-capture.sh` keeps pushing as before.
   `run-plans.sh` and `run-verify.sh` commit nothing and are unchanged (NOTES ruling 3).
2. **One push implementation.** The push the capture already did (`git push -q -u origin
   <branch>`, skipped when there is no `origin`) is moved into one shared function in
   `plan-runner-roots.sh` and called from the capture and the checkpoints — not copied.
   No retry/backoff is added (NOTES ruling 2).
3. **Local profile byte-for-byte unchanged.** Under `local`, start and review push
   nothing and print nothing new.
4. **The hook approves the feature's own push in the cloud.** `hooks/allow-repo-commands.sh`
   approves silently, cloud profile only: `git push origin <B>`, `git push -u origin <B>`
   (and `--set-upstream`), and the same behind `git -C <path inside the root>`, when `<B>`
   is the current branch AND a tracked manifest names `<B>` as `branches[0]`. Everything
   else keeps today's answer: a force push (any spelling, incl. `+<B>`), any other branch,
   a refspec with `:`/`HEAD`/`refs/heads/`, any remote but `origin`, extra flags, a branch
   no manifest names, and every push in the local profile.
5. **In-flight queue state** is documented, not changed (NOTES ruling 4).

Excluded: pushing after each plan in `run-plans.sh`; changing the seeded `pr.sh`
templates; Claude Code's own Stop hook.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- The local profile: no new push, no new output, in `feature-start.sh` and `run-review.sh`
  — check every new push site is behind the profile check.
- The approval in the hook is reached only with the cloud profile, the remote word exactly
  `origin`, the branch word equal to the current branch read by git AND to a tracked
  manifest's `branches[0]`; a probe that fails approves nothing (fail closed). The
  existing deny paths (force, push to `main`, cloud push-elsewhere) still win.
- No second copy of the push command: `feature-capture.sh` and the checkpoints share one
  function; its output lines for the capture are unchanged.
- Named constants for the remote, messages and flags (CONVENTIONS → Named constants);
  bash 3.2, `set -uo pipefail` idioms (`self/PROJECT_FACTS.md`).
- `env-profile.sh` is the only shell way to the profile (`self/profile-confinement.sh`).
- Tests that fail without the change: in `self/tests/hook-cloud-profile.sh` (or a sibling),
  a cloud push of the feature branch approved; another branch, a force push, and a
  local-profile push not approved; in `self/tests/`, a cloud `run-review.sh` pass leaving
  a bare `origin` at the local head, and a cloud start pushing its start commit. Generic
  fixtures only.
- Docs current: `hooks/README.md`, `CONVENTIONS.md` § Shell commands (approved silently),
  `LIFECYCLE.md` steps 2, 5 and rule 2 (which said `git push -u origin <branch>` prompts),
  the root `README.md` `hooks/` row if it states the push rule, `self/tests/README.md`,
  `self/PROJECT_FACTS.md` where it describes commits/pushes, and the feature's `NOTES.md`.
- `.claude/settings.json` regenerated if `policy.py` changed (`wire-settings.py --self
  --check` in the gate).

## Verdict
