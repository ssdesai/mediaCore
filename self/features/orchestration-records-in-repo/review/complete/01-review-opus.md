# 01 — review: orchestration-records-in-repo

Review the direct build of this feature against its rulings, `self/features/
orchestration-records-in-repo/NOTES.md` → "Rulings" (written by the coordinator before the
build), and the manifest's opening paragraph. "No findings" is a legitimate verdict.

## What the feature was supposed to do

- `analysis/roots.py`'s `orchestrations_root` takes the mode: `--self` →
  `<agentTooling>/self/orchestrations/` (unchanged); otherwise the consuming repo's
  `plans/orchestrations/` beside `plans/features/`, honouring `--arm-root`.
- `orchestration-start.sh`, `orchestration-capture.sh`, `analysis/orchestration_capture.py`,
  `analysis/manifest.py --orchestration` and `analysis/report.py --orchestration` accept
  `--self` and choose the root by it; default is the consuming repo, as for
  `feature-start.sh`. Every agentTooling caller that means agentTooling's own records passes
  `--self` (tests, docs, templates' agentTooling usage, the harness).
- `report.py --orchestration`: a feature's `report` path resolves against the record's own
  repo root (`artifact_root(self_mode)`), `--checkout <repo>=<path>` winning for another repo.
  A consumer record whose features sit at `plans/features/<slug>/report.json` in that
  consumer is priced with no `--checkout` and no `../`.
- `hooks/orchestrator_role.py` finds an orchestrator record under either root, so a record in
  `plans/orchestrations/` is a role and a legacy one in the vendored
  `agentTooling/self/orchestrations/` keeps its role. `analysis/coordinator_check.py` reads
  both roots too. A coordinator record is still no role.
- Without `--self`, a slug found only at the legacy vendored location is refused by the
  record tools with the `git mv agentTooling/self/orchestrations/<slug>
  plans/orchestrations/<slug>` that moves it; nothing is written.
- `harness/program-stages.sh` reads an arm's record from the new path, falling back to the
  old one for an arm on an older agentTooling.
- Docs say where a record lives per mode: `LIFECYCLE.md` → "Orchestration records",
  `ORCHESTRATION.md`, `self/orchestrations/README.md`, `analysis/README.md`,
  `hooks/README.md`, `templates/plans/README.md` (generated into consumers),
  `templates/plans/features/TEMPLATE.md`'s `orchestration` bullet, the orchestrator briefs.

Excluded: moving any consumer's existing record; reading a legacy record in place; the hook
reading another checkout's agentTooling copy.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `roots.orchestrations_root` is the one definition; `hooks/orchestrator_role.py`'s mirrored
  constants and `orchestration-start.sh`'s match it, and `self/tests/orchestrator-role.sh` U3
  (or its successor) asserts the mirror for both roots.
- The record fence shape is unchanged: `{ slug, kind?, session, agent_tooling,
  session_window{from,to}, features[{repo, slug, session, branch, pr, report}] }`.
- `report.json` of a group report keeps its fields (`features[].total_usd`,
  `unpriced_reason`, `group_total_usd`, `unpriced_count`, `overhead`, `kind`).
- Existing `--self` behaviour and agentTooling's existing records under
  `self/orchestrations/` read and price exactly as before.
- Acceptance tests in `self/tests/` cover: a consumer-shaped tree (agentTooling vendored
  under a repo with `plans/features/<slug>/report.json`) where start → add-feature →
  report prices the feature with no `--checkout`; the legacy refusal and its `git mv` line;
  the role found under `plans/orchestrations/`. Each new test file has its row in
  `self/tests/README.md` and is recorded by `self/gate.sh`.
- Named constants for every new path or message; README index complete
  (`check-readme-index.py`).

## Verdict
