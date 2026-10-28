# Checkpoint: cloud-close

status: committed
updated: 2026-10-05T16:22:54Z
gate: === gate: done — all checks passed === (110 ok, 0 failed, 0 skipped)

## Slices
- [x] acceptance tests — self/tests/feature-lifecycle.sh (T4 reworked, P2e at 5, new CB,
      CC, CD, F, X6), self/tests/sync-check.sh (pins at 5, 4f-4g v4 drift), fixture
      self/tests/fixtures/pr-v4.sh. Committed red as `cloud-close: acceptance tests`
      (31 + 6 red; every pre-existing check green).
- [x] 1. `manifest_branch` in plan-runner-roots.sh; feature-close.sh and
      feature-capture.sh read the branch from it
- [x] 2. forge.sh (pr-find, pr-open over gh api REST)
- [x] 3. pr.sh v5 (template + self), TEMPLATE_VERSIONS hash, feature-close exports
      FORGE_SCRIPT, gate.sh lists forge.sh
- [x] NOTES.md rulings; BACKLOG entry for the merge request / auto-merge
- [x] 4. Docs — root README (forge.sh row, plan-runner-roots/feature-close/capture rows,
      pr.sh v5, templates row, "Adopting the forge adapter"), LIFECYCLE.md,
      PROJECT_FACTS.md, self/tests/README.md + fixtures/README.md rows, templates README,
      self/README.md, manifest prose. RUNNER.md had no branch-S wording to change.
- [x] gate green, commit

## Learned
- The `gh` shim keeps GH_LOG as a forge-event log and GH_ARGV_LOG verbatim (NOTES.md).
- A bare `forge.sh` fallback is looked up on PATH; the fallbacks carry `./`.

## Resume
- Nothing to resume: the review pass is next (`./run-review.sh --self cloud-close`).
