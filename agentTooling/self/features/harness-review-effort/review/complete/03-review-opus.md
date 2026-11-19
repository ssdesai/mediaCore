# 03 — review: harness-review-effort, round 3

Round 2 was clean. One commit landed after it: `harness-review-effort: fill the feature
README`, which replaced the feature README's template text (title, plans table, excluded
list) and nothing else. "No findings" is a legitimate verdict.

## What the feature was supposed to do

`HARNESS_REVIEW_EFFORT` is the `--effort` of the harness review stage and its usage-limit
retry; unset = `HARNESS_EFFORT`; rows gain `review_effort`; the dry run prints every
stage's effort; rework stays on `HARNESS_EFFORT`. Rounds 1 and 2 reviewed that code.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`. The commit to read is the last one before this
round's stamps: `git log -3 --stat`.

## Contracts to hold it to

- The README commit touches only `self/features/harness-review-effort/README.md`, and what
  it says is true of the diff (the variable, its fallback, rows, dry run, the exclusions).
- Its plans table names the two review briefs that exist; the machine-readable fence is
  untouched.
- Nothing else changed since round 2's verdict.

## Verdict
