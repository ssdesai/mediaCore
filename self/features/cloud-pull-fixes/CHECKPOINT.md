# Checkpoint: cloud-pull-fixes

status: committed
updated: 2026-10-13T00:00:00Z
gate: === gate: done — all checks passed === (self/gate.sh, round 3, run by the rework implementer); individually green: template-versions, template-version-bump (B1-B15); bash -n on both changed .sh

## Slices
- [x] acceptance tests — self/tests/update-cloud-branch.sh (A), self/tests/template-version-bump.sh (B), self/tests/claimant-case.sh (C); committed red first
- [x] A. plan-runner-roots.sh started_features_on (lifted from session-start.sh); update.sh falls back to it lazily, refuses main explicitly, pull line names the feature
- [x] B. TEMPLATE_VERSIONS hashes all but the version line; all six re-recorded; cloud-setup.sh -> 2; template-versions.sh takes a templates dir; sync-check 1m expects 2; gate records the new tests
- [x] C. roots.py collapse_feature_mentions; capture_planning same_feature_ref + collapse in other_session_claimants / annotate_frozen_record / drift lookup / --for; report.py collapses; plan-runner-roots.sh feature_repo_name used by feature-start and feature-capture
- [x] docs: LIFECYCLE Propagate 2, README (Updating, Adopting cloud-setup v2, update.sh / templates / plan-runner-roots / session-start rows), templates/README, analysis/README, self/README, self/tests/README rows, BACKLOG (4 entries)
- [x] manifest prose and review brief (check-plans --self cloud-pull-fixes: 0 failed)
- [x] round 2 — tie template hashes to versions (review finding 01): template-versions.sh compares each template with origin/main's copy (hash recomputed by the current rule; same version + different content fails; lower version fails; new passes; base unavailable fails naming `git fetch origin main`); B8-B14 in template-version-bump.sh; TEMPLATE_VERSIONS header says bump first; READMEs; NOTES 20-23; re-review brief review/incomplete/02-review-opus.md
- [x] round 3 — compare templates at the fork point (escalation 02): template-versions.sh uses `git merge-base HEAD <base>` (tip fallback when it cannot be computed; `TEMPLATE_BRANCH_REPO` override); B15a-d in template-version-bump.sh; self/tests/README.md rows; NOTES 24-25; re-review brief review/incomplete/03-review-opus.md

## Learned
- The cloud origin itself is lowercase; the collapse, not name derivation, fixes C (NOTES 13).
- propagation-pull.sh / sync-check.sh copy update.sh without plan-runner-roots.sh: hence the lazy source.
- A committed table cannot tell a bump from a re-record; only a base comparison can (NOTES 20-21).

## Resume
- Nothing to resume. Next: the coordinator runs run-review.sh --self cloud-pull-fixes for round 3.
