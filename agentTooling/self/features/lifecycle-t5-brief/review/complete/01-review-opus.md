# 01 — review: lifecycle-t5-brief

Review the diff against the spec below, never against a builder's report. "No findings"
is a legitimate verdict.

## What the feature was supposed to do

`self/tests/feature-lifecycle.sh` phase T5 ("a review run from the primary on main commits
nothing") wrote its review brief to
`$AT/self/features/$SLUG/review/incomplete/99-review-opus.md`, a directory the primary's
`main` does not carry at that point. The write failed with `No such file or directory`
and the review ran with no brief, while the run still reported every assertion passed:
T5 may have been passing without exercising the case it describes.

The feature makes T5 run with its brief: the brief exists where the review on `main`
reads it before the review runs (the directory is created, or the brief is placed where
the runner reads it in that setup — whichever matches what T5 means to test), with an
assertion that the brief exists before the review runs and that T5 prints nothing on
stderr. T5a–T5d are then checked to pass for the right reason. If the runner turns out to
commit something from the primary on main, that is a runner bug, to be reported and not
fixed in this feature. The BACKLOG entry "`feature-lifecycle.sh` T5 writes its brief into
a directory that does not exist." is removed, touching no other entry, and
`self/tests/README.md`'s `feature-lifecycle.sh` entry is updated if what T5 asserts changed.

Excluded: any change to runner code (`run-review.sh` and the libraries), any other phase,
any other BACKLOG entry.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- T5's brief is created before `review "$AT" "$SLUG"` runs, in the place the runner reads
  it in that setup, and an assertion fails if it is missing.
- An assertion fails if T5's run printed anything on stderr from the test's own commands
  (the brief write in particular).
- T5a–T5d keep their names and meaning and still pass; none was loosened to pass.
- The test's header description of T5 (near line 107) still says what T5 does.
- The only BACKLOG change is the removal of that one entry; no other entry is touched.
- `self/tests/README.md`'s entry matches what T5 asserts.
- No runner code, no `.claude/`, no other feature's folder is changed.

## Verdict
