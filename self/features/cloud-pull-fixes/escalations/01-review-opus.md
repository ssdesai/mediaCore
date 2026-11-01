Verdict: escalated

# Review: cloud-pull-fixes

## What the batch was supposed to do

Fix three defects found while propagating PRs 85–86 from a Claude Code cloud container:

- **A.** Make `update.sh` accept a cloud-started pull feature. In the cloud the branch is `claude/…` and the manifest sits at `plans/features/<slug>/`.
- **B.** Make "a template changed but its version stamp didn't" impossible to merge. Bump `cloud-setup.sh` to 2 so stale consumer copies show `DRIFT`.
- **C.** Stop `<repo_name>/<slug>` claimant mentions from doubling up when two captures spell the repo name in different case.

## Does it do it

Mostly yes. The gate (`self/gate-report.txt`) is green, including the three new blocking tests (`update-cloud-branch.sh`, `template-version-bump.sh`, `claimant-case.sh`) and the existing `propagation-pull.sh`, `sync-check.sh`, `claims-ledger.sh`, `session-claims.sh` and `session-share.sh`.

- **A: holds.** `update.sh` still checks for the branch-named manifest first. When it is absent, `update.sh` falls back to `started_features_on`, a function lifted out of `session-start.sh` into `plan-runner-roots.sh`, so there is still only one parser.
  - The library is sourced inside `main()`, only on the fallback path, and before the pull.
  - No global name in the library clashes with one in `update.sh`.
  - If the library is missing, the fallback finds zero matches and refuses (fail closed). `propagation-pull.sh` runs `update.sh` without the library and covers the local layout.
  - `main` is now refused explicitly. Untracked manifests are ignored. Two or more matches are refused, naming every slug.
  - This matches how `feature-start.sh` decides a branch already holds a feature: it refuses any tracked manifest whose `branches[0]` is the branch.
- **B: partly.** The template audit is correct. Checking each template's history since its `template-version` line last moved (`edf073d`), only `cloud-setup.sh` changed (PR 85, `af75b94`). So re-recording the other five rows at their current versions hides nothing.
  - Counting comments in the hash reverses an earlier, deliberate rule. I think that is the right call: the comment is how a consuming repo learns how the script is run, and PR 85 proved a free comment edit leaves stale copies reading `in-sync`.
  - The re-record command in the `TEMPLATE_VERSIONS` header is exactly what `stamped_hash` computes.
  - The check still lets a re-recorded edit through without a bump; see the escalation below.
- **C: holds.** Mentions are compared by `(repo_name.lower(), slug)` in `roots.py`. They are collapsed in:
  - `other_session_claimants`
  - `annotate_frozen_record`
  - `report.compute_shared_sessions`
  - the drift check's `claimant_windows` lookup

  `claimant_seen` was already case-insensitive. `share_basis` and the share split dedupe on `claim_key`, which uses the lowercased origin identity, so they cannot double a feature either. I found no other writer or reader the batch missed.
  - The builder's finding is confirmed in this container: `origin` is `https://github.com/ssdesai/agenttooling`, all lowercase. Because the cloud origin itself is lowercase, preferring any spelling with capitals is the right preference, and it depends only on the set of spellings, not their order.
  - The shell's `feature_repo_name` follows the same parsing rule as Python's `repo_display_name`.

## Fixed in this pass

- `update.sh:53-55`: the comment above `FEATURES_REL` still said a branch is a feature's only when `plans/features/B/README.md` exists. It now also names the cloud fallback.
- `LIFECYCLE.md` → "Propagate" step 2: added the bootstrap case. A consuming repo whose vendored `update.sh` predates this feature has no cloud path, so the pull that brings this feature in, from a cloud container, would be refused. The step now gives that one pull by hand: `git subtree pull --prefix=agentTooling <remote> main --squash`, then `agentTooling/sync-plans.sh`.

## Escalated to the next round

1. **B: the check still passes when a template is edited and re-recorded without a version bump.** `self/tests/template-versions.sh` (the `version`/`hash` comparison around lines 90–101) only checks that the file's stamp equals the table's version and that the file's hash equals the table's hash. Nothing links a hash to a version.
   - **How it slips through:** edit `templates/plans/gate.sh`, see the red check, run the re-record command from the `TEMPLATE_VERSIONS` header, and update only that row's hash. Version 3 is unchanged, the gate is green, and every consuming repo reads `in-sync` with a stale copy. That is the PR 85 failure again, now one command away. The failure message (`BUMP_HINT`) names both steps, but nothing enforces the first.
   - **No test covers it:** `template-version-bump.sh` tests an unbumped edit (B3, B4) and a bump that was not re-recorded (B5), but not a re-record without a bump.
   - **Why it is a design decision:** a committed table read on its own cannot show that a row was rewritten in place.
   - **Option 1:** compare the row against the base branch's `TEMPLATE_VERSIONS` (`git show origin/<base>:templates/plans/TEMPLATE_VERSIONS`). This needs only the base tip, which a depth-1 fetch provides, so it still works in a shallow clone. Same version with a different hash fails; a missing base ref is reported as unchecked rather than passed.
   - **Option 2:** make the table append-only, one row per `(file, version)`. That still relies on review to catch an edited old row.
   - **Assertion to add either way:** "B8: hash re-recorded at an unchanged version fails (rc 1), naming the file".

## Not escalated (noted)

- The headers of the other five templates still say "bump when the body changes". That is now looser than the check, but the mistake fails loudly in the gate rather than silently. It is deliberately left for each template's next real bump and is recorded in `self/BACKLOG.md` (NOTES ruling 10).
