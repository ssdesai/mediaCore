# 02 — review: harness-review-effort, round 2

Re-review after round 1 (`escalations/01-review-opus.md`, `review-report.md`). Round 1
found the code correct and escalated one gap: nothing tested that no call carries two
`--effort` flags. "No findings" is a legitimate verdict.

## What the feature was supposed to do

`HARNESS_REVIEW_EFFORT` is the `--effort` of the harness review stage and its usage-limit
retry (the calls `HARNESS_REVIEW_MODEL` covers); unset or empty = `HARNESS_EFFORT`; both
unset = no flag. Same validation as `HARNESS_EFFORT`. Rework, methods and the program
orchestrator stay on `HARNESS_EFFORT`. Rows gain `review_effort`; `--dry-run` prints each
stage's effort; `harness/README.md`, `harness/SPEC.md` document it.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`.

## Contracts to hold it to

- The round-1 escalation is closed: `harness/tests/review-effort.sh` has a case that calls
  `harness_claude` with a stub `claude` and asserts exactly one `--effort` reaches it when
  the caller names one under `HARNESS_EFFORT`, that the fallback adds `HARNESS_EFFORT`
  once, and that neither set adds none. Check it would fail if the guard loop in
  `harness_claude` (`harness/lib.sh`) were deleted.
- Everything round 1 held the diff to still holds; nothing else changed except
  `harness/tests/README.md`'s entry for that test.

## Verdict
