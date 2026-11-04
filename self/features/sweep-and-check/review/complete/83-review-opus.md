# 83 — review

Feature: sweep-and-check — the weekly cost sweep, a pre-run lint of a feature's plan
corpus, drift detection for repo-owned files and the consumer update, each as a script
(manifest: `self/features/sweep-and-check/README.md`).

Diff against `main`. The gate is green on arrival and is your starting condition, not a
finding. Read the manifest first — the contracts table says the four CLI contract blocks
are the batch's spec, written twice each; a finding that re-litigates a decision in
"Deliberately excluded" is noise.

Weight your attention here:

- **The contract blocks were written by one author and implemented by two executors
  each.** Is there a reading of any block that the test accepts and the script does
  not satisfy, or the reverse, that the level-verify papered over? Look for an
  assertion that was weakened to pass rather than the script being fixed.
- **`run-batch.sh` now has a step before the build pass.** Every consuming repo runs
  this. Can the lint stop a batch that used to run? A feature with no manifest fence,
  a legacy plan name, an `NN-gate.md` sentinel, a `.progress.md` sidecar, a `--self`
  invocation — walk each against the fourteen checks. A false positive here is a
  blocked consumer.
- **`update.sh` rewrites itself while running.** Is the function-body guard actually
  sufficient in bash 3.2 — is anything read from the file after the pull? Is a failed
  pull left in a state the next run can recover from?
- **`sync-plans.sh --check` under `set -euo pipefail`.** A `cmp`, a `sed` on a missing
  file, an empty `grep` — any of these aborting the script is a check that never
  reports. Read every command whose status is consulted.
- **The capture change.** `excluded_ids_encountered` lifting the refusal: can a wrong
  branch name still produce an evidenced zero? Trace what populates the set.
- **What has no test.** A finding phrased as the assertion the next batch should add
  beats one phrased as an observation.

Write the verdict for the human approving the PR: what the batch set out to do, whether
it does it, then two lists — fixed here, escalated. "No findings" is a legitimate
verdict.
