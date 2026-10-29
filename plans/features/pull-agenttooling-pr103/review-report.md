Verdict: clean

# Review — pull-agenttooling-pr103

## What the batch was supposed to do

Pull agentTooling main (PR #102 hand-start-friction: `cloud-setup.sh` template v3 with
`setup_in_background` and `--wait`, and feature-start waiting on cloud setup; PR #103
fable-plan-model: `fable` accepted as a plan/review model suffix) into the vendored
`agentTooling/` subtree with `update.sh`. Then adopt `plans/cloud-setup.sh` v3 by hand,
keeping this repo's synchronous venv block and sending nothing through `setup_in_background`.

## Does it do it

Yes. Every contract in the brief holds:

- **Merge shape.** `4546e31` (squashed `agentTooling/` 6053422..61cdeb7) plus merge
  commit `15ee44f`, the shape `update.sh` produces. `update.sh --check` says the chain is
  intact: base 4546e31 records split 61cdeb7.
- **No hand edits inside `agentTooling/`.** The one non-subtree commit (`72d4a9f`)
  touches only `plans/cloud-setup.sh`, `plans/README.md` and this feature's review brief.
- **`plans/cloud-setup.sh` above `REPO-SPECIFIC` is byte-for-byte the template.** A
  `diff` against `agentTooling/templates/plans/cloud-setup.sh` differs only after line
  125, the `REPO-SPECIFIC` marker, and both files have the marker on that same line. The
  template-version line reads 3.
- **The REPO-SPECIFIC venv block is unchanged.** The feature diff has no hunk below the
  marker.
- **`sync-plans.sh --check` is all in-sync**, with `plans/cloud-setup.sh` at
  template-version 3 and `plans/README.md` matching the synced template.

Behavioural note, not a defect: this repo backgrounds nothing, so no pid file is ever
written. `cloud-setup.sh --wait` therefore takes its early return ("nothing was ever
started") and exits 0, before it reaches the venv block. That is how
`feature-start.sh` should see this repo: there is nothing to wait for, and running
`--wait` does not run the install a second time.

The gate (install, lint, fixture idempotence, wheel contents, tests with 307 passing)
was green, and no check in it was skipped.

## Fixed in this pass

None.

## Escalated to the next round

None.
