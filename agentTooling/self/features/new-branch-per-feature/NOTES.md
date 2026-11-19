# Notes — new-branch-per-feature

## Rulings

- **Owner's ruling (2026-11-17):** a new feature always gets a new branch, normally in a
  new cloud session. A squash-merged branch is never taken over or force-pushed to start
  the next feature.
- **Why no takeover:** the parked prototype (`claude/start-squash-merged-branch`,
  unmerged) matched a branch's commits to `origin/main` by `git patch-id`. Its security
  audit found patch-id ignores where in a file a change lands, so a branch edit to one of
  two identical blocks looks "already on main" when main edited the other, and the
  force-push silently loses it.
- **Scope kept to docs:** `ORCHESTRATION.md` → "Cloud sessions" carries the rule;
  `LIFECYCLE.md` step 2 gets one parenthetical pointer where it lists what a cloud start
  refuses; LIFECYCLE rule 2 needed nothing (it already bars `reset --hard` and force-push).
- **Backlog:** the "squash-merged cloud branch can't start its next feature" entry is
  removed. Nothing filed in its place: the ruling closes it, and the other orchestrator
  entry is untouched. Older features' specs and reports that quote the entry are history
  and are left as written.
