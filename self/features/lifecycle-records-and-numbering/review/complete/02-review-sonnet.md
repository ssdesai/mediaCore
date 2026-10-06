# 02 — review: lifecycle-records-and-numbering, round 2

Round 1 (`review/complete/01-review-opus.md`, report at
`escalations/01-review-opus.md`) judged every manifest item done and escalated one
finding. This round judges the rework of that finding and confirms round 1's own fixes
still hold. Begin your report with the `Verdict:` line the prompt asks for. "No findings"
is a legitimate verdict; fix local drift here; anything structural is round 3's brief.
`hooks/` is out of scope.

## What the rework was supposed to do

`stray_paths` (`plan-runner-roots.sh`) reads four globals that `stray_labels` sets. A
caller that skips `stray_labels` used to get an empty result from a subshell `set -u`
killed, and both callers read empty as "nothing is stray" — fail open. The contract
chosen: **a return code.** `stray_paths` returns `STRAY_UNJUDGED_RC` (non-zero) with one
stderr line naming the missing label and `stray_labels` when it cannot judge, and 0 with
its findings on stdout when it can. Every caller — `feature-capture.sh` twice,
`feature-close.sh` once — checks the status with `if ! STRAY="$(stray_paths …)"` and
refuses on non-zero, which also refuses on any other death of the substitution's subshell,
the reason a return code beat the sentinel line round 1 offered. Asserted directly in
`self/tests/verdict-readers.sh`: without `stray_labels` the call returns non-zero and
names `stray_labels`; with labels set, a stray path is printed with status 0 and a cost
record is not. `NOTES.md` carries the ruling under "Round 2".

## The diff

Two diffs. The rework: `git diff <round-1 head>..HEAD` where the round-1 head is the
`head` on the `plan_end` stamp for `01-review-opus` in
`self/features/lifecycle-records-and-numbering/timing.jsonl` (or the commit
`lifecycle-records-and-numbering: review round 1`). Expect `plan-runner-roots.sh`,
`feature-capture.sh`, `feature-close.sh`, `self/tests/verdict-readers.sh`,
`self/tests/README.md`, root `README.md`, `NOTES.md`, `timing.jsonl`, and this brief plus
the manifest's `plans`. Then the whole feature, `git diff main...HEAD --stat`, to confirm
nothing outside those files moved since round 1.

## Contracts to hold it to

- **Every call site checks the code.** `grep -n 'stray_paths' feature-capture.sh
  feature-close.sh` shows each call inside an `if ! STRAY=$(…)` (or equivalent that
  tests the substitution's status), and the refusal that follows names the check that
  could not run. A call whose status is discarded is the fail-open bug back.
- **The guard is explicit and named.** `STRAY_UNJUDGED_RC` is a named constant; the
  function tests all four labels (`FEATURE_REL`, `FEATURES_REL`, `ROUTING_REL`,
  `STRAY_SLUG`) with `${x:-}` so the guard itself cannot trip `set -u`.
- **The unit test is red without the fix.** Read the three new assertions and confirm
  that reverting the guard alone would fail (a); reverting the callers' status check is
  invisible to the unit test — say so in the report as the known limit, unless the
  rework added a caller-level assertion.
- **Round 1's fixes hold.** `self/tests/verdict-readers.sh` still sources the roots file
  before setting `FEATURES_DIR`; the two rewrapped lines are still wrapped.
- **Style and docs.** Bash 3.2, no `set -e`, no chained `cd`; the `plan-runner-roots.sh`
  row in root `README.md` states the return-code contract (Rule 2); `self/tests/README.md`
  describes the fourth reader under test; the ruling is in `NOTES.md`.
- **Nothing else moved.** The whole-feature stat matches round 1's plus the files above.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the rework was supposed to do, whether it does it, what you fixed, what you
escalated with the assertion that would catch it, and the files this pass touched.
