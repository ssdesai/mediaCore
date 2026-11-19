# 02 — review: harness-scorecard-time (round 2)

Round 1 judged this feature `clean` (`review-report.md`). One commit landed after it, and
no review has read it. "No findings" is a legitimate verdict; report only defects you can
demonstrate.

## What the feature was supposed to do

Unchanged from round 1: `harness/scorecard.py` shows time as plainly as cost — a Runs
table with "Wall to PR", "Wall to green" and "Total", a Per cell table with mean wall to PR
and mean total that leaves out `method_failed` rows (with a footnote), docs naming the
columns and the wall-clock caveat, and a registered offline test. No new row fields, no
`run.sh` change, no consumer repo.

The post-round-1 commit only fills `self/features/harness-scorecard-time/README.md`, which
`feature-close.sh` refused while it was still the template.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. Read the commit
`harness-scorecard-time: fill the feature README` in particular, and confirm the rest of
the diff is what round 1 read.

## Contracts to hold it to

- The README states the feature accurately: the columns added, the exclusions (no new
  fields, no `run.sh` change, no Programs section time, no consumer repo), and one plan row
  per plan in the manifest.
- Nothing outside `harness/`, its tests and docs, the `self/gate.sh` registration and
  `self/features/harness-scorecard-time/` changed.
- The round-1 contracts still hold on the final tree.

## Verdict
