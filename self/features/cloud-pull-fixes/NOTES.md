# Notes: cloud-pull-fixes

Rulings made during the direct build, each with its reason. The brief is the spec; these
are what it left open.

## A. update.sh on a cloud-started feature

1. **The cloud fallback matches `branches[0]`, not "any entry of `branches`".** It reuses
   the one reader every other script asks (`manifest_branch`, through the new
   `plan-runner-roots.sh` `started_features_on`, lifted out of `session-start.sh`'s
   `started_feature`), and `branches[0]` is "the feature's branch" everywhere else
   (`feature-close.sh`, `session-start.sh`, `feature-start.sh`'s one-feature refusal). A
   later entry is a historical name kept for cost matching, not the branch a pull lands on.
2. **The branch-named manifest still wins first**, so the local layout is unchanged and
   the lookup (and its `git grep`) runs only when that path is absent.
3. **Tracked manifests only**, as `session-start.sh` already required: an untracked
   manifest is a start nobody committed. It is refused as "not a started feature" before
   the dirty-tree refusal, so the message names the real problem.
4. **`plan-runner-roots.sh` is sourced lazily, inside `main()` and only on the fallback.**
   Before the pull, so the pull overwriting it mid-run cannot matter; and lazily so a
   checkout (or a test fixture) carrying update.sh alone keeps its local-layout behaviour.
   A missing library reads as zero matches, which refuses — fail closed.
5. **`main` is now refused explicitly** (`PROTECTED_BRANCH`), not only because no
   `plans/features/main/README.md` exists: with the fallback a manifest naming `main`
   would otherwise be accepted.
6. **The `pull` line gains `feature <slug>`** after the branch, in both layouts.

## B. template version stamps

7. **The ledger already existed** (`templates/plans/TEMPLATE_VERSIONS`,
   `self/tests/template-versions.sh`, blocking) — but hashed the file with comment-only
   and blank lines stripped, by an earlier deliberate ruling that a doc edit should be
   free. That ruling is what let PR 85 through. **Reversed: the hash now covers the whole
   file except its `# template-version:` line.** A seeded script's comments are the
   consuming repo's only documentation of how the script is run (cloud-setup.sh's said it
   was the hook; it no longer is), so a comment change is a change a consumer must merge.
   The cost — a typo fix is a bump and a one-line DRIFT in every consumer — is accepted.
8. **Committed ledger over git history**, as the brief preferred: works in a shallow clone,
   needs no base ref, and the table's header holds the exact re-record command (which
   `template-version-bump.sh` B6 reads and runs, so the documented recipe is the tested one).
9. **Only cloud-setup.sh was bumped (1 → 2).** An audit of history found it the only
   template changed since its version line last moved; the other five were re-recorded at
   their current versions under the new hash rule, which forces no consumer DRIFT.
10. **The other five templates' headers still say "bump when the body changes".** Rewording
    them is itself a bump and a DRIFT line in every consumer for no behaviour; left for the
    next real bump of each (BACKLOG).
11. **sync-plans.sh's compare is exact equality** (`cver == tver`, printed as `<`), so a
    consumer at 1 reads `DRIFT … (template-version 1 < 2; …)`. The hand-merge is the new
    header plus the version line; a consumer whose copy already carries the new header
    (two of the four) changes the line alone. Said in the template's own header and in
    `README.md` → "Adopting cloud-setup.sh version 2".
12. **`template-versions.sh` takes an optional templates directory** so the new
    `template-version-bump.sh` can run the real check over edited copies — the check is
    seen to fail, not just to pass.

### Round 2 (review finding: a re-recorded hash at an unchanged version passed)

20. **The hash is tied to the version against the base branch** (option 1). Each template
    is compared with `git show <base>:templates/plans/<file>`; same version with different
    content fails, a lower version fails. Base = `origin/main` (`BASE_REF`), overridable
    through `TEMPLATE_BASE_REF` / `TEMPLATE_BASE_REPO` for the test fixture. Only the base
    tip is read, so a depth-1 fetch serves.
21. **The base's hash is recomputed from its file with the current rule**, not read from
    its table. Ruling 7 changed the rule, so main's stored hashes are of another
    definition; recomputing makes the five rows this feature re-recorded read as unchanged
    content at an unchanged version, and makes any later rule change immune. The base's
    `TEMPLATE_VERSIONS` is never consulted (the fixture omits it to prove it).
22. **Base unavailable:** precedent is `run-review.sh`'s `review_diff_base` (best-effort,
    fall back to local `main`). Followed for the lookup: `origin/main`, else local `main`.
    If neither resolves the check FAILs with a message naming `git fetch origin main`,
    because for this check "unchecked" would be the PR-85 silence again (the brief's
    preference). **New template** (no base file, or no version line there): pass.
    **Removed template:** nothing to check, since the checked set is the `TEMPLATES` list.
23. **A stale local `main` is acceptable only as a fallback**; with `origin/main` present it
    is never consulted.

### Round 3 (review escalation: tip comparison reddens branches that never touched a template)

24. **Templates are compared at the branch's fork point** (escalation option (a), decided by
    the coordinator): the base copy is `git show <merge-base of HEAD and the base>:…`. The
    check is about what THIS branch changed; a branch that never touched templates passes
    however far main has moved, and nobody is pushed to bump a stale copy, which would roll
    main's newer template back on merge. Base resolution and overrides from round 2 are
    kept; `TEMPLATE_BRANCH_REPO` names the checkout whose HEAD is the branch (default: this
    one) so the fixture can hold both.
25. **Fallback to the base tip** only when the merge base cannot be computed (a shallow
    clone without the shared history); neither resolving is still the "no base" failure.
    Residual case: a stale shallow branch can still trip on a newer main bump. The
    lower-version message says to merge the base in that path, and says instead that the
    branch lowered it in the fork-point path, so it is accurate for both. B15 (a–d) pins it.

## C. claimant names that differ by case

13. **Finding, against the brief's premise:** `capture_planning.repo_display_name` already
    derived the name from the `origin` URL, not the directory. In this container the
    ORIGIN itself is lowercase (`git -C /home/user/musicmap remote get-url origin` is
    `https://github.com/ssdesai/musicmap`) — the cloud clones from a case-folded URL — so
    no local rule can recover `musicMap` from it, and part (1) alone fixes nothing here.
    The fix that does is (2), the collapse. Part (1) still mattered in the shell:
    `feature-start.sh` (the brief-header line) and `feature-capture.sh` (`--for`) named the
    repo by `basename "$PRIMARY"`. Both now use `plan-runner-roots.sh` `feature_repo_name`,
    the same rule as `repo_display_name` — and `agentTooling` under `--self`, which they
    used to get wrong in a vendored copy (the consumer's directory name).
14. **Preferred spelling: any spelling not all lowercase beats an all-lowercase one; ties
    to the smallest string** (`roots.preferred_mention`). Case is only ever lost (a
    lowercase clone, a case-folding proxy), never invented, so the spelling with capitals
    is the one somebody typed. The brief said "prefer the remote-derived spelling"; here the
    remote-derived spelling IS the lowercase one, so that preference would keep the wrong
    spelling. Deterministic in the set, never the order, which is what keeps the refresh
    idempotent (claimant-case.sh C3).
15. **The collapse lives in `roots.py`** (`feature_mention_key`, `preferred_mention`,
    `collapse_feature_mentions`): the one module both `capture_planning.py` and
    `report.py` already import, and report.py must not import capture_planning.
16. **Applied at four points:** `other_session_claimants` (the ledger's own claims, which
    can hold one feature under two `repo_name`s), `annotate_frozen_record` (kept mentions
    compared by key, the spelling a record already holds competing with the ledger's, the
    union collapsed — so a record holding both comes out with one, once, and is then
    stable), `report.compute_shared_sessions` (renders one even from a record nobody has
    refreshed; its list is now sorted rather than insertion-ordered), and the drift check's
    `claimant_windows` lookup (a laptop `share_basis` finds a cloud-named claimant).
17. **Repo-name comparisons are case-insensitive** via `same_feature_ref`:
    `check_brief_headers` and `--list-subagents --for`. The slug half stays exact.
18. **The ledger's stored `repo_name`s are not rewritten.** They are read through the
    collapse wherever they become a mention; rewriting a ledger shared by every repo on the
    machine buys nothing the read side does not already give.
19. **Directory names left elsewhere** (`--list-subagents`' `cwd` column, `Path(cwd).name`)
    are display of where a transcript ran, not a feature's identity: left, recorded in
    BACKLOG.
