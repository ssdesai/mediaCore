# Checkpoint: recover-cost-at-close

status: committed          planned | tests-written | implementing | gating | committed
updated: 2026-09-06T15:24:20Z
gate: === gate: done — all checks passed === (51 checks, 0 failed)

## Slices
- [x] brief — `review/incomplete/85-review-opus.md` + manifest prose, `./check-plans.sh --self` clean, commit `recover-cost-at-close: brief`
- [x] acceptance tests — `self/tests/recover-at-close.sh` (11 red, expected), fixture helper, gate + README rows
- [x] 1. ruling 1 — `result_event` in `write_usage_sidecar` (+ `backfill_usage.py`, `analysis/README.md`)
- [x] 2. ruling 2 — `recover_attempts.py --for <slug>`; `feature-close.sh` recovery step between 4 and 5; `COST_FILES` extended
- [x] 3. ruling 3 — no bare `$0.0000`: `unpriced_plans[]` out of `compute_cost_rollup`, read by the printed line and `report.md`
- [x] 4. ruling 5 — docstring/README stop saying "killed only"
- [x] 5. ruling 7 — `self/BACKLOG.md`
- [x] READMEs: `analysis/README.md`, `self/tests/README.md`, `self/README.md` row, `self/gate.sh` registration
- [x] gate green, NOTES.md, stamp-timing, commit
- [x] rework: the four review escalations (NOTES.md → "Rework — 2026-09-06")
      1. unpriced_reason's three branches pinned by exact text — recover-at-close.sh D1-D4,
         fed by two new runner-written shapes (A7 failed+missing, A8 harvested killed)
      2. rollback_recovery pinned the way feature-lifecycle.sh C5f pins rollback_carry — E1-E5
      3. report.py raises at import unless QUEUE_COST_BUCKETS covers QUEUE_DIRS — D5-D6
      4. COST_USAGE_GLOB -> is_cost_usage_path (<queue>/<state>/…, both sets the runner's
         own); archived layout confirmed compatible from find_queue_segment and all 574
         sidecars on disk — F1-F3

## Learned
- The stream file is written by a `tee` in the middle of `run_plan`'s pipeline, so a
  consumer that closes the pipeline's stdout early truncates the record while `claude`
  runs on and exits 0. That is the defect's mechanism, not a CLI that omits its result
  event; see NOTES.md and `self/BACKLOG.md`.
- `in_window`'s `to` bound is EXCLUSIVE, which makes any fixture that stamps a transcript
  seconds before a close boundary-flaky. Pin the session with `feature-start.sh --session`
  instead.
- bash 3.2 mis-parses a `case` pattern inside `$( … )` and reports it on stderr while the
  assignment succeeds — a silent wrong answer. Use `grep`/`cut` in a substitution.
- The captured `.stream.jsonl` is gitignored and dies with the worktree; the surviving
  evidence for the defect is the **0-byte `.progress.md`** beside each unpriced sidecar.
- The defect is wider than the brief says: seven vinylCatalogue features, not two, plus
  musicMap `pin-ruff`. All eight session transcripts still exist under `~/.claude/projects/`.
- `feature-close.sh` does not need the worktree, but it does need branch `<slug>` locally
  **or** `origin/<slug>`. Every affected feature still has `origin/<slug>`.
- `manifest.py set-window-to` leaves an already-stamped `to` alone and exits 0, so a
  re-close does not move the window.

## Resume
- `git -C /Users/sahildesai/dev/agentTooling-recover-cost-at-close status --short`
- `bash self/tests/recover-at-close.sh` (the acceptance tests; RED until slices 1-3 land)
- `./self/gate.sh` from the worktree
