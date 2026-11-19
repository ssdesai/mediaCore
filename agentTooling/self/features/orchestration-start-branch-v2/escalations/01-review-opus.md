Verdict: escalated

# Review: orchestration-start-branch-v2

## What the batch was supposed to do

1. `orchestration-start.sh --branch claude/<slug>`. This applies under the cloud profile, to an
   orchestrator record only:
   - The start refuses a detached HEAD or `main` without `--branch`, and the refusal names
     `--branch claude/<slug>`.
   - Given `--branch`, it cuts the branch off `origin/main` before any write, then commits the
     record on it.
   - It asks origin whether the branch exists, with `ls-remote`: exit 0 refuses, exit 2 goes on,
     any other exit refuses.
   - It refuses a branch that a manifest on `origin/main` names.
   - It enumerates manifests NUL-separated, and `held_feature` is fixed the same way.
2. An orchestrator session may `git mv` its own stranded record from
   `agentTooling/self/orchestrations/<slug>` to `plans/orchestrations/<slug>`. Every other move
   is still denied.

## Does it do it

Item 1 is done, and the code holds every contract the plan names:
- Every refusal comes before the first write. `checkout -b` is the first write, and the record
  and the ledger come after it.
- The exit codes are unchanged: 2 for usage, 1 for a refusal.
- `--coordinator` and the local profile both refuse `--branch` and are otherwise unchanged.
- The `ls-remote` exit-code mapping is exactly as specified.
- `held_feature` reads `ls-files -z` and `branch_named_at` reads `ls-tree -z`, both with
  `read -r -d ''`.
- `NOTES.md` records the decision on unmerged features' branches.
- The tests cover every case the plan lists: B1–B6, V4 and H28.
- The docs are updated: `ORCHESTRATION.md`, `hooks/README.md`, `LIFECYCLE.md`, the brief and the
  backlog.

`NOTES.md` explains why the brief's template version was not bumped. The brief has no
`template-version` line and is not in `TEMPLATE_VERSIONS`, so there is nothing to bump. I checked
this against `sync-plans.sh` and `templates/README.md`, and it holds.

The gate is green, with no check skipped.

Item 2 is approved by the hook exactly as specified, but **in its most likely use the approved
command fails** (escalated below).

## Fixed in this pass

- `self/BACKLOG.md` has two new non-blocking entries:
  - Six refusals of `--branch` have no test: a local branch of that name, `--branch main` or an
    invalid name, `--branch` while on another branch, a record already on `origin/main`, commits
    ahead of `origin/main`, and a dirty tree. I read each of them and each is correctly placed
    before any write. None is asserted.
  - `started_features_on` in `plan-runner-roots.sh` has the same `git grep -l` C-quoting gap
    this batch fixed in `held_feature`.

## Escalated to the next round

1. **The approved record move fails when `plans/orchestrations/` does not exist yet.** That is
   the usual state of a consuming repo whose only record is stranded at the old place: git
   tracks no empty directory, and only starting a new record in that repo creates
   `plans/orchestrations/` (`orchestration-start.sh`'s `mkdir -p`).
   `git mv agentTooling/self/orchestrations/<slug> plans/orchestrations/<slug>` then exits 128
   with "renaming '…' failed: No such file or directory". I checked this against git 2.43.0 in a
   scratch repo.
   - **Why it matters:** the orchestrator's allowlist holds no `mkdir`. So the session that
     `LEGACY_RECORD_REFUSAL` is written for still cannot apply the remedy, which is the gap
     item 2 was meant to close.
   - **Why the tests miss it:** H28 in `self/tests/hook-orchestrator-role.sh` (around line 2069)
     passes because its consumer fixture already has `plans/orchestrations/`, left behind by
     earlier steps.
   - **What the fix needs:** a decision on one of these:
     - (a) also admit `mkdir -p plans/orchestrations`, from the consuming repo's root, exactly
       that path, in `orchestrator_command_allowed`, and approve outright the line
       `mkdir -p plans/orchestrations && git mv …`;
     - (b) change `shared_rules.LEGACY_RECORD_MOVE`, and with it `LEGACY_RECORD_REFUSAL`, to a
       remedy that works without the parent directory;
     - (c) have `orchestration-start.sh` create `plans/orchestrations/` before it refuses the
       stranded record. That changes "nothing is written on a refusal", so it is an invariant
       amendment to decide on purpose.
   - **The missing assertion:** with `plans/orchestrations/` absent in the consumer fixture, the
     sanctioned remedy is approved and actually moves the record.
