# Checkpoint: review-base-and-cloud-hook

round: 4 — a re-capture on the branch can move `to` later (SPEC.md → "Round 4")
status: committed
updated: 2026-10-11T17:09:15Z
gate: not run (the coordinator's). Run one by one, all green: self/tests/feature-lifecycle.sh
      (red first: W8a–c FAILED, all else ok), worktree-claims.sh, recover-at-close.sh,
      session-share.sh, capture-from-worktree.sh, subagent-capture.sh, claims-ledger.sh,
      session-claims.sh, capture-guard.sh, routing-record.sh; bash -n feature-capture.sh and
      feature-lifecycle.sh; py_compile analysis/capture_planning.py.

## Slices
- [x] acceptance tests — feature-lifecycle.sh W8: a second branch session after the
      stamped `to`, a re-capture on the branch moves `to` past it (W8a–b); the chained
      successor cap through `--last-branch-instant --ignore-to` (W8c); fixture back on the
      W1 evidence via `exclude_sessions` (W8d); the same set-up through post-merge
      `--recapture` neither widens nor attempts to (W8e–g). Committed as
      `review-base-and-cloud-hook: round 4 acceptance tests`
- [x] 1. `last_branch_instant(..., ignore_to=False)` + `--ignore-to` CLI flag; the open
      upper bound capped at a chained successor's `from` (`chained_successor_from`)
- [x] 2. feature-capture.sh's on-branch path passes `ON_BRANCH_EVIDENCE_ARGS`; the
      post-merge path and the claim index's `provisional_to` do not
- [x] 3. docs — feature-capture.sh header step 2 + post-merge paragraph, docstring, usage
      line, LIFECYCLE.md step 6, analysis/README.md (two places), README.md row,
      self/tests/README.md row, NOTES.md rulings 30–33
- [x] 4. run touched tests, bash -n, py_compile; commit

## Learned
- feature-lifecycle.sh copies the scripts at its start only, so edits after its first
  phases do not reach a run already going.
- Deleting a priced session's transcript makes the next re-capture refuse; the W8 fixture
  disowns it with `exclude_sessions` instead (the acceptance commit's mv version did this).

## Resume
- git status --short; git log --oneline -5
- bash self/tests/feature-lifecycle.sh; never ./self/gate.sh
