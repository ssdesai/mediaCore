Verdict: clean

# Review: review-report-never-tracked

## What the batch was supposed to do

A consuming repo that committed `plans/review-report.md` before the generated
`plans/.gitignore` line `/review-report.md` reached it kept tracking the file. Every review
round's `git add -A` then re-committed it, and two features reviewed at once conflicted on it
at merge. The docs also promised an archived per-feature copy of the verdict that nothing
wrote. The batch had four parts:

1. `run-review.sh` untracks a tracked, now-ignored live report before the round commit, and
   tells the user to run `sync-plans.sh` when the file is tracked but not ignored.
2. `sync-plans.sh` untracks any tracked file that `plans/.gitignore`'s own patterns ignore.
   Each one prints as `UNTRACKED`, or as a `TRACKED` item under `--check`.
3. Every round copies the report to `<features>/<slug>/review-report.md`, and the round
   commit carries it.
4. A self-test and the matching docs.

## Does it do it

Yes. I checked the diff against each contract in the brief:

- **The untrack is safe.** `untrack_review_report` is called inside `commit_pass_output`,
  after the detached-HEAD and base-branch guards, so it never stages a change that nobody
  commits. It uses `git rm --cached`, so the file stays on disk for the close's PR body.
  It is guarded by `check-ignore --no-index`, so it never does an untrack that the next
  `git add -A` would undo. Every git call uses `git -C "$REPO_DIR"`.
- **`sync-plans.sh` is safe under `set -euo pipefail`.** If `plans/` is not in a work tree,
  the function returns 0. A failed `rev-parse` also returns 0. When nothing is ignored, the
  pipeline ends in `|| true`. Only matches whose `check-ignore -v` source is
  `<prefix>.gitignore` count, so root `.gitignore` matches are left alone. Under `--check`
  the function only reads (`ls-files`, `check-ignore`) and never writes the index.
- **The archived copy's path is not ignored.** In `plans/.gitignore` the pattern is
  anchored as `/review-report.md`. In the root `.gitignore`, `self/review-report.md` is
  anchored by its inner slash.
- **Nothing that enumerates a feature directory is confused by the new file.**
  `completed_review_count` and `latest_review_plan` only look under `review/`. The round
  commit carries the copy in every path where that commit runs, so the close never sees it
  dirty, and `stray_paths` never has to judge it.
- **Ordering is right.** The budget-cap banner (`run-review.sh:219`) is appended before
  the archived copy is taken (`:347`).
- **Named constants.** The new literal is `ARCHIVED_REPORT_NAME`.
- **Docs.** README.md, LIFECYCLE.md step 5, RUNNER.md, `templates/README.md`,
  `templates/plans/.gitignore`, `self/PROJECT_FACTS.md` and the test's entry in
  `self/tests/README.md` all agree with the code, including the `TRACKED`/`UNTRACKED` words.

The gate is green, and `review-report-untrack.sh` passes U0, R1–R5, S1 and S2.

## Fixed in this pass

- **Feature-directory layouts were missing the new file.** Neither
  `self/features/README.md` nor `templates/plans/features/README.md` listed the
  `review-report.md` the runner now writes into every feature directory. I added a line to
  each. The second is the template itself, not a generated copy, and the stubs carry no
  template version.
- **`self/README.md` did not mention the archived copy.** Its `review-report.md` row now
  says each round is copied to `features/<slug>/review-report.md` and committed.
- **The banner-before-copy ordering had no test.** Nothing checked that the archived copy
  carries the cap banner, so reordering the two steps would have stayed green. I added one
  assertion beside the existing banner check in `self/tests/tiered-gates.sh`: "capped
  review: the archived copy carries the cap banner too". I also updated that test's entry
  in `self/tests/README.md`. I have not run this assertion; the next gate run will.

## Escalated to the next round

None.
