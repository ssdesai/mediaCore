# Checkpoint: tooling-backlog-2026-09-06

status: committed
updated: 2026-09-07T04:42:07Z
gate: all checks passed — 59 checks, 530 assertions, 0 failed, 0 SKIPPED

## Slices (rework)

The review pass's one escalation (`self/review-report.md` → "Escalated to the next
batch"): which copy of a deduplicated attempt the dollars come from. Built as a rework
one-shot on the same branch, on top of the build/verify/review commits.

- [x] 1. assertions first, 8 red — `self/tests/stale-failed-sidecars.sh` phases 11-13
      beside 8a/8b: 11a-11g the whole-plan path, 11h-11k the per-attempt path the
      finding described, 12 (both copies null, still unpriced) and 13 (both priced and
      disagreeing, live wins) the two contrasts. New `list_names_plan` verify command;
      `NO_COST` beside `LIVE_COST` / `STALE_RECOVERED` / `DECOY_COST`.
- [x] 2. `analysis/report.py` — `ATTEMPT_FIGURE_FIELDS` / `ATTEMPT_RECOVERED_FIELD`
      precedence constants, `attempt_figure()`, and `prior_attempt_cost` merging a
      prior copy into the live sidecar's attempts by `session_id` instead of skipping
      it. Its third return value is now the whole deduplicated list, so
      `compute_cost_rollup` drops `all_attempts = attempts + prior_attempts`.
- [x] 3. docs — `analysis/README.md` (the precedence beside the dedupe rule, in both
      places it documents the roll-up), `self/tests/README.md` (the
      `stale-failed-sidecars.sh` paragraph), `NOTES.md` → Rework, this file.
- [x] 4. `self/BACKLOG.md` — the closed entry deleted; the duration lower bound stays.
- [x] 5. gate green on the first run — 59 checks, 530 assertions, 0 failed, 0
      SKIPPED — then committed, pushed, and the escalation answered on PR #33.

## Learned
- The escalation's own account of the damage is half the story: the live null copy falls
  into `unrecoverable_sessions` only when the live sidecar prices some OTHER attempt.
  Where the shared attempt is the plan's only one, `compute_cost_rollup`'s earlier
  `cost is None and not plan_recovered and not prior_total` test short-circuits and the
  stem is unpriced as a whole plan instead. Both paths need a fixture.
- Only phase 11 can be red before the change: 12 asserts today's behaviour by
  construction ("as today") and 13 was already green because the old dedupe kept the
  live copy — unconditionally, which was the defect. Recorded in `NOTES.md` → Rework.
- Byte identity is checkable without touching the committed reports: two throwaway trees
  under $TMPDIR, each an `analysis/` copy beside a copy of `self/features/`, rendered
  slug by slug and diffed with `generated_at` filtered out.

## Resume
- Worktree `/Users/sahildesai/dev/agentTooling-tooling-backlog-2026-09-06`, branch
  `tooling-backlog-2026-09-06`. Never touch `/Users/sahildesai/dev/agentTooling`.
- Test: `bash self/tests/stale-failed-sidecars.sh`.
- Gate: `./self/gate.sh` (~70s), report at `self/gate-report.txt`.
