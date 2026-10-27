# Checkpoint: cost-capture-collisions

status: committed
round: 2 (rework of round 1's review escalation, escalations/01-review-opus.md)
updated: 2026-10-05T18:30:00Z
gate: all checks passed (shellcheck skipped, not installed — as on the base)

## Round 1 (closed)
- [x] acceptance tests, runner scrub, collision capture, ledger `seen`, the cut, READMEs,
      real-corpus annotate, gate green, committed — see NOTES.md 1–20.

## Round 2 slices
- [x] acceptance tests committed alone (`cost-capture-collisions: round 2 acceptance
      tests`): subagent-capture.sh C12–C14b, a second project directory
      `-elsewhere-coordinator` holding pinned collided coordinator E; C13, C13b, C14b red
      on round 1's code
- [x] fix: `fallback_parent_collision` judges each pinned-delegate fallback hit's parent
      from its own transcript (`runner_collision` + `spawning_tree`);
      `find_pinned_anywhere` returns `(path, parent_collision)`; warnings shared via
      `runner_spawned_pin_warning` / `untold_spawner_warning`
- [x] ruling recorded: NOTES.md 21 (and 8 cross-referenced)
- [x] READMEs: analysis/README.md (fallback rule), self/tests/README.md (C12–C14b)
- [x] gate green, committed

## Resume
- Nothing to resume: the round-2 review (`review/incomplete/02-review-sonnet.md`) is next,
  the coordinator's.
