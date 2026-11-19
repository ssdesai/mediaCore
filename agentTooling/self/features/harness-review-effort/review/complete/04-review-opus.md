# 04 — review: harness-review-effort, round 4

Rounds 1–3 judged the feature as built. Since then `origin/main` moved (PR 128,
`harness-scorecard-time`, merge `cbd140c4`) and was merged into this branch (`c4ac39b`).
The merge conflicted in one place, `harness/tests/README.md`, and was resolved by hand.
"No findings" is a legitimate verdict.

## What the feature was supposed to do

`HARNESS_REVIEW_EFFORT` is the `--effort` of the harness review stage and its usage-limit
retry; unset = `HARNESS_EFFORT`; rows gain `review_effort`; the dry run prints every
stage's effort; rework stays on `HARNESS_EFFORT`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. The merge commit is `c4ac39b`;
`git show --cc c4ac39b` shows the resolution.

## Contracts to hold it to

- The resolved `harness/tests/README.md` keeps both sides: main's
  `harness scorecard time self-test` step and this feature's `harness review effort
  self-test` step both appear in the list of gate steps, and the stated count matches the
  steps `self/gate.sh` registers for the harness.
- `harness/README.md`, `harness/SPEC.md` and `self/gate.sh` merged without losing either
  side's content: main's scorecard-time entries and this feature's review-effort entries
  are all present, and `review_effort` still sits beside `effort` in the row field lists.
- Nothing in the feature's code changed since round 3; the diff against `origin/main`
  stays under `harness/`, its tests and docs, `self/gate.sh` and the feature folder.

## Verdict
