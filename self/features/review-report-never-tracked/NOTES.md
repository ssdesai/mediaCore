# Notes: review-report-never-tracked

Rulings made during the hand build, each with its reason. The brief is the spec; these
are what it left open.

## The bug

1. **Legacy state, not a live defect in the ignore.** humanNetworkMap committed
   `plans/review-report.md` (2026-10-22, "import-edge-relationships: review stamps")
   before the generated `plans/.gitignore`'s anchored `/review-report.md` line reached it.
   A `.gitignore` never untracks a tracked file, and `run-review.sh`'s commit step is
   `git add -A`, so every round after re-committed it and two features reviewed
   concurrently conflicted on it (PR #253). mediaCore, whose history began after the line
   existed, never tracked it.
2. **The "archived copy" was documentation drift.** `templates/plans/.gitignore`,
   `templates/README.md` and `templates/plans/README.md` all promised a committed
   `features/<slug>/review-report.md`; no script wrote one.

## Decisions

3. **The repair lives in both places, whichever runs first.** `run-review.sh` untracks the
   live report inside its own round commit (so an affected repo is repaired on its very
   next review, even without a propagation pull), and `sync-plans.sh`'s write path
   untracks it (so a repo is repaired on the pull that brings this fix, before any
   review). Either is enough; both are idempotent and silent once untracked.
4. **`run-review.sh` untracks only when the ignore now covers the file.** An untrack the
   same commit's `git add -A` re-adds is no repair, so a repo whose `plans/.gitignore`
   predates the line is told to run `sync-plans.sh`, which writes the line and untracks.
   The untrack sits after `commit_pass_output`'s detached-HEAD and on-base guards, so it
   never stages a deletion that nothing commits.
5. **`sync-plans.sh` untracks every path its `.gitignore` ignores, not only the report,
   and only by that file's own patterns.** A tracked `gate-report.txt` is the same legacy
   bug with the same harm. Matches from the repo's root `.gitignore` (or anywhere else)
   are the repo's business and are left alone — told apart by `git check-ignore -v`'s
   source. The untrack is staged and not committed, like the routing moves: this script
   never commits. On the write path an `UNTRACKED` line is done work, not an item; under
   `--check` each is a `TRACKED` item.
6. **Implement the archived copy rather than delete the claim.** It is one `cp`, and it
   fixes the real gap that a clean verdict had no committed record outside the PR body.
   The path is the one the docs and the anchored ignore already describe —
   `features/<slug>/review-report.md`, one file per feature overwritten each round — so
   no doc or ignore pattern had to move, and git's history of the file holds every
   round's verdict. A per-round file under `review/<state>/` was rejected: a
   `<stem>.report.md` there matches `completed_review_count`'s and
   `latest_review_plan`'s `[0-9]*.md` glob and would miscount rounds.
7. **The `escalations/` copy stays.** It is named by review stem, is what the next round's
   instructions point at, and is what the tier ladder's directory holds; the archived copy
   is a record, not a brief. Redundant bytes on an escalated round, but two readers with
   two jobs.
8. **The transitional merge.** A feature cut before the fix that rewrote the tracked
   report, merged after one that untracked it, meets a modify/delete conflict once. That
   is the end of the legacy state, not a new one; resolve it by deleting.
