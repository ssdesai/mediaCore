# Checkpoint: orchestration-records-in-repo

status: round 3 built (merge of origin/main committed, R3.1-R3.6 done); awaiting gate and review
updated: 2026-11-13T00:00:00Z
gate: not run (the coordinator's)

## Slices
- [x] acceptance tests — self/tests/orchestration-records-in-repo.sh, row in self/tests/README.md, record in self/gate.sh (committed alone; written after the code, so green not red — NOTES 13)
- [x] 1. roots.py `orchestrations_root(self_mode)`, `legacy_record_refusal`, `all_orchestrations_roots`
- [x] 2. manifest.py / orchestration_capture.py / report.py `--self`; report resolves against artifact_root; home repo case-insensitive
- [x] 3. orchestration-start.sh / orchestration-capture.sh `--self`; hooks/orchestrator_role.py both roots; coordinator_check.py
- [x] 4. harness/program-stages.sh fallback + smoke.sh path
- [x] 5. existing callers pass --self (orchestration-records.sh, coordinator-records.sh, orchestrator-role.sh U3/U3b/U3c)
- [x] 6. docs: LIFECYCLE, ORCHESTRATION, READMEs (self/orchestrations, analysis, hooks, README, harness, templates/plans, self, tests), TEMPLATE.md, briefs, BACKLOG note

## Round 2 (rulings 14-17)
- [x] R2.1 acceptance tests (self/tests/orchestration-records-in-repo.sh extended; committed alone; 21 checks red against a `git archive HEAD` copy)
- [x] R2.2 roots.py: `is_stranded_record`, `record_refusal`, `standalone_refusal`, `orchestration_home_repo` (moved from report.py), `roots.py stranded <slug>` CLI
- [x] R2.3 callers: report.py, manifest.py, orchestration_capture.py -> record_refusal; orchestration-start.sh shell mirror (capture goes through python)
- [x] R2.4 hooks/orchestrator_role.py record_roots; coordinator_check.py `--self` pass-through (feature-start.sh SELF_FLAG)
- [x] R2.5 docs: self/orchestrations/README.md, analysis/README.md, hooks/README.md, LIFECYCLE.md, ORCHESTRATION.md, templates/plans/README.md, self/tests/README.md, feature README; NOTES 18-22
- gate: not run (the coordinator's). Round 2 ran green: orchestration-records-in-repo, orchestration-records, coordinator-records, orchestrator-role, hook-orchestrator-role, hook-brief-header, orchestrator-brief, routing-record, feature-lifecycle, cloud-start, sync-check, propagation-pull, template-versions, readme-index, hook-wiring; py_compile, bash -n, check-readme-index.py. harness/ untouched: smoke not run.

## Round 3 (merge of origin/main: hook-role-hardening)
- [x] R3.1 merge origin/main; resolve analysis/manifest.py, hooks/README.md, hooks/orchestrator_role.py, self/tests/README.md (orchestrator_role: every source over both roots — `record_bases`, `committed_role_record`, `ledger_record_path`)
- [x] R3.2 role hook: committed-record history and ledger-era checks span both roots (self/orchestrations always; ../plans/orchestrations from a vendored copy only) — code in the merge; R11 in orchestration-records-in-repo.sh; NOTES 23-26
- [x] R3.3 orchestrator allowlist admits the record tools' `--self` (report.py, orchestration-capture.sh, manifest.py --orchestration) — ORCHESTRATOR_SELF_FLAG; H25; NOTES 27
- [x] R3.4 consumer ask rule (wire-settings.py) covers plans/orchestrations; audit paths and docs true for both roots — NOTES 28-29; hook-wiring.sh ASK
- [x] R3.5 tests extended to the new root (orchestrator-role.sh, coordinator-records.sh, hook-orchestrator-role.sh as needed); README entries; NOTES round-3 rulings — main's new start calls pass --self (NOTES 30); new root in R11/H25
- [x] R3.6 run the orchestration/role/hook tests, py_compile, bash -n, check-readme-index.py — all green: orchestration-records-in-repo, orchestration-records, coordinator-records, orchestrator-role, hook-orchestrator-role, hook-brief-header, hook-wiring, security-audit, orchestrator-brief, routing-record, feature-lifecycle, allow-repo-commands; py_compile (orchestrator_role, wire-settings, allow-repo-commands.sh, manifest); bash -n of changed .sh; check-readme-index.py (gate's --root/--ignore). harness/ untouched in round 3: smoke not run.
- gate: not run (the coordinator's).

## Learned
- The shell policy refuses `sed -i`/heredoc writes: use Edit/Write.
- `report.py` takes the home repo name from `capture_planning.corpus_identity` -> `repo_display_name` (lazy import).
- plan-runner-roots.sh `resolve_roots` gives SELF_MODE/REPO_DIR/SELF_ARG to the start script.
- harness smoke's arm is the committed HEAD: run it after committing, not before.

## Ran (green)
orchestration-records-in-repo.sh, orchestration-records.sh, coordinator-records.sh, orchestrator-role.sh, hook-orchestrator-role.sh, hook-brief-header.sh, orchestrator-brief.sh, routing-record.sh, feature-lifecycle.sh; py_compile of changed .py; bash -n of changed .sh; check-readme-index.py (with the gate's --root/--ignore). harness/tests/smoke.sh: see the coordinator's result (run in background after the commit).

## Resume
- Re-run the tests above; then the gate (`GATE_RESUME=1 ./self/gate.sh`) is the coordinator's.
