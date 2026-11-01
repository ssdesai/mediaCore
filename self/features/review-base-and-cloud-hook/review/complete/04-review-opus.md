# 04 — review: review-base-and-cloud-hook, round 4

Written before the rework, from the spec. Never from the implementer's report. "No
findings" is a legitimate verdict.

## What round 4 was supposed to do

`self/features/review-base-and-cloud-hook/SPEC.md` → "Round 4: a re-capture on the branch
can move `to` later". Read it first; it is this round's whole spec. In one line: the
on-branch capture's evidence for `session_window.to` must ignore the provisional `to` an
earlier capture stamped, so a re-run after more work moves the bound later, as the
doctrine already promises; every other caller of `last_branch_instant` is unchanged.

## The diff

`git fetch origin main`. Then the round's own diff: `git log --oneline` to find
`review-base-and-cloud-hook: review round 3`, and `git diff <that sha>..HEAD`. Expect
`analysis/capture_planning.py`, `feature-capture.sh`, tests, docs and this feature's
records — and nothing under `hooks/`.

## Contracts to hold it to

- **The defect is real and fixed at its cause.** Confirm for yourself that, before the
  change, `in_window(min(timestamps), normalize_window(manifest))` with a stamped `to`
  excluded every session beginning after it. After the change, the on-branch evidence has
  no upper bound; the lower bound, branch, cwd/claim-roots, `exclude_sessions` and
  subagent rules are untouched (diff them line by line).
- **Scope of the switch.** Only `feature-capture.sh`'s on-branch path (the one that runs
  `set-window-to --replace`) passes the new option. The post-merge path (`--recapture` /
  `--tighten`) does not; the claim index's `provisional_to` call does not (check it still
  only runs for an open window). Trace every caller of `last_branch_instant` and say what
  each passes.
- **No widening after a merge.** A post-merge `--recapture` still reads the window as
  written; `--tighten` still refuses a later bound. Probe it.
- **Interplay with chained windows.** A later feature on the same branch name whose
  window starts at this feature's `to` (`to` exclusive, `from` inclusive): could the
  open-ended evidence now pull this feature's `to` over the next feature's sessions? On
  the branch, before the merge, only this feature's sessions carry its `branches` — check
  whether the cloud case (one `claude/…` branch, possibly reused for a next feature after
  a squash merge; `self/BACKLOG.md`'s first new entry) makes that reachable, and whether
  the implementer recorded a ruling. Escalate only if it is reachable and unhandled.
- **Tests have teeth.** The new assertion fails on the pre-change code (read it, or
  revert the one call site in a scratch copy and run it). The post-merge non-widening case
  is asserted. The test is recorded by `self/gate.sh` and has its `self/tests/README.md`
  row; every profile-sensitive invocation pins `AGENTTOOLING_PROFILE` and clears
  `CLAUDE_CODE_REMOTE`.
- **Docs say how the promise is now true**: `feature-capture.sh`'s header step 2,
  `last_branch_instant`'s docstring, `LIFECYCLE.md` step 6, `analysis/README.md`, and the
  `--last-branch-instant` usage line. Named constants for any new literal; stdlib only;
  bash 3.2-compatible shell.
- **Rounds 1–3 untouched**: no change under `hooks/`, `run-review.sh`, `env-profile.sh`.
- `./self/gate.sh` green.

## Verdict

Write `self/review-report.md`. Its FIRST line is exactly `Verdict: clean` or
`Verdict: escalated`. Fix local findings in this pass and say what you fixed; escalate
only structural ones. Then the findings with file:line, then what you probed and found
sound.
