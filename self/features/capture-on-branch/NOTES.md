# Notes: capture-on-branch

Rulings made while building, each with its rationale, in the order they were made
(`AGENT_DIRECT.md` → "The procedure", step 4). Deliberate exclusions also carry a
`self/BACKLOG.md` entry.

## Rulings

1. **The "worktree guard" in `capture_planning.py` was a root, not a refusal, and is lifted
   in `roots.session_root`.** There is no git-dir ≠ common-dir test anywhere in the Python
   (triage fix 2a never landed as code there); what made the worktree's copy "the wrong
   copy" is that `session_root` stopped at the nearest `.git`, which in a worktree is its
   own `.git` file, so every claim root and the transcript-directory scan were derived from
   the worktree. `session_root` now follows a worktree's `.git` file to its common git dir
   (`gitdir:` → `commondir`, read from the files git writes, no subprocess) and returns the
   primary checkout — so a worktree's copy selects exactly what the primary's does. A
   submodule's `.git` file has no `commondir` and resolves as before. The artifact root is
   unchanged: the record is still written into the worktree's corpus, on the branch.

2. **The shim refuses; it does not forward.** `feature-close.sh` prints that close is
   retired, names `feature-capture.sh` with the two ways to run it, and exits 1. A forward
   would carry no logic either, but the words people type — the old command, from the
   primary, after the merge — now reach `feature-capture.sh`'s post-merge path, which writes
   locally and commits nothing, where the old close committed and pushed to `main`. A silent
   forward would look like the close had worked and leave the record uncommitted in the
   primary. Its one assertion is `feature-lifecycle.sh` X1.

3. **`pr.sh` keeps its commit: two commits, not one.** `pr.sh` commits the pass's work and
   opens the PR exactly as before; the capture then commits `S: cost records` on the same
   branch and pushes again. Deferring `pr.sh`'s commit to the capture would make the capture
   commit a stranger's work (the review pass's edits), breaking the "cost records and
   nothing else" rule it enforces, and would leave every consuming repo's already-seeded
   `plans/pr.sh` — which still commits — disagreeing with the harness. With two commits a
   consumer's un-merged v2 copy still works; the hand-merge is only for `PR_AUTO_MERGE`.

4. **Which run it is follows from where it runs, never from a flag.** The checkout this
   copy lives in has `<slug>` checked out → on the branch: stamp with
   `set-window-to --replace`, capture with `--recapture` once a record exists, commit the
   cost records on the branch, push the branch. Anywhere else → post-merge: refuse a branch
   that is not merged into what is checked out (naming the worktree copy to run instead),
   proceed on "manifest tracked here + `S: start` in history" when no branch is left, stamp
   a null `to` only (or `--tighten` under `--recapture`), write locally, commit nothing,
   push nothing. `--recapture` on the branch itself is refused: a plain run there already
   replaces the record.

5. **`manifest.py set-window-to --replace` is the pre-merge rule.** Replaces a set bound in
   either direction, printing `replaced: old -> new`; still refuses a bound at or before
   `from` (an empty window owns nothing whichever way it moved). `--tighten` and
   `--replace` together are refused. Chosen over a bare "stamp null or leave alone" because
   the design requires a re-run after more work to move `to` later.

6. **A plain post-merge capture with no branch left proceeds** (recover-at-close.sh C14,
   previously asserted as a refusal). Design §3.2 and the review brief require a feature
   merged under the old flow and never closed to stay capturable from the primary — and a
   forge with delete-on-merge takes its branch, which is exactly the "no branch left" shape.
   The manifest-plus-start-commit test that `--recapture` already used guards the plain run
   the same way; a never-started slug still refuses ("nothing to capture").

7. **Rollback is from a snapshot, not `git checkout`.** Before the stamp, the manifest and
   every `*.usage.json` under the feature directory are copied to a `mktemp -d`; a refusal
   restores the ones that differ. Exact whatever their git state (on the branch a sidecar
   may be committed, dirty or untracked), and no tree-touching git command is needed.

8. **The stray check runs first, on the branch only, with `--untracked-files=all`.**
   Nothing but cost records (COST_FILES, queue/state sidecars, routing records) may be dirty
   before the capture writes anything, so a refusal leaves the worktree untouched and the
   commit is provably this run's records. `--untracked-files=all` because porcelain
   otherwise collapses an untracked directory to `notes/`, which hides the file name the
   refusal must print. After the merge nothing is committed, so no check is needed.

9. **The unclaimed-delegate warning is asked after the capture.** Before it, the ledger does
   not yet hold this capture's claims, so a delegate claimed through its parent (a
   coordinator in the worktree) would be listed as unclaimed. After it, the list is exactly
   the delegates neither route claimed. The unclaimed-*sessions* listing the old close
   printed "for your eyes" is dropped: the corpus-wide residue belongs to
   `sweep-retirement-and-audit-fixes` (design §3.5).

10. **`routing.py --refresh-for <slug>` keeps the prior record's entries.** A start writes
    the slug it is starting with a null `at` because its own tool call has not flushed; a
    refresh that re-derived from the transcript alone could drop that slug. The prior
    entries the transcript does not carry are appended in their prior order, so the refresh
    is still deterministic (byte-identical on a second run). A record whose transcript is
    gone is left untouched with a warning. Printed as `router    refreshed <path>`.

11. **`pass_end` is written once per pass by `stamp_pass_end` in `plan-runner-lib.sh`.**
    `run-review.sh` calls it after `pr_opened` and before the capture; the EXIT trap's
    `print_status` calls the same function, which returns once the flag is set. Every other
    runner is unchanged — the trap is still the only writer there.

12. **The capture runs after a clean pass even when no PR hook exists.** The record is the
    feature's, not the PR's. Missing `feature-capture.sh` beside the runner (a test sandbox
    that copies only the runners) prints one line and carries on.

13. **`PR_AUTO_MERGE` reads the environment above the repo-specific section.** The template
    sets `AUTO_MERGE="${PR_AUTO_MERGE:-0}"` and `self/pr.sh` sets `AUTO_MERGE=0` with the
    reason, both above the marker, so the logic below it — `auto_merge`, called once the PR
    is created or found already open — stays byte-identical between the copies
    (`feature-lifecycle.sh` P1d). The call is `gh pr merge <branch> --auto --merge
    --delete-branch`; a refusal warns and exits 0, since the PR is then simply open.
    (`--merge`, not the `--squash` first built: the review pass changed it, because the
    prune and the post-merge capture both decide "merged" by ancestry, which a squash
    merge never gives.)
    **Known race, filed in BACKLOG:** with no required status check on the base, the forge
    may merge before `feature-capture.sh` pushes the cost commit. The template's comment says
    to enable it only where a check is required.

14. **The stale-reference exceptions.** `grep -rn feature-close` also finds `hooks/`
    (`allow-repo-commands.sh`'s git-shape reason text and its comment) and the hook's own
    test `self/tests/allow-repo-commands.sh`, which asserts that reason text. `hooks/` is
    out of scope and edit-denied, and the test pins the hook's current words, so both stay
    and are filed in BACKLOG. `self/TRIAGE-2026-09-03-feature-execution-procedure.md` is a
    dated record like the design file and is not rewritten.

## Deliberate exclusions

- `sweep.sh` retirement, the corpus-wide residue listing, `report.py --all` filling missing
  reports, the `check-plans.sh` window lints, `run-batch.sh`'s inferred-slug lint and
  `RUNNER.md`'s $5 → $7 review cap: design §3.5/§3.8, the next feature's. `LIFECYCLE.md`
  step 7 (sweep) stays.
- The open items (per-feature budget, `git stash list`) are not built.
- `hooks/allow-repo-commands.sh` still names `feature-close.sh` in its reason text (ruling 14).
