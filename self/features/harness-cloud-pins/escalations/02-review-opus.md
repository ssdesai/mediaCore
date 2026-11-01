Verdict: escalated

# Review: harness-cloud-pins (round 2)

## What the batch was supposed to do

The spec is the manifest's opening paragraph:

- **Repositories by URL.** Fixtures name their repositories by URL (`repo.url`,
  `spec.url`). `harness_resolve_repo` resolves each one per machine, in this order: an
  environment override, a local checkout, the path hint, an origin search, then a clone.
- **One forge seam.** The forge is asked through the vendored `forge.sh` (`pr-find` /
  `pr-open`), with `HARNESS_FORGE_BIN` as the seam. The `direct` brief also opens its PR
  this way.
- **Arms.** `agent_tooling: {<label>: <sha>}` arms are a third cell axis. Each arm gets
  a pin commit, a `<stem><Method><Arm><n>` branch, and `arm` / `agent_tooling` in its
  ledger row. The scorecard compares arms within each fixture × method.
- **Two fixes along the way:** the smoke test's Linux `mktemp`, and the skipping of
  merged manifests in `started_features_on` and in the start.

Round 1 found the feature complete and fixed three defects. It escalated three missing
tests: resuming after a failed pin, the scorecard's arm and method comparisons, and a
malformed `agent_tooling`. In round 2, commit `f342c9e` adds those tests and `56c9798`
repoints a stale cross-reference.

## Does it do it

Yes, with one exception: a defect in the pin (escalated item 1 below).

- **Round 1's three tests are all present.** Each asserts what round 1 asked for:
  - `smoke.sh` section 7: the pin dies after `worktree add`; the re-run pins exactly
    once; a further `--from setup` adds no second pin commit.
  - The malformed-`agent_tooling` check in section 6.
  - `harness/tests/scorecard-arms.sh`: four comparison lines, both figures, the band
    wording, and an unpinned row that is never paired with a pinned one.
- **Nothing the spec excludes appears in the diff.**
- **NOTES.md's claims hold.**
- **The two new READMEs are current.** `harness/README.md` and `harness/tests/README.md`
  describe the new test and its sections.

**The gate does not cover this round's work.** `self/gate-report.txt` is green and lists
nothing as SKIPPED. But it was generated at 14:04Z, before the test commit (14:13Z). And
`self/gate.sh` runs nothing under `harness/`: no `bash -n` of `harness/*.sh`, and neither
harness test. `harness/tests/README.md` says so itself. So the green gate tells you
nothing about this round's tests or about the harness code. **I ran both tests myself on
this tree:** `harness/tests/scorecard-arms.sh` passed all 24 checks, and
`harness/tests/smoke.sh` printed "all checks passed", including the new sections 6 and 7.

## Fixed in this pass

1. **The manifest's Plans table was out of date**
   (`self/features/harness-cloud-pins/README.md`). It listed only
   `review/incomplete/01-review-opus.md`, but that plan is now in `review/complete/`, and
   it did not list round 2's `02-review-opus.md` (which the JSON `plans` array already
   carried). The table now lists both rounds where they are.

## Escalated to the next round

1. **An arm pinned to the commit the base already vendors cannot run**
   (`harness/lib.sh`, `harness_pin_agent_tooling`).
   - **What's wrong:** the pin ends with
     `harness_commit_all … || harness_die "nothing to commit … the tree already matched?"`.
     A subtree-vendored `agentTooling/` at upstream commit X is byte-identical to
     `git archive X`. So when an arm names the version the fixture's base already
     carries, the extract and the sync change nothing, and `git commit` fails. The cell
     then dies after `worktree add`.
   - **Why it matters:** that is the natural control arm. `EXPERIMENTS.md` →
     "Setting up the arms" builds every arm "off the same prep commit", and the next
     feature's `exportStore` A/B (before PR 104 vs after) is likely to have one arm equal
     to what its base vendors. Every smoke check stays green because the smoke repo's
     `agentTooling/` is a symlink, so the pin always changes something.
   - **Suggested fix:** commit with `--allow-empty` when the staged tree is unchanged.
     The pin commit then still records the arm, and `do_setup`'s check (the pin subject
     in `BASE..HEAD`) still guards re-runs. Alternatively, skip the commit and treat the
     arm as pinned. Either way it is a decision, because the current behaviour is a
     deliberate refusal.
   - **Test to add:** a smoke cell whose base's `agentTooling/` is a real directory
     already at the arm's sha. Assert that it exits 0, that exactly one pin commit is on
     the branch, and that the row's `agent_tooling` is that sha.
2. **The gate never runs the harness** (`self/gate.sh`).
   - **What's wrong:** `harness/lib.sh`, `run.sh`, `new-experiment.sh`,
     `check-fixture.sh`, `publish.sh` and `scorecard.py` are most of this diff, yet none
     of them is syntax-checked or exercised by the gate. The tests rounds 1 and 2 added
     only protect anything when someone remembers to run them by hand.
   - **Suggested fix:**
     - Add `harness/*.sh`, `harness/methods/*/run.sh` and `harness/tests/*.sh` to the
       gate's `shell_scripts` list.
     - Add `harness/scorecard.py` to its `py_compile` checks.
     - Add `record "harness scorecard arms self-test" bash harness/tests/scorecard-arms.sh`,
       which is offline and takes seconds.
     - Add `smoke.sh` too: it is offline and needs only `jq`, `git` and `python3`, which
       the gate already requires.
     - Then drop "run them by hand" from `harness/tests/README.md`.
   - This changes what the gate covers and how long it takes, so it is a decision for the
     next round, not a review edit.

## Unverified

The gate was not re-run after this pass's README edit. That edit is prose in a feature
manifest, outside the fence that `manifest.py` reads.
