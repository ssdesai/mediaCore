Verdict: escalated

# Review — close-after-filing, round 3

## What the batch was supposed to do

Round 3 fixes round 2's escalation (audit B2): a gitlink next to the BACKLOG, hidden from a
porcelain `git diff` by an excluded worktree `.gitmodules` (`ignore = all`) or by
`diff.ignoreSubmodules=all`, passed `commit_changes_only`. Every name list the close judges a
commit by now reads `--ignore-submodules=none`: `commit_changes_only`, the cost/PR case's
`git show`, and `audit_paths_in_range`. Separately, the `100644` mode check moved into
`commit_changes_only`, so it now covers `: review stamps` as well as `: backlog` (C24). Tests
K13a/b/c and K14 were added, and NOTES.md and `self/tests/README.md` were updated.

## Does it do it

Yes, against every contract the brief lists:

- `commit_changes_only` (`feature-close.sh:151`) checks for one parent, compares the
  `--no-renames --ignore-submodules=none -z` name list against a sentinel, then checks for
  `REGULAR_FILE_MODE`. Both subjects call it, and the BACKLOG case no longer has a mode check
  of its own (`BACKLOG_FILE_MODE` is gone, and NOTES.md was renamed to match).
- `audit_paths_in_range` (`plan-runner-roots.sh:270`) reads `--ignore-submodules=none`. Its
  callers (`audit_paths_touched`, F1's `JUDGED_HEAD..HEAD`, run-review's queuing) still pass
  in the gate.
- The only name list still read without the flag is `AUDIT_ALL_FILES`
  (`feature-close.sh:320`). It is used only for the emptiness check. Ignoring submodules there
  can only make the list emptier, so that check still fails closed. This is not a hole.
- K13a/b/c and K14 are in the test and pass in the gate (`close-backlog: all checks passed`).
  K1/K2/K9 still pass. K13b correctly relies on the excluded `.gitmodules` from K13a
  surviving `reset --hard`.
- NOTES.md records the round 3 ruling, and `self/tests/README.md` lists K13 and K14.

But the round 3 security audit that ran with this pass (`audit-report.md`) came back
**`Verdict: escalated`** with a new blocking finding, B3. This feature changes audit paths, so
the close (F4) refuses anyway until a clean audit exists at a judged head. That alone makes
this a new round.

## Fixed in this pass

Nothing.

## Escalated to the next round

**E1 — audit B3: a replace ref makes an unreviewed commit look like a `<slug>: backlog`
commit** (`audit-report.md` → "Blocking findings"). Every `git` call in `feature-close.sh`
resolves objects through `refs/replace/`, but `git push` sends the real objects. Suppose a local
`git replace <real> <fake>` swaps in a fake commit that touches only the BACKLOG, on the same
parent. Then `commit_changes_only` accepts it, and the pushed branch carries the real
commit's unreviewed `hooks/policy.py` change. The base refused every `: backlog` commit,
so this diff introduced the regression for this input. The same attack under
`: review stamps` (audit A09) predates this feature and is also open in the base.

- **Fix:** in `feature-close.sh`, put `export GIT_NO_REPLACE_OBJECTS=1` before its first git
  call (`plan-runner-roots.sh` is sourced, so it is covered once the export comes before any
  of its functions run). The audit verified that this refuses both A08 and A09. The next round
  should also decide whether `run-review.sh`, which stamps the judged head and queues the
  audit, needs the same export. That changes a script-wide invariant ("history is read with
  replace refs off"), so record it in NOTES.md as a ruling.
- **Tests:** add two cases next to K13 in `self/tests/close-backlog.sh`. Each is an
  unreviewed commit (for example one touching `hooks/policy.py`) shadowed with
  `git replace` by a fake on the same parent, then `git read-tree -u --reset HEAD`. One fake
  touches only the BACKLOG under `feat: backlog`. The other touches only timing.jsonl under
  `feat: review stamps`. Both must be `refused_unreviewed`. List them in
  `self/tests/README.md`.

## Non-blocking notes

- **K13c does not test the `audit_paths_in_range` change.** The head-check loop runs
  before F1 (`feature-close.sh:305`). So in K13c, `commit_changes_only` refuses the
  `hooks/sub` gitlink first, and the assertion (`rc == 1`, no stray words) passes whether or
  not `audit_paths_in_range` reads `--ignore-submodules=none`. Reverting the flag in
  `plan-runner-roots.sh:270` leaves the gate green. The missing assertion is a direct one: in
  a fixture with `diff.ignoreSubmodules=all`, `audit_paths_in_range <checkout> <range>` over a
  commit adding a gitlink at `hooks/sub` must print `hooks/sub`. Run it against the sourced
  `plan-runner-roots.sh`, for example next to the existing `audit_paths_in_range` unit cases.
  Cheap enough to add in the next round with E1.
