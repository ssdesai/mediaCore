Verdict: clean

# Review — harness-arm-spec

## What the batch was supposed to do

Let a base-arm experiment give each arm its own spec: `new-experiment.sh --arm-spec-path
<label>=<path>,…` (recorded as `experiment.json` `arm_spec_paths`) makes a cell read the
spec at that path in its own worktree instead of the shared, detached spec worktree. The
prompts must then say the spec is never to be edited. Without the option every prompt must
be byte for byte what it was at the base. Every row gains `spec_source` and `spec_path`, and
the six bad shapes are refused.

## Does it do it

Yes. Checked against each contract in the brief:

- **Byte identity.** `harness_build_isolation` defaults `HARNESS_SPEC_SOURCE` to `shared`,
  so `program-stages.sh`, which never sets it, gets the base text. The shared values of
  `HARNESS_SPEC_PROVENANCE` / `HARNESS_SPEC_RULE` reproduce the removed template lines
  exactly, line breaks and indentation included. I ran `arm-spec.sh --from-ref origin/main`,
  which fills the prompts with the base's own harness, and it matches
  `arm-spec.shared.md` (once the fix below is in). The test fills all six prompts the driver
  fills: the three method templates, `null`, and the review and rework preambles.
- **Placeholder order.** `@@SPEC_RULE@@` is replaced inside `harness_build_isolation`,
  before `@@ISOLATION@@` is inserted. `@@ISOLATION@@` goes in before the scalar loop, so the
  `@@SPEC_TREE@@` / `@@SPEC_PATH@@` inside the rule always get filled. In arm mode,
  `arm-spec.sh` asserts that no `@@…@@` is left in any of the six prompts.
- **Arm-mode wording.** In arm mode no prompt says "checked out detached" or "never write to
  it". The method templates now say "never to be edited: it is this arm's own copy, inside
  your tree", and the isolation bullet says "never edit, move or delete it". The review and
  rework preambles only say "(read-only)", which is still correct.
- **Refusals.** All six shapes are refused in `new-experiment.sh` with a message naming the
  label or path. The shape checks live in one `lib.sh` helper (`harness_check_arm_spec_paths`),
  which `run.sh` calls too, and `run.sh` also refuses a spec path missing from the cell's
  tree, at setup and on resume. The tests cover them in `arm-spec.sh` (unit) and `smoke.sh`
  (end to end).
- **Row shape and docs.** `spec_source` and `spec_path` are on every row and in the state
  file. These all document them: `harness/README.md` (Contents, Arms, `experiment.json`, row),
  `SPEC.md`, `EXPERIMENTS.md`, the templates, methods and tests READMEs, and
  `PROJECT_FACTS.md`. `self/gate.sh` records the new test, and the gate report is green.
- **Conventions.** No associative arrays, `set -uo pipefail` without `-e`, `mktemp -d` with
  a template under `$TMPDIR`, messages and labels as named constants, and no model named.

## Fixed in this pass

1. `harness/tests/arm-spec.sh`: the `--from-ref` mode did not work. It extracted only
   `harness/` from the ref, but `lib.sh` sources `../plan-runner-lib.sh` (and
   `../env-profile.sh`). The fill then printed a "No such file or directory" line into its
   output, and the comparison failed. That is the very mode the README says generates the
   expected file. The gate never runs it, so it stayed green. The test now extracts those
   two files as well, and `arm-spec.sh --from-ref origin/main` passes.
2. `harness/README.md`, Contents row for `new-experiment.sh`: the usage line was missing
   `[--arm-spec-path <label>=<path>,…]`. Added.
3. `harness/README.md`, "The ledger row": added that on an `"arm"` row `spec_commit` is still
   the fixture's `spec.commit`, which that cell did not read; its spec is at `base`.
   Otherwise a reader would take `spec_commit` as the version of the spec the arm used.

## Escalated to the next round

None.

Two things I chose not to escalate:

- Nothing checks after the method stage that the arm's spec file is unchanged in the cell's
  tree, for example `git diff <base> -- <spec_path>` coming back empty. The shared spec
  worktree had no such check at the base either, so this matches existing behaviour.
- `harness_arm_spec_path_ok` splits the path on `/` with globbing still on. A component like
  `.*` could therefore be wrongly refused under bash 3.2. Neither is likely in practice.
