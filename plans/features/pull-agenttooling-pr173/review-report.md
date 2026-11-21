Verdict: clean

# Review (round 3): pull-agenttooling-pr173

## What the batch was supposed to do

Bring agentTooling main into mediaCore's vendored `agentTooling/` with `update.sh`: first
`25b332c9` (PR #173, which also carries #170–#172), then in round 3 `b9b7f2d4`, which adds
the upstream `orchestrator-move-length-cap` fix. The pull had to leave `agentTooling/`
byte-for-byte upstream's tree, keep the subtree trailer chain intact, keep `plans/` and the
`.claude/settings.json` wiring in sync, leave `src/`, `tests/` and the fixtures untouched,
and keep the gate green.

## Does it do it

Yes.

- **Vendored tree is upstream's.** `HEAD:agentTooling` and the tree of the squash commit
  `358887cb` ("Squashed 'agentTooling/' changes from 25b332c9..b9b7f2d4", trailer
  `git-subtree-split: b9b7f2d4…`) are both `d743d3b1`. Nothing under `agentTooling/` has an
  uncommitted change, so there is no local edit.
- **Out-of-scope paths are untouched.** `git diff origin/main...HEAD` is empty for `src/`,
  `tests/`, `fixtures/`, `.claude/`, `plans/README.md` and `plans/gate.sh`. The pull changes
  nothing under `agentTooling/templates/`, so the sync had nothing to write.
- **Gate.** `plans/gate-report.txt` was generated at 02:24:25Z, three seconds after the
  squash commit, and reports all checks passed: install, lint, fixture idempotence, the
  wheel's fixture, and tests (307 passed). Nothing was skipped.
- **Upstream fix is present.** The round-3 audit confirms the move is judged first, under
  its own 20,000-character cap, and that `roots.py` start-refusal and self-write now need the
  `ok` token. This removes the round-1/2 length-ordering regression that the owner's ruling
  had accepted.
- **The `tooling-wave-2026-11-18` orchestration record** arrives under
  `agentTooling/self/orchestrations/`. Its fence lists features from both agentTooling and
  mediaCore, so upstream's classifier (`roots.legacy_record_claim`) rates it `ambiguous`.
  That means it ships with agentTooling and is not moved, which is correct for a cross-repo
  wave that agentTooling ran.
- **Manifest `plans` list.** It names each stem once: 01–03 review and audit, six stems in
  batch order.

The round-3 **security audit** (`audit-report.md`) came back `escalated` on its own. Its
blocking finding is that if `agentTooling/analysis/roots.py` is replaced by a stub (or a
symlink to one) that prints `ok`, `orchestration-start.sh` goes on past a stranded record.
That is a trust issue in upstream code, and it can only be fixed upstream: an edit under
`agentTooling/` here would be undone by the next pull. This review does not rule on it. The
owner rules on the audit separately.

## Fixed in this pass

- `plans/features/pull-agenttooling-pr173/README.md` → "Plans": removed a stray, empty
  `| Plan | What it does |` table header that came before the prose line. Added the missing
  round-3 rows (`03-review-opus`, `03-audit-opus`), so the table matches the fence's
  `plans` list. Corrected the round-2 rows to their `review/complete/` paths and verdicts.
- Same file → "Deliberately excluded": the first bullet still said the length-check
  ordering regression was "accepted by the owner's ruling". That ruling was superseded in
  round 3. The bullet now says the regression is fixed upstream by
  `orchestrator-move-length-cap`, arrived with the `b9b7f2d4` re-pull, and was not edited
  here.

## Escalated to the next round

None.

For agentTooling's backlog, report only (not this repo's work):

- The round-1/2 non-blocking audit findings: an edited `analysis/roots.py` defeats the
  classifier, and only a record's last fence is counted.
- The `run-review.sh` duplicate-stem finding from an earlier round.
- Round 3's non-blocking items: `HTTPS_PROXY` / `GIT_SSL_NO_VERIFY` in the hook's
  environment are not checked by the own-push rule, and a stubbed `roots.py` still allows
  the move of a record that is not stranded. Both behave the same way on the base.

## Deviations from the brief

None
