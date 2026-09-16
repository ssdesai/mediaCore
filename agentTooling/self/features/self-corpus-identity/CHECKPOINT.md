# Checkpoint: self-corpus-identity (rework)

status: committed            planned | tests-written | implementing | gating | committed
updated: 2026-09-09T22:44:49Z
gate: all checks passed

## Slices
- [x] 1. item 3 — phase 10's fixture precondition (`10-pre`): $VHOST's origin really is
      $VENDOR_ORIGIN, checked right after the `remote add`
- [x] 2. item 1 — `vcapture_all` plus `10-annotated`/10h/10i/10j: the annotate-only `--all`
      in the VENDORED layout, ledger reseeded to a shared ledger's two declared-identity
      rows. 10i and 10j RED against main's analysis/ (NOTES.md → Rework → Red proof)
- [x] 3. item 2 — one upstream URL across roots.py / update.sh / README.md, as section
      8b-8d of self/tests/sync-check.sh (beside its existing read-only section 8)
- [x] 4. item 4 — `repo_identity(checkout_dir)`; capture_planning.py's `corpus_identity`
      closing paragraph and self/PROJECT_FACTS.md reworded as conceptual, both naming
      `corpus_identity` as the only remaining caller. No session-side call reintroduced
- [x] 5. self/tests/README.md rows (session-claims.sh, sync-check.sh), NOTES.md `# Rework`
- [x] gate green, commit

## Learned
- `--all` walks `feature_slugs` in name order, so `claim-here` is annotated before
  `claim-self-twin` is captured — the vendored phase's annotate assertions read a ledger
  the twin's own capture has not yet rewritten.
- Inheriting 10a-10g's ledger state would make 10i vacuous against `main`: the earlier
  runs leave `claim-here` under the consumer's origin there, so there is no
  `agentTooling` row for the self-exclusion to miss. The phase reseeds `$VLEDGER`.
- Red proof without touching VCS state: `git archive main analysis | tar -x -C <scratch>`
  beside this branch's `self/tests/{session-claims.sh,fixtures}` — `HERE` resolves to the
  scratch root and the fixture copies `main`'s modules.

## Resume
- cd /Users/sahildesai/dev/agentTooling-self-corpus-identity
- bash self/tests/session-claims.sh   # 10-pre, 10a-10j are this feature's
- bash self/tests/sync-check.sh       # 8b-8d are the rework's
- bash self/gate.sh                   # verdict must read: all checks passed
