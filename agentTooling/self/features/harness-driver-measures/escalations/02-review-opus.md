Verdict: escalated

# Review: harness-driver-measures, round 2

## What the batch was supposed to do

Round 1 found the feature sound and escalated one gap: nothing tested that a `no-pr` resume
(`run.sh <exp> --from review`) re-captures the method's cost with `--recapture` at the
driver's rates. Round 2 was meant to close that gap. It added one log line to
`capture_one`'s `RECAPTURE_METHOD` branch (`harness/run.sh:607`) and two assertions to
`harness/tests/smoke.sh` section 9c2c (lines 1575–1578): the resume output names the
method's slug as re-captured, and names no other slug.

## Does it do it

Partly. The contract the brief set is met: if `RECAPTURE_METHOD=true` is removed from
`do_pr_resume`, or the `if` branch in `capture_one` is removed, the log line disappears and
the first assertion fails. The second assertion correctly catches the branch firing for the
review or rework slug.

The brief also asked whether the log text could appear without `--recapture` actually being
passed. **It can.** The log line and `recapture=(--recapture)` are separate statements, and
the test watches only the log line. Two mutants get through with the suite still green:

- delete `recapture=(--recapture)` at `harness/run.sh:608`, keeping the log line; or
- drop `${recapture[@]+"${recapture[@]}"}` from the `capture_planning.py` call at
  `harness/run.sh:620`.

The scenario can't catch either one. The fake sessions price nothing, so the method's
feature directory has no `planning.json` freeze (smoke.sh 3b says so), and
`capture_planning.py` produces exactly the same result with or without `--recapture`. The
test checks that the harness meant to re-capture, not that the re-capture happened.

Everything round 1 checked is outside this round's diff and still holds: `forge.sh` stays
backward compatible, `--arm-root` with `--self` gives a usage error, the bash 3.2 rules are
kept, the method templates are untouched and the READMEs are current (one line fixed below).
I didn't re-run the gate; the verify pass has already run it.

## Fixed in this pass

- `harness/tests/README.md` (smoke section on the third cell): the description of the
  no-pr resume test didn't mention the new assertions. It now says the resume logs that it
  re-captures the method's slug, and only that slug, at the driver's rates.

## Escalated to the next round

1. **`harness/tests/smoke.sh` §9c2c (before the resume at line 1563): make the resume
   test depend on the flag reaching `capture_planning.py`.** Before the resume:
   - Commit a freeze dated in the future onto the cell's **local** branch
     `$RESUME_PR_BRANCH` in `$REPO`. `ensure_resume_trees` re-adds the worktree from
     `refs/heads` first. Use a scratch `git worktree add`, commit, then `worktree remove`.
   - The file is `plans/features/$RESUME_PR_SLUG/planning.json` with
     `{"captured_at": "2099-01-01T00:00:00+00:00", "cost": {"total": 5.0}, "sessions": [], "subagents": []}`.
   - A 2099 stamp is later than any manifest window, so the stale-freeze `elif` in
     `capture_one` never fires. Only the `RECAPTURE_METHOD` path can rebuild the freeze,
     the same idea as the `FRESH` seed in smoke §2b.

   Then assert both:
   - `$RESUME_PR_DIR/logs/$RESUME_PR_BRANCH-capture.log` has no
     `$RESUME_PR_SLUG: already captured` line. That line is what `capture_planning.py`
     prints (`analysis/capture_planning.py:3378`) when it honours a freeze because no
     `--recapture` was passed.
   - The resume row's `cost_method_usd` is not `5.0`. The rebuilt figure from fake sessions
     is `0`.

   Both mutants above then fail: without the flag, the freeze is honoured, the log says
   "already captured" and the row carries `$5`. Keep the existing log-line assertions. They
   still pin "only the method's slug".
