# 02 — review: rates-haiku-live-warning, round 2

feature: agentTooling/rates-haiku-live-warning

## What the feature was supposed to do

Round 1 (clean) added Haiku 5.5 to the rate history, added `refresh_rates.py --only`, and
split `--check`'s exit code so a new model is a `note` rather than a `WARN`. Its brief is
`self/features/rates-haiku-live-warning/review/complete/01-review-opus.md`. Do not
re-review it except where round 2 touches it.

Round 2 makes a review round end on a clean tree:

1. **`run-review.sh`**, after writing a recorded verdict's `plan_end` and `pass_end`
   stamps, commits the feature's `timing.jsonl` alone as `<slug>: review stamps`
   (`STAMPS_COMMIT_SUFFIX`). It uses the same guards as the pass commit (nothing on the
   base branch or a detached HEAD) and is advisory: a failed commit leaves the file, and
   the close's existing `S: PR` fallback commits it. The stamp's `head` is still the
   pass commit's sha, so the stamps commit sits one commit after the judged head.
2. **`feature-close.sh`** accepts `<slug>: review stamps` after the judged head **only**
   when that commit touches `$FEATURE_REL/timing.jsonl` and nothing else. Any other
   commit under that subject is refused like any unreviewed commit. `stray_labels` moved
   above the head check so `FEATURE_REL` is set there.
3. **A standing rule**: after a clean verdict, the coordinator runs the close without
   asking (`LIFECYCLE.md` step 5, `CONVENTIONS.md` → "Closing a feature").

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff. Round 2's own changes are the commits after
`rates-haiku-live-warning: review round 1`. Read the whole diff, but judge round 2's part
against this brief.

## Contracts to hold it to

- **The judged head is unchanged in meaning.** `plan_end`'s `head` is the pass commit,
  the tree the verdict judged. The stamps commit must not change it, and nothing that
  reads `head` should now expect `HEAD`. Grep for readers of the stamped `head`
  (`feature-close.sh`, `plan-runner-roots.sh`, `analysis/report.py`, the tests) and check
  each one.
- **Only `timing.jsonl` is staged.** `commit_stamps` must not sweep in anything else in
  the tree, even when other paths are dirty. Check the pathspec form of `git add` and
  `git commit`.
- **The close's check is exact.** It compares `git show --name-only` output to one path.
  Check that a commit touching timing.jsonl plus another file is refused, that the path
  is right in a vendored checkout (`agentTooling/self/features/...` or
  `agentTooling/plans/features/...` as a status prefix) as well as standalone, and that
  moving `stray_labels` earlier changes nothing for the stray check.
- **Every path that records a verdict ends clean**: clean, escalated, unreadable, and
  budget-capped-after-report. A pass that records no verdict commits nothing new.
- **No round-counting regression.** `next_round` and the Rounds table read
  `timing.jsonl`, and committing it must not change what they count. The test suite's
  RD and RC cases cover rounds 2 and capped; confirm they assert what they claim.
- **Tests and docs.** `feature-lifecycle.sh` V1c/V1d/V1f/V1h/V1i, T4b, V2d, RDd, RCc and
  the new X1f. The docs (`LIFECYCLE.md`, `RUNNER.md`, `AGENT_DIRECT.md`, `README.md`,
  `templates/plans/README.md`, `self/tests/README.md`, `CONVENTIONS.md`) must describe
  the same behavior the code has.
- **The CONVENTIONS rule ships to every consuming repo.** Check that it is worded so it
  only applies after a clean verdict, and names nothing self-specific beyond `--self`.

## Verdict

"No findings" is a legitimate verdict. Fix local issues in the pass. Escalate anything
structural, such as a change to what `head` means, or a way for an unreviewed change to
reach the close.
