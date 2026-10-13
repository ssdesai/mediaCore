# Checkpoint: ledger-and-routing

status: committed          planned | tests-written | implementing | gating | committed
updated: 2026-09-18T12:44:00Z
gate: `=== gate: done — all checks passed ===` (self/gate-report.txt VERDICT
      `all checks passed`, exit 0) — full tree: shell syntax, every self-test,
      python syntax, the byte-for-byte permission policy check, rate table,
      runner prerequisites; shellcheck not installed, no SKIPPED, no FAIL

Two implementers in one worktree (design §6). This file is **A1's** (§1, the routing
record per feature); A2's slice (§2–§4) keeps no checkpoint here.

## Slices (A1)
- [x] acceptance tests, RED first — `routing-record.sh` (36 red), `feature-lifecycle.sh`
      MR and the start/capture paths (14 red, the second merge exiting 1 on the add/add
      conflict itself), `verdict-readers.sh` (1 red)
- [x] 1. `analysis/routing.py` — `record_path(features_dir, slug)`, `routers_of` reads the
      one file, `load_records` globs `*/routing.json` and keeps one record per
      `session_id` by `record_rank`, `--migrate`
- [x] 2. the writers and the stray reader — `feature-start.sh`, `feature-capture.sh`,
      `plan-runner-roots.sh`, `sync-plans.sh`
- [x] 3. `--migrate` run on `self/`: two legacy records into seven feature directories,
      one slug skipped (NOTES ruling 1), `self/routing/` gone
- [x] 4. READMEs — root, `LIFECYCLE.md`, `analysis/`, `self/`, `self/features/`,
      `self/tests/`, `templates/plans/` and its features stub, the manifest TEMPLATE
      trailer and this feature's copy of it, `self/BACKLOG.md`
- [x] NOTES.md rulings 1–11; gate green; four commits

## Learned
- `analysis/report.py` needed no change at all: both renderers take `features_dir` and ask
  `routing.py` for the paths (NOTES ruling 6).
- `self/tests/sync-check.sh` never mentioned `routing/`; nothing to follow there.
- The corpus really holds the open question's case — `tooling-backlog-2026-09-17`, a slug
  a router started that never became a feature here.

## Resume
- Worktree `/Users/sahildesai/dev/agentTooling/.worktrees/ledger-and-routing`, branch
  `ledger-and-routing`, base `main`. A2 is editing `analysis/capture_planning.py`,
  `analysis/manifest.py` and the session/claims tests in the same tree — stage by path.
- Tests: `bash self/tests/routing-record.sh`, `bash self/tests/feature-lifecycle.sh`,
  `bash self/tests/verdict-readers.sh`.
- Gate: `bash self/gate.sh` from the worktree; last line `all checks passed`.
- Not from here: `run-review.sh`, `feature-close.sh`, a push, a PR.
