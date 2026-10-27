# 01 — review: cloud-off-branch-remedy

## What the feature was supposed to do

A Claude Code cloud container is one feature's checkout, on the feature's branch. When the
platform reclaims an idle session's container and a new message wakes it, the session
comes back in a NEW container cloned on `main`, while the feature's branch and its
committed manifest (`branches[0]`) are still on origin. Two pieces of advice were wrong
there, and this feature fixes the **messages only**:

1. `hooks/allow-repo-commands.sh`: a cloud `git checkout <feature-branch>` from `main` is
   rightly refused by the switch-away rule, but its reason (`GIT_CLOUD_DENY_REASON_TEMPLATE`)
   filled the CURRENT branch in, so it said "Commit on `main`, push only `main`" — the
   forbidden action offered as the remedy (PR #94's rework session, 2026-10-27). Now, when
   the checkout is on `main` (the policy's protected branch) or detached and the refused
   switch/checkout names a branch a manifest records as `branches[0]` (the remote-tracking
   `origin/<x>` spelling included), a new reason is printed: the container is off its
   feature's branch, the session cannot switch to it, and the remedy is a fresh session on
   that branch or the human checking it out here. It must never tell the agent to commit or
   push the base.
2. `session-start.sh`: in the cloud on `main` or detached, one more line after the
   new-feature line — a session continuing a feature started on another branch is not on
   it; a fresh session on that branch is the fix; never check it out or push main.
3. Tests in `self/tests/hook-cloud-profile.sh` (O block) and `self/tests/session-start.sh`
   (C4b–C4d).
4. Docs: `hooks/README.md`, root `README.md` (`hooks/` and `session-start.sh` rows),
   `LIFECYCLE.md` step 2 (the restart case), `ORCHESTRATION.md` → "Cloud sessions" (a
   reclaimed child comes back on main; the parent launches a fresh session), and the
   fence's `NOTES.md` recording why no carve-out allows the switch.

5. Added by the parent session, docs only: `ORCHESTRATION.md` → "Cloud sessions" gains a
   bullet that each child's model is named on `create_session` by the repo's tiering
   (`haiku`/`sonnet`/`opus`, never the parent's tier by default; no specific model ID),
   with a matching line in `LIFECYCLE.md` → "Propagate" and `NOTES.md` ruling 5.

**The refusal itself must not change.** No carve-out may allow the switch.

One deliberate widening to check: the spec asked to reuse the existing manifest lookup over
the checkout's tracked manifests, but in the real incident the manifest is committed only
on the feature's branch, not on `main`, so that lookup alone would never fire. The hook's
`started_feature` therefore also searches the target commit's own tree (`git grep <tree>`,
`git show <tree>:<path>`). Judge whether that is correct and bounded.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every answer (allow / deny / prompt) of the hook is unchanged: only the deny REASON text
  differs, and only in the off-branch case. `self/tests/hook-cloud-profile.sh`'s T table
  still passes unchanged.
- The off-branch reason never contains "push only" or "Commit on" for the base; it names
  the target branch, the slug, a fresh session and the human.
- A switch on `main` to a branch no manifest names keeps the existing reason; on the
  feature's own branch nothing changes.
- The new probes run only on the cloud, refused, switch/checkout path; no git subprocess
  is added locally (the X checks), and every failure falls back to the ordinary cloud
  reason, never a crash and never an allow.
- `session-start.sh` stays read-only, fast and short: one fixed line, no manifest scan.
- Magic values are named constants (CONVENTIONS.md → "Named constants"); bash 3.2; no
  profile variable spelled outside the allowed files.
- READMEs touched are accurate (CONVENTIONS.md → "Keeping READMEs up to date").
- `./self/gate.sh` is green.

"No findings" is a legitimate verdict.

## Verdict

The first line of `self/review-report.md` is `Verdict: clean` or `Verdict: escalated`.
