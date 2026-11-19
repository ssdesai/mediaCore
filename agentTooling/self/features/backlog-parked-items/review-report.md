Verdict: clean

# Review: backlog-parked-items (round 1)

## What the batch was supposed to do

Docs only. Add to `self/BACKLOG.md`:

- eight README/spec-structure entries the owner parked on 2026-11-07, under a lead sentence
  saying they are parked, raised by `readme-structure`
- five loose harness items (9, 12–15), raised by `orchestrator notes 2026-11-07`

Items 10 and 11 were already in the file and must not be repeated. The diff could touch only
`self/BACKLOG.md` and `self/features/backlog-parked-items/`.

## Whether it does it

Yes.

- **Scope.** `git diff origin/main...HEAD --stat` shows three files: `self/BACKLOG.md`, which
  only gains lines (+90, no existing entry touched), plus the feature's own README and review
  brief.
- **Entries and shape.** All thirteen entries are present. Each has a bold claim, an
  `Assertion:` and a `Raised by`, and runs 3–6 lines.
- **No duplicates.** Neither "Program cells cannot be reset" (line 367) nor "`run-plans.sh`
  has no time budget" (line 373) is repeated. The new "brings a feature branch up to date
  with main" entry is related to the existing "squash-merged cloud branch can't start its
  next feature" entry, but it is not the same item. That one is about a start refusing on a
  branch that is already merged. The new one is about merging `origin/main` into a live
  feature branch.
- **Claims checked against the tree:**
  - `harness/README.md` (lines 725–726) says an `"arm"` row's `spec_commit` is still the
    fixture's `spec.commit` while the cell's spec is at `base`. This matches the entry.
  - In `harness/publish.sh` (lines 108–112), the PR body is that experiment's
    `SCORECARD.md`, and an already-open PR is only logged, not updated. This matches the
    entry.
  - `feature-start.sh` has one "Manifest and review stub" step (line 867 on) and no
    experiment case. This matches the entry.
  - The PR numbers (#218, #231, #273, #275, #277, #73, #74, #119) and the A/B figures
    (−30.3% / −77.2% / −5.5%, n=2) match `self/orchestrations/readme-structure/README.md`.
- **Consumer-repo claims.** The section's lead sentence says consumer state comes from the
  orchestration record or the orchestrator's note as of 2026-11-07, not checked from this
  tree. Where an entry goes beyond the record (#119 opt-in, the `check_test_spec_split.py`
  wiring, the experiments index), it repeats "as of 2026-11-07".
- **Gate.** `self/gate-report.txt` (final level) reads "all checks passed", including the
  README-index check. Nothing was skipped.

## Fixed in this pass

- `self/BACKLOG.md`, in the entry "`plans/experiments/README.md` lacks index lines…": the
  entry cited `harness/SPEC.md` as expecting "the index to gain a line per experiment
  directory". SPEC.md says no such thing. Its only mention (line 454) is that, in one
  humanNetworkMap build, the index gained two specific directories. I replaced the
  citation with a fact the tree does show and that explains the drift:
  `harness/new-experiment.sh` writes the experiment's own `README.md` but no line in that
  index.

## Escalated to the next round

None.
