# Test-first levels

A batch can be split into **levels** by sentinel plan files `NN-gate.md`; the
build runner runs the mechanical gate at each one, labelled, and yields (exit 4) to a
queued level-verify plan that `run-batch.sh` drains with `run-verify.sh --up-to NN`
before resuming the build. The gate template gains a level label, a per-level report
copy, and `record_skip`, so a skipped check is a non-green verdict. `AGENT_PLANS.md`
gains the rules that use it: plan 01 is the wanted behaviour as tests, one level per
layer, optional scoped level-verify, a smaller final verify.

## Plans

| Plan | What it does |
|---|---|
| `auto/incomplete/65-runner-sentinels-sonnet.md` | `plan-runner-lib.sh`: `is_gate_sentinel`, `level_verify_queued`, `run_level_gate`, sentinel branch in Phase 2 with exit 4, `PLAN_MAX_NN` bound in `list_plans`; `run-verify.sh --up-to`; skip≠pass in the verify prompt; `RUNNER.md`. |
| `auto/incomplete/66-batch-level-loop-sonnet.md` | `run-batch.sh` level loop; `README.md` rows and the consuming-repo adoption steps. |
| `auto/incomplete/67-gate-label-and-skip-haiku.md` | `templates/plans/gate.sh` and `self/gate.sh`: level label, `gate-report.<label>.txt`, `record_skip`, SKIPPED verdict, gate-provisioning principle; `templates/README.md`. |
| `auto/incomplete/68-doctrine-levels-sonnet.md` | `AGENT_PLANS.md` "Levels" section, manifest tables, checklist item 6, sentinel file-format bullet; manifest template; `self/` index and facts. |
| `verify/incomplete/69-verify-sonnet.md` | Exercises the sentinel, exit 4, `--up-to`, and `record_skip` on a scratch feature; checks doctrine against observed behaviour. |
| `review/incomplete/70-review-opus.md` | Diff review against the §1 decisions, the runner lock-step, and bash 3.2. |

## Deliberately excluded

- **The consuming repo's `plans/gate.sh`.** Repo-owned, never overwritten; each repo
  hand-merges the three gate edits (README → "Updating").
- **The grounding rule, multi-run green for browser suites, the read-budget fallback.**
  Separate features.
- **Changing D3 (level-verify optional, run when queued)** before the pilot measures it.
  It was changed afterwards — see below.
- **`sync-plans.sh` / `plan-runner-roots.sh`** — no change needed; the label is
  passed positionally and the gitignore widening is a consuming-repo edit.

## Decisions taken while authoring

- `self/gate.sh`'s shellcheck branch stays a bare informational skip rather than
  `record_skip`: shellcheck is not a dependency, and counting its absence as SKIPPED would
  make every self gate non-green on a machine without it.
- Plan numbers continue the global `self/` sequence (65–70) per `self/PROJECT_FACTS.md`,
  which is also ≥ the per-feature rule in `AGENT_PLANS.md`.

## Where the design rationale went

This feature was authored from a standalone proposal, `AGENT_TOOLING_TESTING_RESTRUCTURE.md`,
which carried a decisions table (D1–D8) naming the alternative each mechanism rejected. The
proposal was deleted once every part of it shipped and `RUNNER.md` / `AGENT_PLANS.md` became
the truth — it had drifted (it still documented the pause as exit 4, which shipped as 64).
Read it at `git show aa7cc7c:agentTooling/AGENT_TOOLING_TESTING_RESTRUCTURE.md` when you need
a rejected alternative rather than the shipped rule.

## Machine-readable

```json
{
  "slug": "test-first-levels",
  "plans": ["65-runner-sentinels-sonnet", "66-batch-level-loop-sonnet", "67-gate-label-and-skip-haiku", "68-doctrine-levels-sonnet", "69-verify-sonnet", "70-review-opus"],
  "branches": ["test-first-levels"],
  "session_window": {"from": "2026-08-20T00:00:00Z", "to": null},
  "exclude_sessions": []
}
```
