Verdict: clean

# Review: harness-claim-root

## What the batch was supposed to do

The experiment harness runs every `claude` session with cwd `<repo>-<Branch>`
(`harness_worktree_path`). `capture_planning.claim_roots` admitted only the primary, the
nested worktree and the legacy `<repo>-<slug>` sibling, so harness sessions landed in
`launched_elsewhere` and priced $0. The batch was to:

- add a `<primary>-<branch>` root for each manifest branch, at both call sites
- name that root in the warning
- drop the smoke test's fake legacy cwd
- fix the `// true` bug in the stage flags, which read an explicit `false` as true
- update the docs

## Whether it does it

Yes.

- **`claim_roots(primary, slug, branches=())`** adds `harness_tree_path(primary, b)` for each distinct branch.
  - It still returns `(roots, fences)`.
  - The `<primary>/.worktrees` fence still beats the primary root.
  - Whole-component matching (`path_at_or_under`) is unchanged.
  - A branch with a `/` or a trailing `/` only narrows the root; nothing widens it past `<primary>-<branch>`.
  - Empty `branches` adds no root.
- **Both call sites pass `branches`:** `capture_feature` and `last_branch_instant`.
- **The `launched_elsewhere` warning** is still one string expression per cwd, and it now lists the harness-tree roots.
- **Review and rework manifests carry the feature branch:** `write_stage_manifest` (in `harness/run.sh`) calls `harness_write_manifest "$TREE" "$slug" "$BRANCH" …` for the implementer, review and rework slugs alike.
- **`harness_stage_enabled`** (in `harness/lib.sh`) maps `null` to `true` and otherwise prints the value.
  - It is the only reader of the flags (`harness/run.sh`).
  - `program-stages.sh` only consumes `DO_*`.
  - `new-experiment.sh` writes the flags and does not read them.
  - A smoke assertion pins `"stages": {"review": false}` as false.
- **`smoke.sh`** no longer fakes the legacy cwd (`tcwd="$PWD"`).
- **Docs:** `analysis/README.md`, `harness/README.md`, `EXPERIMENTS.md`, `SPEC.md`, `harness/tests/README.md` and `self/tests/README.md` all describe the new behaviour.
- **Contracts:**
  - No file under `.claude/` or in another feature's folder is touched.
  - The test uses the `claude-sonnet-5` pricing fixture, which `worktree-claims.sh` and `session-claims.sh` already use.
- **Tests:** `bash self/tests/harness-claim-root.sh` and `bash self/tests/worktree-claims.sh` both pass. I did not run the full gate, as the plan said.

## Fixed in this pass

- **Two untested behaviours now have assertions** in `self/tests/harness-claim-root.sh`. Before this, either could have regressed with the gate still green:
  - **H5:** `--last-branch-instant` is bounded by the harness-tree session (`2026-06-01T10:00:01Z`), not by the later, unclaimable `otherBranch` and `…Extra` sessions. Before this, nothing tested the second call site's `branches` argument.
  - **H2c:** the warning names `['<primary>-exportStoreDirectAfter2']` among the claimable roots. H2b only checked that it named the offending cwd, which the warning always printed anyway.
- **README:** the entry in `self/tests/README.md` and the test's header comment now describe both new assertions.

## Escalated

None.
