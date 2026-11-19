Verdict: clean

# Review — orchestration-records-in-repo, round 3 (merge of main)

## What the batch was supposed to do

Merge `origin/main` (which gained `hook-role-hardening`, PR 140) into the feature after
round 2's clean verdict, resolving the four conflicted files (`hooks/orchestrator_role.py`,
`analysis/manifest.py`, `hooks/README.md`, `self/tests/README.md`) so that neither feature loses
behaviour. The orchestrator role must read records under `self/orchestrations/` and, from a
vendored copy only, the consuming repo's `plans/orchestrations/` (rulings 4, 16), with every
check hook-role-hardening added (role by shape, every fence, session-id check, committed-record
role, ledger, orchestrator allowlist) applied to both roots.

## Does it

Yes. Read from `git show --remerge-diff 168e2d3` and `git diff 168e2d3 f502554`:

- **`hooks/orchestrator_role.py`** — the resolution composes the two sides rather than picking
  one. `record_bases` is the one definition of the roots (self first, consumer only when the
  tooling dir has no `.git` of its own); `record_roots`, the working-tree scan (`names_role`,
  every fence), the history source (`committed_role_record`, one bounded
  `git -C <base> log --relative -- <rel>` per root, shallow-boundary skip kept) and the ledger
  (`ledger_record_path`) all walk it. R4's "every source is asked; unreadable only when none
  names the session" is preserved across roots. The rename `committed_role_slug` →
  `committed_role_record` leaves no stale references outside feature records.
- **`analysis/manifest.py`** — keeps both the `--self` scope / legacy-location refusal and
  main's coordinator-shape refusal (`session=`/`branch=` on a coordinator record).
- **Follow-ups** — `orchestration-start.sh` validates the session id before choosing a root, so
  the K1 checks hold for the consumer root too; the ledger append is root-independent. The
  orchestrator allowlist admits `--self` as the first argument of `manifest.py`/`report.py`
  only (ruling 27); the consumer ask rules gain `Edit(**/plans/orchestrations/**)` while keeping
  the legacy one (ruling 28), mirrored in `self/tests/hook-wiring.sh`.
- **Tests** — hook-role-hardening's start calls in standalone fixtures now pass `--self`
  (ruling 30). This makes them stronger, not weaker: before, the refusal cases passed because of
  the standalone refusal, not the session-id check they name. The new tests cover both roots:
  `orchestration-records-in-repo.sh` R11 (history after edit or delete, ledger path with and
  without a folder, the real start's ledger, a standalone checkout ignoring its parent's history)
  and `hook-orchestrator-role.sh` H25 (the `--self` allowlist shapes, and a `plans/orchestrations`
  orchestrator denied a build script and an implementer brief with the role reason).
- **READMEs** — `hooks/README.md` (orchestrator_role entry, allowlist table, ask rules) and
  `self/tests/README.md` (R11, H25) match the merged code. Rulings 23–30 are recorded in
  `NOTES.md`.
- **Gate** — `self/gate-report.txt` (level final): "all checks passed", nothing SKIPPED. The
  one non-zero exit is the advisory "pricing rate history is current" check. The gate does not
  count it as a failure, and it is unrelated to this feature.

## Fixed in this pass

None.

## Escalated to the next round

None.
