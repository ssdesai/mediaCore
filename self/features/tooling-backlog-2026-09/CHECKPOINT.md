# Checkpoint: tooling-backlog-2026-09

status: committed
updated: 2026-09-02T13:00:40Z
gate: all checks passed

## Slices
- [x] acceptance tests — `self/tests/level-sentinel.sh` (item 2, 4 red),
      `self/tests/tiered-gates.sh` (item 1, 4 red), `self/tests/direct-timing.sh`
      (new, item 5, 14 red), `self/tests/cost-recovery.sh` (item 9, 3 red);
      committed alone as `tooling-backlog-2026-09: acceptance tests`
- [x] 1. item 1 — `run-batch.sh` resume settles a crossed level with `auto/incomplete/` empty
- [x] 2. item 2 — `LEVEL_PAUSE_NN_OUT` handshake (`plan-runner-lib.sh` + `run-batch.sh`)
- [x] 3. item 3 — the SKIPPED sentence in `run-review.sh`'s review prompt item 4
- [x] 4. item 5a — `stamp-timing.sh`, `self/gate.sh` `shell_scripts`, root `README.md` row
- [x] 5. item 5b — `report.py` direct checkpoint sub-rows; `AGENT_DIRECT.md`,
      `harness/methods/direct/template.md`, `analysis/README.md` (items 5, 8)
- [x] 6. item 9 — `report.py` stops calling a runner-skipped level-verify "missing usage"
- [x] 7. item 4 — stacked PRs in `templates/plans/pr.sh` + `self/pr.sh`; `README.md`
      "Adopting stacked pull requests"; one line in `ORCHESTRATION.md`
- [x] 8. item 6 — `templates/plans/.gitignore`, `sync-plans.sh` `GENERATED`,
      `templates/README.md`, the two `README.md` steps, root `.gitignore` checked (complete)
- [x] 9. item 7 — `--list-subagents` empty-scan message names `--everywhere`
- [x] READMEs — `self/tests/`, `analysis/`, `templates/`, `templates/plans/`, `self/`,
      `harness/methods/direct/`, root `README.md`, `RUNNER.md`, `self/PROJECT_FACTS.md`
- [x] commit everything at status `committed`

## Learned
- The self-tests copy the real runner scripts into a `mktemp -d` checkout and drive them
  with `--self`; a stub `claude` on `PATH` and a stub `self/gate.sh` make behaviour
  observable without a model. Replacing a *runner* with a stub inside that checkout is
  how a `run-batch.sh`-only contract is isolated (`level-sentinel.sh` phase 7) — do it
  last, since the copies are not restored.
- `report.py`-level fixtures are hand-written feature dirs (`README.md` with a json
  fence, `planning.json`, a queue dir of sidecars) under the throwaway checkout's
  `self/features/`, driven as `python3 analysis/report.py <slug> --self`. A fixture
  `planning.json` with no `duration_s` makes the **Time** total partial, which is why an
  assertion about a partial *cost* total must name the Cost table's own row.
- `write_usage_json` (`self/tests/fixtures/usage/`) always writes a null top-level
  `total_cost_usd`; a fixture plan that must carry real dollars is written inline.

## Resume
- `cd /Users/sahildesai/dev/agentTooling`, branch `review/tooling-backlog-2026-09`.
- Tests, all green: `bash self/tests/{level-sentinel,tiered-gates,cost-recovery,direct-timing}.sh`
- Gate: `./self/gate.sh` (about two minutes), report at `self/gate-report.txt`.
- Remaining: `git add -A && git commit` on this branch. Do not push; the review pass
  (`self/features/tooling-backlog-2026-09/review/incomplete/71-review-opus.md`) opens the PR.
