Verdict: escalated

# Review — close-after-filing, round 4

## What the batch was supposed to do

Round 3 escalated on its security audit's B3: a local `git replace <real> <fake>` made
`feature-close.sh` judge a BACKLOG-only stand-in commit while `git push` sent the real one,
which carried an unreviewed `hooks/policy.py` change. The A09 variant does the same under
`<slug>: review stamps`. Round 4's commit (`d9954df`) should:

- export `GIT_NO_REPLACE_OBJECTS=1` in `feature-close.sh` before its first git call;
- add tests K15a/b, one replace-ref stand-in under each subject;
- add test L2, which calls `audit_paths_in_range` directly;
- add a NOTES.md ruling on why `run-review.sh` needs no change;
- update the READMEs.

## Whether it does

Every contract in the brief holds:

- **The export comes first.** `export GIT_NO_REPLACE_OBJECTS=1` is at `feature-close.sh:74`,
  with a comment explaining it. That is before the `source` of `plan-runner-roots.sh` and
  `resolve_roots` (`:137–138`) and before the first git call (`:159`, inside a function;
  the first top-level call is `:186`). Child processes inherit it because it is exported.
- **K15a, K15b and L2 pass, and so do K1, K2 and K9.** The gate report shows
  `close-backlog: all checks passed` and its verdict line reads "all checks passed". Its one
  `exit: 1` is the advisory pricing-staleness check.
- **K15 can fail.** With replace refs on, the close would read the stand-in. It would accept
  the subject, and the index, resynced to the stand-in's tree, would look clean, so the close
  would reach the stray check. `refused_unreviewed` requires that the stray words are absent,
  so K15 would fail without the export.
- **The NOTES.md round-4 ruling on `run-review.sh` holds.** The `head=` stamp is a ref
  resolution, which a replace ref does not change. The close re-derives the subject loop, F1
  and `audit_paths_touched` itself, with replace refs off.
- **`self/tests/README.md` lists K15 and L2,** and the header comment of `close-backlog.sh`
  matches it.

## Fixed in this pass

Nothing.

## Escalated to the next round

**E1. The fix closes replace refs but not grafts, so the feature still accepts an unreviewed
change under `<slug>: backlog`.**

- **The finding.** The round-4 security audit found this as B06, a blocking finding
  (`self/features/close-after-filing/audit-report.md`, `Verdict: escalated`). It is
  restated here because it breaks the feature's core contract: "refuses everything else."
  I have not reproduced it; this pass does not run code. The audit gives the commands to
  reproduce it (`attack.sh … graft_backlog`), comparing the head copy with the base copy.
- **The mechanism.** `GIT_NO_REPLACE_OBJECTS` does not turn off `.git/info/grafts`.
  Take a real commit R that changes `docs-notes.txt` and the BACKLOG. A cyclic graft
  (`R F`, `F JD`, `JD JD^ F`) gives R a fabricated parent F whose tree differs from R's only
  in the BACKLOG. In `feature-close.sh`, `commit_changes_only` (`:159–163`) then diffs
  `R^..R` and lists the BACKLOG alone. `merge-base --is-ancestor` (`:255`) still holds, and
  the subject loop (`:291`) sees only R. The close accepts R, and `git push` sends R's real
  `docs-notes.txt` change.
- **Introduced by the feature.** The base refuses every `<slug>: backlog` commit. The same
  attack under `<slug>: review stamps` (the audit's B08) predates the feature.
- **Audit paths are still covered.** A graft cannot hide one: B07 is refused by the
  tree-range check.
- **The NOTES.md claim is too strong.** NOTES.md, "Round 4" ruling, says every call
  "resolves the objects `git push` sends". That is not true while grafts are in force.
- **What the next round should do.** This needs a design decision:
  - Next to the existing export at `feature-close.sh:74`, export `GIT_GRAFT_FILE=/dev/null`.
    The audit tried this as `scratch/headfix`.
  - Separately, decide whether a shallow repository (`.git/shallow`) should be refused or
    tolerated. Cloud containers can be shallow, so refusing outright needs a ruling.
  - Add K16a/b: a cyclic graft under each subject, with a non-audit payload, must be refused.
  - Amend the NOTES.md sentence to name both variables.

## Non-blocking notes

None.
