Verdict: clean

# Review: harness-cloud-pins (round 3)

## What the batch was supposed to do

The spec is the manifest's opening paragraph:

- **Repositories by URL.** Fixtures name their repositories by URL (`repo.url`,
  `spec.url`). `harness_resolve_repo` resolves each one per machine.
- **One forge seam.** The forge is asked through the vendored `forge.sh`, with
  `HARNESS_FORGE_BIN` as the seam.
- **Arms.** `agent_tooling: {<label>: <sha>}` arms are a third cell axis. Each arm gets a
  pin commit, a `<stem><Method><Arm><n>` branch, and `arm` / `agent_tooling` in its
  ledger row. The scorecard compares arms.
- **Two fixes along the way:** the smoke test's Linux `mktemp`, and the skipping of
  merged manifests at the start.

Rounds 1 and 2 found the feature complete. Round 2 escalated two items, and NOTES.md
records a ruling on each:

1. **An arm equal to the base could not run.** Ruling: such an arm (the control arm)
   still gets its pin commit, made with `--allow-empty`.
2. **The gate never ran the harness.** Ruling: the gate now runs it.

This round reviews the commits that build those two rulings: `0010ad3` and `951fbc0`.

## Does it do it

Yes.

- **The control arm (`0010ad3`).**
  - `harness_commit_all` takes an optional `--allow-empty`. Only
    `harness_pin_agent_tooling` passes it, so every other caller still fails on an empty
    tree, as before.
  - The pin's error message no longer guesses that "the tree already matched".
  - `smoke.sh` section 8 tests it the way round 2 asked. It builds a base whose
    `agentTooling/` is a real directory at the arm's commit, already synced. It then
    asserts all of the following:
    - the run exits 0;
    - there is exactly one pin commit;
    - that commit lists no files and has its parent's tree;
    - the row's `agent_tooling` is the arm's full sha;
    - a `--from setup` re-run finds the empty commit and does not make a second one.
  - `SPEC.md`, `harness/README.md` → "Arms", `EXPERIMENTS.md` → "Setting up the arms"
    and `harness/tests/README.md` all describe the empty pin commit.
- **The gate runs the harness (`951fbc0`).**
  - `self/gate.sh` syntax-checks `harness/*.sh`, `harness/methods/*/run.sh` and
    `harness/tests/*.sh`.
  - It compiles `harness/scorecard.py`.
  - It records `scorecard-arms.sh` and `smoke.sh` as steps.
  - `harness/tests/README.md` no longer says to run them by hand.
  - `self/README.md` (the `gate.sh` entry) and `self/PROJECT_FACTS.md` → "Tests" now
    list them.
- **The gate is green, and this time it covers the harness.** `self/gate-report.txt`
  (generated 14:22Z, level final) ends `all checks passed` and lists nothing as SKIPPED.
  It includes:
  - `bash -n` of every harness script;
  - `py_compile harness`;
  - `harness scorecard arms self-test` (all checks);
  - `harness smoke test`, including the new section "control arm (pin equal to the
    base)" (11 checks, all ok).

  This round's two commits are timestamped 14:33Z, after the gate ran. But the report
  already contains their steps and section 8, so it was run on that working tree before
  it was committed.
- **Contracts.**
  - Nothing the spec excludes appears in the diff.
  - The new code introduces no magic literals: the smoke test's names and counts are
    constants at the top of the file.
  - Every folder touched has a current README.
  - NOTES.md's two round-2 rulings match the diff. Its "Left undone" items are still
    absent rather than half-done.

## Fixed in this pass

1. **The manifest's Plans table pointed at the wrong directory**
   (`self/features/harness-cloud-pins/README.md`). It listed this round's plan as
   `review/incomplete/03-review-opus.md`. The runner moves the plan to `review/complete/`
   when this pass finishes, so the row now names `review/complete/03-review-opus.md`,
   like the rows for rounds 1 and 2.

## Escalated to the next round

None.

## Unverified

The gate was not re-run after this pass's edit. The edit is prose in the manifest's
Plans table, outside the JSON block that `manifest.py` reads.
