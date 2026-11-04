# Checkpoint: sweep-retirement-and-audit-fixes

status: committed          planned | tests-written | implementing | gating | committed
updated: 2026-09-17T17:40:00Z
gate: all checks passed    (self/gate-report.txt; 795 ok lines, one skip: shellcheck is
                            not installed on this machine — environmental, as on the base)

## Slices
- [x] acceptance tests — self/tests/feature-lifecycle.sh, self/tests/check-plans.sh,
      self/tests/audit-fixes.sh (committed 49c2e7b; all three green)
- [x] 1. report.py --all renders every planning.json with no report.json, says how many
- [x] 2. check-plans.sh check 7 extended to window ordering
- [x] 3. run-batch.sh lints the inferred slug once the build pass has resolved it
- [x] 4. RUNNER.md review cap $5.00 -> $7.00 (two places)
- [x] 5. run-review.sh commits its own pass before pr.sh (+ pr.sh contract comments)
- [x] 6. feature-capture.sh: annotation at capture (capture_planning.py --annotate-frozen)
      and the residue listing; stray_paths accepts another feature's cost records
- [x] 7. delete sweep.sh and self/tests/sweep.sh; gate.sh entries; every live reference
- [x] 8. docs: LIFECYCLE step 7 -> Propagate, root README rows, analysis/README,
      PROJECT_FACTS, self/README, self/tests/README, RUNNER.md, templates
- [x] 9. NOTES.md (14 rulings), three self/BACKLOG.md entries, the manifest's Slices
      table, self/features/README.md row, templates/plans/README.md pr.sh row, the
      surviving `$5.00` in RUNNER.md

## Learned
- The resume found the whole of 1–8 built but uncommitted and the checkpoint stale at
  `tests-written`; all three named tests passed on the tree as it stood, so the build
  needed no repair — only slice 9 and the gate.
- The ledger-only entry point is `capture_planning.py --annotate-frozen [--except SLUG]`
  (`annotate_corpus`); `feature-capture.sh` step 5 loops over the slugs it prints.
- An annotated sibling's record needs both a `stray_paths` exemption (ANNOTATION_FILES)
  and its own `git add` path; both built.
- template-versions.sh hashes templates with comment lines stripped: editing pr.sh's
  contract comment needs no version bump.
- `--list-sessions --unclaimed` already excludes routers (`is_router_lines`); the residue
  listing inherits that for free.

## Resume
- Nothing left: the branch carries `sweep-retirement-and-audit-fixes: retire the sweep,
  fold in the audit fixes` on top of the acceptance-tests commit, and the review pass
  (`109-review-opus`) is next.
- Tests: bash self/tests/feature-lifecycle.sh; bash self/tests/check-plans.sh;
  bash self/tests/audit-fixes.sh
- Gate: ./self/gate.sh (a few minutes)
