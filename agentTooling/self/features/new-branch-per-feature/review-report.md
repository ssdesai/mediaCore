Verdict: clean

# Review — new-branch-per-feature

## What the batch was supposed to do

Write the owner's ruling into the docs: **a new feature always gets a new branch, normally
in a new cloud session. A squash-merged branch is never taken over or force-pushed to start
the next feature.** The rule goes in `ORCHESTRATION.md` → "Cloud sessions", `LIFECYCLE.md`
gets at most a one-line pointer, and the backlog entry "A squash-merged cloud branch can't
start its next feature." is removed. Nothing else changes.

## Does it do it

Yes.

- **Scope:** `git diff origin/main...HEAD --stat` touches `LIFECYCLE.md` (+2/−1),
  `ORCHESTRATION.md` (+13), `self/BACKLOG.md` (−13) and files inside
  `self/features/new-branch-per-feature/`. No script, hook or `analysis/` file changes,
  and no other feature's folder changes.
- **`ORCHESTRATION.md` → "Cloud sessions":** the new bullet covers every required point:
  - one feature per child session and per branch;
  - after a merge, the next feature is a new child session on a new `claude/<slug>` branch;
  - a squash-merged records branch gets a normal merge of `origin/main` (no reset, no
    force-push) or a fresh records branch;
  - one sentence on the `git patch-id` hazard.

  It uses the same bold-lead bullet shape and `→ "…"` cross-reference style as the bullets
  around it. Both references resolve:
  - "`outcome_branch`, as above" points to the bullet at line 117.
  - `LIFECYCLE.md` → "Orchestrator and implementer sessions" is the heading at line 250.
    Its "Consequence" bullet says the same thing as the new text: one session, one branch,
    one feature, and a start refuses a tracked manifest's branch, merged or not.
- **The patch-id claim** is stated accurately. It explains why there is no takeover to
  automate, and says the prototype was parked for that reason. It does not claim the
  prototype was wrong in every case.
- **`LIFECYCLE.md`:** the change is one parenthetical in step 2's list of what a cloud start
  refuses, pointing to the new rule. It is consistent with that list.
- **`self/BACKLOG.md`:** only the targeted entry is removed. The "Running several features
  at once from one cloud orchestrator is undocumented" entry is unchanged. No other backlog
  text mentions the removed entry; the only "squash" left in the file (line 260) is about
  an unrelated merge-method issue. The other places that quote the entry are older
  features' specs and review reports, which are history. `NOTES.md` records that they were
  left as written on purpose.
- **Gate:** `self/gate-report.txt` verdict is "all checks passed", and the README index
  check passes (24 READMEs, none missing). The one non-zero exit is the advisory check
  "pricing rate history is current" (exit 1). That check is about rate data, not this
  docs-only change.

## Fixed in this pass

None.

## Escalated to the next round

None.
