Verdict: clean

# Review: coordinator-cost-records

## What the batch was supposed to do

The manifest's opening paragraph asks for a **coordinator record**. This is an orchestration record whose fence carries `"kind": "coordinator"`, for a session that coordinates several features through Agent delegates. Its own transcript is billed to no feature, so it needs a record of its own. The paragraph asks for six things:

1. `orchestration-start.sh <slug> --coordinator [--session] [--from]` writes the record. `from` defaults to the session's first transcript instant.
2. The record is no role: the lifecycle scripts and the hook refuse nothing in the coordinator or in its delegates, which share its session id. The reverse guard is skipped.
3. No double count: the capture prices the coordinator's own transcript plus only its own unclaimed `feature: none` delegates. Every other delegate goes in `subagents_not_priced`. The capture warns when a feature pins the coordinator's session.
4. `report.py --orchestration` carries `kind` and uses the coordination wording. `--checkout REPO=PATH` prices features in other repositories.
5. Launch-place doctrine in `ORCHESTRATION.md`, plus a cloud-only advisory from `feature-start.sh` (`analysis/coordinator_check.py`).
6. The `ablation-wave` record for this session.

## Does it do it

Yes. I checked each contract against the diff (base `origin/main`):

- **No role.** `hooks/orchestrator_role.py` `is_role()` skips a fence with `kind: coordinator` inside `record_for_session`, so `refuse_orchestrator_session` and the hook both pass it. A record with no `kind` is refused exactly as before. Covered by H10 (with and without `agent_id`) and K2. K2 also checks that a plain record is still refused.
- **Kind constant mirrored three times.** `roots.ORCH_KIND_KEY`/`ORCH_KIND_COORDINATOR`, `orchestrator_role.KIND_KEY`/`KIND_COORDINATOR` and `orchestration-start.sh`'s `COORDINATOR_KIND` all spell `kind`/`coordinator`, and each one names the others. `ORCH_KEY_ORDER` has `kind` right after `slug` (K1 asserts it).
- **Start.** `--coordinator` takes `from` from `manifest.py session-start`, falling back to the clock with a note. It skips the reverse guard. A `--from` that is not a `Z` instant is refused before anything is written. A plain start is unchanged apart from honouring `--from`. All of this is in K1.
- **No double count.** `price_session_in_window(subagent_filter=…)` adds `subagents_not_priced` only when a filter is passed. The orchestrator path passes none and is unchanged (K3's `as-orch` case). `coordinator_owns` requires a `KIND_NONE` header and an id in neither the ledger nor any manifest's `subagents`.
- **Report.** `kind` is in `report.json`, the wording is chosen per kind, and `--checkout` is resolved per repo. The three usage errors and a plain record's wording are all in K4.
- **Record.** In `self/orchestrations/ablation-wave/`, `README.md`, `planning.json`, `report.json` and `report.md` agree on kind, session, window, overhead ($44.3088), the 14 unpriced delegates and the one own delegate (`ab83534d…`), the 8 priced plus 1 unpriced features, and the group total ($182.1908). These match `NOTES.md` → Facts.
- **Tests and gate.** `coordinator-records.sh` is in `shell_scripts` and has its `record` line. `self/gate-report.txt` says "all checks passed" and lists no skipped self check.
- **READMEs.** `analysis/`, `hooks/`, `self/orchestrations/`, `self/tests/`, the root `README.md`, `LIFECYCLE.md` and `ORCHESTRATION.md` all describe the change. `NOTES.md`'s rulings match the diff.

## Fixed in this pass

- `feature-start.sh` (the advisory block near line 1058) gated `coordinator_check.py` on `(( COORDINATOR ))`. That flag is also set by a **local** start launched on the feature's branch, but the contract and every document (manifest item 5, root `README.md`, `analysis/README.md`, the module docstring, `NOTES.md`) say the check runs under the cloud profile only. I changed the condition to `profile_is_cloud && [[ -n "$ROUTER_SESSION" ]]` and added a comment explaining it. Every cloud start already takes the coordinator path, so cloud behaviour (A1j, W1) is unchanged. `bash -n` is clean. The gate ran before this edit and was not re-run.

## Escalated to the next round

None.

## Notes (not blocking)

- No test asserts the cloud-only gate above. A local launched-on-branch start that prints no `--coordinator --session` line would pin it, and could be added cheaply to `self/tests/cloud-start.sh`'s local cases.
- `report.py` `compute_orchestration_report` still prices an entry from another repository against the agentTooling root when a file exists at that path. Only when no such file exists does it fall back to the `--checkout` reason. This is documented in the docstring and keeps pricing working for existing records, but it is looser than the brief's wording ("unpriced with the `--checkout` reason").
- The capture's warning for the ledger's session section (`session_claimants`) has no test. Only the manifest `sessions` pin case is asserted (K3).
