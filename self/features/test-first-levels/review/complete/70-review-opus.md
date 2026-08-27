# 70 — Review `test-first-levels`

Feature `test-first-levels`, plan 6 of 6. The feature reorders a batch into **levels** —
tests first, then per-layer build plans — with the free mechanical gate run at every level
boundary via a sentinel plan file `NN-gate.md`, so a cross-layer seam fails at the
boundary it crosses instead of at review one batch later.

Diff against `main`. The batch was supposed to implement §3 and §4 of
`AGENT_TOOLING_TESTING_RESTRUCTURE.md` — read that document's §1 decisions table first;
each decision is a contract this diff must honour, and D8 (gate stays advisory, verify
stays single, verify and review stay separate) is the one most easily broken by accident.

Hold the diff to:

- **The sentinel bypasses every sidecar.** No `.progress.md`, `.stream.jsonl` or
  `.usage.json` can be created for `NN-gate.md`, and nothing in `analysis/` can ever see
  it. Read `finalize_plan` and the Phase 2 loop as changed; confirm the sentinel path
  cannot reach `run_plan`.
- **Resume semantics survive.** Phase 1 (`inprogress/`) is untouched and a sentinel can
  never be there. An interrupted run after exit 4 re-enters cleanly.
- **The lock-step between runners.** `run-plans.sh` exit 4 ⇄ `run-batch.sh`'s loop ⇄
  `run-verify.sh --up-to`: the flag order, the slug source (`FEATURE_SLUG_OUT` kept across
  iterations), and `level_nn` derivation must agree. A mismatch here is exactly the
  cross-file seam this feature exists to catch — say if you find one.
- **`list_plans` is shared.** `PLAN_MAX_NN` must be unset in `run-plans.sh` and
  `run-review.sh`; confirm nothing else sources a stale value.
- **bash 3.2.** Every new construct.
- **Doctrine ⇄ mechanics.** `AGENT_PLANS.md`, `RUNNER.md`, `README.md`,
  `templates/README.md`, `self/features/README.md`, `self/PROJECT_FACTS.md` describe the
  same exit code, flag, filename and sentinel rule the code implements.

Never run anything; verify already did. "No findings" is a legitimate verdict. Write
`self/review-report.md` for the human approving the PR: what the batch was supposed to
do, whether it does it, then two lists — fixed here, escalated to the next batch — with
the highest-value escalation being any invariant above that has no check and the
assertion that would cover it.
