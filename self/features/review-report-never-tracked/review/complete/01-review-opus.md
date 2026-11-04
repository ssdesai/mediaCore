# 01 — review: review-report-never-tracked

feature: agentTooling/review-report-never-tracked

## What the feature was supposed to do

A consuming repo (humanNetworkMap) TRACKS `plans/review-report.md`: it was committed before
the generated `plans/.gitignore`'s `/review-report.md` line reached it. A `.gitignore` never
untracks a tracked file, and `run-review.sh`'s commit step is `git add -A`, so every review
round re-commits it, and two features reviewed concurrently conflict on exactly that file at
merge (their PR #253). Separately, the docs promised "a feature's own archived copy
(`features/<slug>/review-report.md`) is the committed record" — and nothing wrote one, so a
clean verdict survived only as the PR body.

The fix, as specified:

1. `run-review.sh`, before its round commit: if the live report (`REVIEW_REPORT`, normal and
   `--self` roots) is tracked AND now ignored, `git rm --cached` it so the round commit
   untracks it, printing one line. The file stays on disk (`feature-close.sh` reads it for
   the PR body). If it is tracked but NOT ignored, leave it and say to run `sync-plans.sh`.
   Keep using `git -C "$REPO_DIR"` (the reads-fence).
2. `sync-plans.sh`: after writing the stubs, untrack every tracked file under `plans/` that
   `plans/.gitignore`'s OWN patterns ignore (`UNTRACKED <path>`); under `--check` report
   each as a `TRACKED` item and write nothing. Never touch matches from the root
   `.gitignore`. The one-time repair thus happens at the next review or the next
   propagation pull, whichever comes first.
3. Make the docs true by implementing the archived copy: every round `run-review.sh`
   copies the report to `<features>/<slug>/review-report.md`, carried by the round commit.
   The `escalations/` copy stays (it is the per-stem rework brief).
4. Self-test `self/tests/review-report-untrack.sh`, registered in `self/gate.sh` and
   `self/tests/README.md`; README.md rows, LIFECYCLE.md step 5, RUNNER.md, templates docs,
   `self/PROJECT_FACTS.md` updated; rulings in the feature's `NOTES.md`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- The untrack never removes the file from disk, and never runs on detached HEAD or the
  base branch (it must sit after `commit_pass_output`'s guards, so it never stages a change
  nobody commits).
- An untrack the next `git add -A` would undo is not done (the `check-ignore --no-index`
  guard).
- `sync-plans.sh` runs under `set -euo pipefail`: no new path may abort it — a repo with no
  git, a `plans/` outside a work tree, nothing tracked-and-ignored.
- `sync-plans.sh --check` writes nothing (index included).
- The archived copy's path is not matched by any ignore (the anchored `/review-report.md`
  in `plans/.gitignore`; `self/review-report.md` in the root `.gitignore` under `--self`),
  and nothing that enumerates a feature directory — `completed_review_count`,
  `latest_review_plan`, `stray_paths`/`COST_FILES`, `check-plans.sh`, `analysis/` — is
  confused by a new top-level `review-report.md` in it. In particular: is it committed by
  the round commit in every path where the round commit runs, so the close never sees it
  dirty?
- Ordering: the budget-cap banner is appended to the live report BEFORE the archived copy
  is taken.
- Docs: every place that described the archived copy, the live report's tracking, or
  `sync-plans.sh`'s outputs agrees with the code (including the `TRACKED`/`UNTRACKED`
  words and the test's assertion list in `self/tests/README.md`).
- Named constants for new literals (CONVENTIONS.md → "Named constants").

## Verdict

"No findings" is a legitimate verdict — say it outright rather than manufacturing concerns.
