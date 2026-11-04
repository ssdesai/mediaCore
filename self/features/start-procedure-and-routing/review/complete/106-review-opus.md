# 106 — review: start-procedure-and-routing, rework

Second review pass, after a rework one-shot took the escalations from the first pass
(`105-review-opus.md`). Written from those escalations and the decisions taken on them,
never from the rework's report. "No findings" is a legitimate verdict (AGENT_PLANS.md →
"Review plans"). Fix local drift here; anything structural is an escalation in the verdict.
A finding under `hooks/` is always an escalation.

## What the rework was supposed to do

The six items the first review escalated, decided as follows:

1. **Prune deletes with `git branch -D`** once `git merge-base --is-ancestor <branch>
   origin/main` has held; the `-d` check was measured against local `main`, which lags
   `origin/main` whenever the PR merged on the forge and nobody pulled. A new case in
   `self/tests/feature-lifecycle.sh` merges through a second clone so the primary's `main`
   is behind, and asserts the worktree is removed, the branch is gone, and the printed line
   is truthful.
2. **A `--self` start from a vendored agentTooling** (the script one directory below the
   primary's root, `REL_REPO` non-empty) commits `agentTooling/self/routing/<id>.json` in
   `S: start`. Tested by a scaffold that nests the checkout, or, if the scaffold cannot be
   made to nest without rewriting it, a `self/BACKLOG.md` entry with the assertion.
3. **Conflict rule for the routing record:** when two features started by the same router
   merge in turn and conflict on its record, the side with the later `captured_at` wins.
   It is the superset. Said in `analysis/README.md`, `NOTES.md`, and the design record's
   §3.4 (replace "resolves by taking either side"). The one-file-per-session layout stays.
4. **Router detection matches `feature-start.sh` only at command position:** the first
   word of a simple command (start of line or after `&&`, `||`, `;`, `|`), optionally
   preceded by `bash`. `grep -n foo feature-start.sh hooks` on a `main` session leaves it in
   `--list-sessions --unclaimed`; asserted in `self/tests/routing-record.sh`.
5. **`open-session.sh`** quotes the worktree path in both copies, and `TEMPLATE_VERSIONS`
   carries the re-recorded hash so `self/tests/template-versions.sh` passes.
6. **`routing.routers_of`** is either called by `report.render_routed_by` or removed, and
   the `analysis/README.md` entry says which readers share which predicate.
7. **The feature README's prose** (`self/features/start-procedure-and-routing/README.md`)
   is written: title, the one-paragraph summary, a slices table in place of the template's
   plans/levels/contracts sections, and the deliberately-excluded list. The first build left
   the template text above the fence. The fence itself is not hand-edited beyond what
   `manifest.py` writes.

Nothing else changes. `feature-close.sh`, `run-review.sh`, `pr.sh`, `sweep.sh` and
`hooks/` carry no new diff from the rework.

## The diff

Base is the first review's commit: `git log --oneline main..HEAD` and diff from the
commit titled `start-procedure-and-routing: build, verify and review passes` to `HEAD`.
Expect `feature-start.sh`, `analysis/routing.py`, `analysis/report.py`,
`analysis/README.md`, `self/open-session.sh`, `templates/plans/open-session.sh`,
`templates/plans/TEMPLATE_VERSIONS`, `self/tests/feature-lifecycle.sh`,
`self/tests/routing-record.sh`, the feature's `NOTES.md` and `CHECKPOINT.md`,
`self/DESIGN-2026-09-16-lifecycle-restructure.md`, and `self/BACKLOG.md` if item 2 was
deferred.

## Contracts to hold it to

- Every one of the six items is present, or named in `NOTES.md` as deferred with a
  backlog entry. Item 4 is not deferrable.
- The gate is green: run `./self/gate.sh` from the worktree root and quote its verdict
  line. The first review only syntax-checked its own fixes; this pass runs the suite.
- Every test the first review's fixes touched still holds: the prune's truthful output,
  the vendored routing path, and every existing case in `feature-lifecycle.sh`,
  `routing-record.sh`, `allow-repo-commands.sh` and `template-versions.sh`.
- Named constants for the command-position regex and the conflict-rule wording; bash
  3.2; no `set -e`; no `cd` chained with another command anywhere in the diff except the
  `osascript` string in `open-session.sh`.

## Verdict

Write it as the PR body will read it: what the rework changed, each item above as
holds / fixed here / escalated, the gate's verdict line, and the files touched by this
pass.
