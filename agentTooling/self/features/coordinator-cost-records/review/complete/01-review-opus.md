# 01 — review: coordinator-cost-records

A hand build: the coordinator built this feature itself, so there is no build plan and no
builder's brief. Review the diff against the spec below — never against the builder's
account of it — and say "no findings" when there are none: that is a legitimate verdict
(AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The spec is the manifest, `self/features/coordinator-cost-records/README.md`: its opening paragraph (what
the feature delivers and why) and its "Deliberately excluded" list. Read it before the
diff. If that paragraph is still the template's `<One paragraph: …>` placeholder there is
no spec to review against: say so and return `Verdict: escalated`.
`self/features/coordinator-cost-records/NOTES.md` is the builder's record — its rulings and what it left
undone. Read it after the diff, to check its claims, not to learn what was intended.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every behaviour the spec names is implemented, and nothing the spec excludes is.
- New or changed behaviour has a test that would fail without it, and the gate
  (`self/gate.sh`) is green on this tree: its report says so, and the review does
  not re-run it.
- Every folder the diff touches has a README that still describes it (CONVENTIONS.md →
  "Keeping READMEs up to date"); a generated README is changed only through the file its
  header names.
- No magic literal in new code that CONVENTIONS.md → "Named constants" would name.
- NOTES.md's claims hold: what it says was done is in the diff, and what it says was left
  is not silently half-done.

This feature's own contracts:

- **No role.** `hooks/orchestrator_role.py`'s `record_for_session` returns None for a record
  whose fence has `"kind": "coordinator"`, so `plan-runner-roots.sh`'s
  `refuse_orchestrator_session` and the hook's `orchestrator_reason` pass that session —
  including a subagent payload carrying the coordinator's `session_id` plus an `agent_id`.
  A record with no `kind` is refused exactly as before.
- **One kind constant, mirrored three times.** `analysis/roots.py`'s `ORCH_KIND_KEY` /
  `ORCH_KIND_COORDINATOR`, `hooks/orchestrator_role.py`'s `KIND_KEY` / `KIND_COORDINATOR`
  and `orchestration-start.sh`'s `COORDINATOR_KIND` spell the same `kind` / `coordinator`.
  `analysis/manifest.py`'s `ORCH_KEY_ORDER` keeps `kind` right after `slug`.
- **The start.** `orchestration-start.sh --coordinator` writes `kind`, `from` = the
  session's first transcript instant (`manifest.py session-start`) unless `--from` is
  given, and skips the reverse guard; `--from` that is not a `Z` instant is refused, writing
  nothing. A plain start (no `--coordinator`) writes what it wrote before, `from` now.
- **No double count.** For a coordinator record `orchestration_capture.py` prices the main
  transcript plus only the delegates whose brief opens `feature: none — …` and whose id is
  in neither the claims ledger's `subagents` nor any readable manifest's `subagents`; every
  other in-window delegate is in `subagents_not_priced`. An orchestrator's capture is
  unchanged except for the added `kind` key (`price_session_in_window` with no
  `subagent_filter` prices every delegate and writes no `subagents_not_priced`).
- **The report.** `report.json` gains `kind`; `--checkout REPO=PATH` resolves an entry of
  REPO against PATH; an entry outside `agentTooling` with no checkout is unpriced with the
  `--checkout` reason; `--checkout` without `--orchestration`, with no `=`, or naming no
  directory is a usage error. A plain record's report reads as before.
- **The advisory.** `feature-start.sh` runs `analysis/coordinator_check.py` only under the
  cloud coordinator branch and only prints `  warn` lines; it never changes the start's exit
  status or what it writes.
- **The record.** `self/orchestrations/ablation-wave/` holds `README.md` (kind coordinator,
  session `4cba07a3-…`), `planning.json`, `report.md`, `report.json`, consistent with each
  other.
- **Tests.** `self/tests/coordinator-records.sh` (K1–K5) is in `self/gate.sh`'s
  `shell_scripts` and has a `record` line; `hook-orchestrator-role.sh` H10 and
  `cloud-start.sh` A1j/W1 are the added cases.

## Verdict
