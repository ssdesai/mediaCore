Verdict: clean

# Review, round 2: pull-agenttooling-pr173

## What the batch was supposed to do

Pull agentTooling `main` at `25b332c9` (PR #173, which also brings in #170–#172) into
mediaCore's vendored `agentTooling/` with a squashed subtree pull from split `a130257f`.
The pull had to:

- leave `agentTooling/` exactly as it is upstream,
- keep the trailer chain intact,
- leave `plans/` and the `.claude/settings.json` wiring in sync,
- not touch `src/`, `tests/` or the fixtures,
- and keep the gate green.

Because the pull changes `hooks/`, it also gets the security audit.

## Does it do it

Yes.

- **Upstream tree:** `HEAD:agentTooling` and the squash commit `38d1e381` have the same
  tree (`f59c4443…`). So `agentTooling/` is upstream's tree with no local edit.
- **Trailers:** the squash commit carries `git-subtree-dir: agentTooling` and
  `git-subtree-split: 25b332c9…`.
- **Untouched paths:** `git diff origin/main...HEAD --stat` touches nothing under `src/`,
  `tests/`, `fixtures/`, `.claude/` or the synced `plans/` templates. The only files
  outside `agentTooling/` are this feature's own records under
  `plans/features/pull-agenttooling-pr173/`.
- **Gate:** `plans/gate-report.txt` says all checks passed (307 tests, lint clean, fixture
  idempotent). I did not re-run it. The round-2 commits after that report changed only
  files under this feature's folder.
- **READMEs:** `plans/features/README.md` is generated. `plans/PROJECT_FACTS.md` already
  covers the `pull-agenttooling-pr<N>` folder pattern, so no README index needs a new line.
- **Owner's ruling:** the round-1 audit's blocking finding is accepted for this pull and is
  not escalated here. In `agentTooling/hooks/allow-repo-commands.sh` (from #172), the
  orchestrator's own-record move is checked before `ORCHESTRATOR_MAX_LINE_CHARS`. As a
  result, a move padded past 20,000 characters is allowed where origin/main denies it.
  The ruling was relayed by the orchestrator session `tooling-wave-2026-11-18`. The fix is
  a separate agentTooling feature and is not edited here.
- **Non-blocking audit findings, for agentTooling's backlog only:**
  - an edited `analysis/roots.py` defeats the new classifier;
  - the record check counts only the last fence of a record.

## Fixed in this pass

- **Duplicate plan stem in the manifest.** The `plans` list in
  `plans/features/pull-agenttooling-pr173/README.md` (uncommitted, written by the runner
  this round) listed `"02-audit-opus"` twice. `analysis/report.py` (around line 449) loads
  one usage record per listed stem and does not remove duplicates. The round-2 audit's
  cost would therefore have been counted twice in this feature's report. I removed the
  duplicate.
  - **Cause, for agentTooling's backlog:** `queue_security_audit` in
    `agentTooling/run-review.sh:440-447` adds the audit stem to `plans[]` without checking
    whether it is already there. The coordinator had already listed `02-audit-opus` in
    commit `42704dba`. The conformance path a few lines down (`run-review.sh:504-508`) does
    check for an existing entry, with a comment saying `set-plans` does not remove
    duplicates. The audit path needs the same check.
  - **Missing test:** an agentTooling self-test should assert that `run-review.sh`, run
    against a manifest that already lists the audit stem, leaves the stem listed once.
- **Template placeholders left in the manifest.** The same README still had the template's
  placeholder Plans table (`<one line>`) and the "Levels" and "Contracts across levels"
  sections. Both of those sections say to delete them when the batch has a single level.
  I replaced the table with this feature's four real review and audit plans and deleted
  the two sections.

## Escalated to the next round

None.

## Deviations from the brief

None
