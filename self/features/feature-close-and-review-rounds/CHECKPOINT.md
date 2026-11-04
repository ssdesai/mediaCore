# Checkpoint: feature-close-and-review-rounds (slice A)

status: gating          planned | tests-written | implementing | gating | committed
updated: 2026-09-17T19:30:24Z
gate: all checks passed

## Slices
- [x] acceptance tests — self/tests/feature-lifecycle.sh (V1–V3, X1–X3, RD, B1–B2, rewritten
      T3/T4/T5/P2), self/tests/sync-check.sh (1d/1f/4b/4d), self/tests/template-versions.sh
      (44 red before the build, all green after)
- [x] A1. the verdict in run-review.sh (`Verdict:` in the prompt and read back, escalations
      copy, `<slug>: review round N`, plan_end `verdict=`/`head=`, no PR, no capture, the
      next step printed)
- [x] A2. rounds in the stamps (plan-runner-roots.sh `stamp_timing` + `TIMING_ROUND` fixed
      at `pass_start` in plan-runner-lib.sh; stamp-timing.sh computes fresh)
- [x] A3. feature-close.sh — the real script (five refusals, PR body = report + Rounds
      table, `pr_opened`, capture, `pr.sh --merge-request` last, re-runnable)
- [x] A4. pr.sh template-version 4 in templates/plans/pr.sh and self/pr.sh, TEMPLATE_VERSIONS
      hash re-recorded
- [x] A5. run-batch.sh: clean → close, escalated/unreadable → brief path + exit 1, no review
      plan → exit 0 as before
- [x] A6. docs (LIFECYCLE steps 5 Review / 6 Close / 7 Merge, AGENT_DIRECT, RUNNER,
      AGENT_PLANS, ORCHESTRATION, root README rows + the adoption section, templates/README,
      templates/plans/README, self/PROJECT_FACTS, self/README, self/tests/README, the
      Superseded note in DESIGN-2026-09-16 §3.2)
- [x] C. NOTES.md rulings, self/BACKLOG.md (PR_AUTO_MERGE entry removed, three added,
      the hooks entry re-scoped), self/features/README.md row

## Learned
- `plan_end` is stamped by `finalize_plan` before the runner's own commit, so `head=` can
  only be attached by deferring that one stamp (`PLAN_END_DEFERRED`/`flush_plan_end`).
- The review pass necessarily leaves `timing.jsonl` dirty; the close commits it as
  `<slug>: PR` before pr.sh, which keeps pr.sh's fallback commit the no-op it is meant to be.
- `round` is appended as the LAST key of a timing line: several tests read a line back by
  its key order (`"event":"pass_start","queue":"auto"`).
- A batch over a feature with no review plan must still exit 0 — the empty review queue has
  always been a clean no-op (level-sentinel.sh, tiered-gates.sh, batch-sigpipe.sh all rely
  on it).
- Slice B's `report.py --self <slug> --rounds-md` is in the tree and exits 0 with the table
  on stdout; the close's PR body was checked against it.

## Resume
- Tree: dirty, uncommitted, on branch feature-close-and-review-rounds in its worktree; the
  coordinator reviews the diff, commits and stamps `committed`.
- Tests: `bash <worktree>/self/tests/feature-lifecycle.sh` (and `sync-check.sh`,
  `tiered-gates.sh`, `level-sentinel.sh`, `batch-sigpipe.sh`, `template-versions.sh`).
- Gate: `<worktree>/self/gate.sh`, then read `self/gate-report.txt`.
