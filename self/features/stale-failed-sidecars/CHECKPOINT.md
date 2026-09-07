# Checkpoint: stale-failed-sidecars

status: committed          planned | tests-written | implementing | gating | committed
updated: 2026-09-06T14:19:00Z
gate: all checks passed

## Slices
- [x] 0. review brief (84-review-opus), manifest prose, check-plans clean — commit `brief`
- [x] tests first: self/tests/stale-failed-sidecars.sh — 17 of 18 RED against the
      unfixed report.py, registered in self/gate.sh twice + tests README row — commit
      `acceptance test`
- [x] 1. build_usage_index → sorted candidates, PlanUsage(live, priors), sibling rule
      then USAGE_STATE_PREFERENCE then path; find_state_dir shared with find_queue_segment
- [x] 2. read_plan_md warns and skips; compute_plan_length_vs_loc and compute_plan_drift
      go through it, both gained `warnings`, both call sites updated
- [x] 3. prior_attempt_cost + compute_cost_rollup(usage_index=): priors' measured and
      recovered dollars roll in once; the unpriced trigger gained `and not prior_total`,
      its wording untouched
- [x] 4. docs: analysis/README.md index entry, RUNNER.md failed/ paragraph (ruling 1 as a
      decision), self/tests/README.md row, self/README.md rows
- [x] 5. self/BACKLOG.md — four entries, stream_shows_usage_limit first
- [x] phase 6 re-fixtured after the fix: the original 6b asserted the total was the live
      figure alone, which ruling 4 contradicts; it now reads the winner off the
      plan-length table and asserts the prior's dollars roll in beside it
- [x] gate green (49 sections, 0 FAIL, 0 SKIP); NOTES.md; commit `build`

## Learned
- The gate does NOT glob tests: `self/gate.sh` needs the new script in `shell_scripts`
  (for `bash -n`) AND its own `record` line. Two edits, or it half-runs.
- `report.py` reads a sibling `.md` in exactly two places; the other four `with_name`
  hits are `.stream.jsonl` and were already `.exists()`-guarded.
- `loaded_plans` triples are unpacked in nine places, so the priors travel through
  `usage_index` into `compute_cost_rollup` rather than through a widened tuple.
- `recover_attempts.py` walks `features_dir.rglob("*.usage.json")` itself (line 138) and
  never imports `report`, so ruling 5's answer is "unaffected".
- `report.py` over `sweep-and-check` and `feature-lifecycle` is byte-identical before and
  after but for `generated_at` — the ranking is a no-op where the old dict was unambiguous.
- Test fixture pattern copied from `self/tests/cost-recovery.sh` assertion 15: a minimal
  feature dir with a fenced-JSON `README.md`, a `planning.json` carrying `cost_usd.total`,
  inline `usage.json` files, assertions read out of `report.json` through a `$TMP/verify.py`.

## Resume
- Nothing outstanding. Three commits on `stale-failed-sidecars`: `brief`,
  `acceptance test`, `build`. Not pushed; the review pass opens the PR.
- Worktree: /Users/sahildesai/dev/agentTooling-stale-failed-sidecars; the primary
  checkout and every other worktree were never touched.
- Verify: bash self/tests/stale-failed-sidecars.sh (20/20); ./self/gate.sh;
  ./check-plans.sh --self stale-failed-sidecars (14 checks, 0 failed)
- Left to the coordinator: pin the implementer's agent id in the manifest's `subagents`.
