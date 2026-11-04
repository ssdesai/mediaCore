# 98 — review: self-corpus-identity

## What the feature was supposed to do

Give agentTooling's own corpus (`self/features/`) a **declared** repo identity, so that a
capture run from a consuming repo's vendored copy labels a self-corpus manifest
`agentTooling/<slug>` and never `<consumer>/<slug>`. Read
`self/features/self-corpus-identity/brief.md` for the defect and the rulings, which are
settled and not reopened here:

1. `build_claimant_index` derived every corpus's identity with
   `repo_identity(features_dir.parents[1])`. For a vendored
   `<consumer>/agentTooling/self/features` that directory is the vendored `agentTooling/`,
   which `git` resolves to the consumer's origin, so agentTooling's own features entered
   the consumer's claim set under the consumer's identity while the ledger holds them as
   `agentTooling/<slug>`. `session_claim_intervals` dedupes on `(repo, slug)`, so both
   survived and one feature was counted twice, under a name that does not exist.
2. The remedy is a declared identity in `analysis/roots.py`, the same string
   `update.sh`'s `DEFAULT_REMOTE` names, used by **every** `--self` question of the form
   "which repo does this corpus / this feature belong to" — the claimant index, the
   capture's `share_ctx`, the ledger record and the frozen-record annotation. A `--self`
   operation never asks `git` who it is. `repo_identity` stays for the enclosing repo's
   own corpus and for "which repo did this session run in".
3. The ledger is not migrated: every agentTooling session claim already carries that
   exact string, because the standalone checkout's origin is that URL.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Read
`self/features/self-corpus-identity/NOTES.md` for the implementer's rulings and
`CHECKPOINT.md` for the shape of the build.

## Contracts to hold it to

- **One identity per corpus, one rule.** No call site under `--self` may still derive
  the self corpus's identity from `git`; no call site for the enclosing corpus may have
  moved onto the declared one. Two rules would drift back to the defect.
- **The key is the whole identity, not the display name.** Dedupe in
  `session_claim_intervals` still runs on `(repo, slug)`; the fix makes the manifest's
  `repo` equal the ledger's, it does not weaken the comparison to `repo_name`.
- **Nothing frozen moves.** No `planning.json` outside this feature's own directory may
  change. `git diff main...HEAD -- 'self/features/*/planning.json'` is empty.
- **The standalone checkout's answer is unchanged.** `capture_planning.py --self` in
  `~/dev/agentTooling` recorded `https://github.com/ssdesai/agentTooling.git` before
  and records the same after; the existing ledger entries dedupe against the new key.
- **The test stands up the vendored layout for real.** `.git` at the enclosing directory
  and not under `agentTooling/`, transcripts filed under the enclosing directory's
  project path, and the assertions read `share_basis` and the ledger — not internals.
  Every new assertion was proved red against the pre-change code; NOTES.md records the
  mutation. Spot-check one.
- **`manifest_pinned_subagents` keeps its slug-only lookup.** Its rationale paragraph in
  `analysis/README.md` and its docstring must describe the identity as it now is, not
  as it was.
- **README rules.** `analysis/README.md`'s roots and share paragraphs,
  `analysis/roots.py`'s module docstring, `self/PROJECT_FACTS.md`'s "Artifact root vs
  session root" gotcha and `self/tests/README.md`'s row for the test all say what the
  identity is and where it is declared. `update.sh` and `roots.py` name the same URL and
  each says the other does.

The highest-value finding is a missing assertion. Local fixes here; structural ones
escalated with the assertion that would have caught them.

## Verdict

What the feature was supposed to do; whether it does it; fixed here / escalated to the
next batch. "No findings" is a legitimate verdict.
