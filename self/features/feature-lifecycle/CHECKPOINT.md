# Checkpoint: feature-lifecycle

status: committed          planned | tests-written | implementing | gating | committed
updated: 2026-09-03T19:54:18Z
gate: all checks passed

## Slices
- [x] 0. manifest, review brief, checkpoint, notes; triage moved in (commits 1–2)
- [x] 1. index: README by category, EXPERIMENTS.md → harness/, retire migrate-plans-layout.sh (items 1–3)
- [x] tests first: feature-lifecycle.sh (49 red), capture-guard.sh 15–16 (+14b re-fixtured), subagent-capture.sh 17, direct-timing.sh 6 — all red, old phases green
- [x] 2. capture: repo_match for R-<slug>, cwd on entries, three-cause warning, session pins + selected_by, --list-sessions, zero refusal, base ignored (items 4–6, 8)
- [x] 3. report.py method hand; analysis/manifest.py (items 7, 12)
- [x] 4. plan-runner-roots.sh manifest_field; plan-runner-lib.sh @@TODO@@ refusal; run-review.sh FEATURE_BASE (items 8, 11, 13)
- [x] 5. feature-start.sh; templates/plans/worktree-setup.sh; self/worktree-setup.sh; sync-plans.sh seeding (items 9–10)
- [x] 6. feature-close.sh (item 12) — DELEGATED to an opus implementer with pr.sh, gate.sh wiring and the tests README; also fixing S1j
- [x] 7. pr.sh template + self (item 13) — same delegate as 6
- [x] 8. DELEGATED to an opus implementer: LIFECYCLE.md; prune AGENT_DIRECT, ORCHESTRATION, AGENT_PLANS, analysis/README; TEMPLATE.md; features READMEs (items 14–15)
- [x] 9. same delegate as 8, except self/gate.sh and self/tests/README.md (delegate 6): READMEs and field lists for every folder touched; self/gate.sh shell_scripts + record; self/tests/README.md row (item 16)
- [x] gate green; commit

## Learned
- The review runner stamps pr_opened and pass_end after pr.sh commits, so a worktree is never clean after a green pass; close carries those lines home (ruling in NOTES.md).
- timestamps-are-utc.sh phase 4 read the $0.00 file a nothing-matched capture used to write; a sonnet delegate is re-fixturing it.
- Delegates inherit this session's branch (main) and cwd; pin their ids in the manifest's `subagents` before close (`capture_planning.py --self --list-subagents --unclaimed`).
- Close captures with the window still open, then stamps `to`: `to = now` excludes nothing, and a refused capture must leave the manifest clean.
- The running session's id is in $CLAUDE_CODE_SESSION_ID, so the pin in item 9 is automatic.
- capture's manifest reader is parse_manifest (last json fence); unknown keys pass through.
- report.py KNOWN_METHODS at ~305; direct branches at 334, 689, 1071, 1106.
- capture-guard.sh builds transcripts with fixtures/transcripts/build-transcript.sh under a fake HOME; the project dir name is the resolved path with / → -.

## Resume
- Worktree: /Users/sahildesai/dev/agentTooling-feature-lifecycle on branch feature-lifecycle; primary stays on main.
- git -C <worktree> log --oneline main..HEAD; git -C <worktree> status --short
- Tests: bash self/tests/feature-lifecycle.sh (red until slices 4–7); bash self/gate.sh
- Stamp: ./stamp-timing.sh --self feature-lifecycle checkpoint status=<status>
