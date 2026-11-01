Verdict: escalated

# Review: one-feature-per-branch, round 2

## What this round was supposed to do

Round 1 escalated one defect. `last_branch_instant` in `analysis/capture_planning.py` read
only the copy of a session id that the walk reached first. When a session had transcripts
under two project directories, the `session_window.to` stamped from that evidence could end
with the shorter copy while the capture priced the longer one, so a pinned session was cut
short. The fix was to give `last_branch_instant` the same per-id dedupe that
`capture_feature` uses: each session id read once, from the copy that ends latest, with
subagents looked for beside every copy.

## Does it do it

Yes. The code changes are correct as far as I can tell from reading them.

- `last_branch_instant` (`analysis/capture_planning.py:2585-2628`) now uses the same steps
  as `capture_feature`'s walk (`:3420-3434`, `:3518-3521`): a `walked_session_ids` skip,
  `best_session_copy(session_id)`, the lines swapped for the best copy, `branches_seen`
  computed from those lines, and `copy_dirs = {every copy's parent} | {transcript_dir}`
  walked in sorted order for subagents. The two functions agree on which copy is read and
  which directories are searched for subagents. The only difference is in ordering, and it
  does not matter: `last_branch_instant` checks `exclude_sessions` before the dedupe, and
  an excluded id is dropped either way.
- Nothing calls a removed name. `find_session_elsewhere` appears only in old reports and
  briefs. Its one former caller, the pinned-elsewhere loop, now calls
  `best_session_copy(…, skip_dirs=this_repo_dirs)`.
- The test checks results, not just that the code runs. 19h checks the exact stamped
  bound (`10:30:01Z`). The short copy alone would give `10:00:01Z`, so the assertion tells
  the fixed code from the broken code. 19i writes that bound as `to`, pins the session, and
  checks that the priced total equals the long copy's total. Under the old bound the
  10:30 message would fall outside the window and the total would be lower.
- The gate (`self/gate-report.txt`, level `final`) is green with nothing skipped, and
  `capture-guard.sh` passed all its checks.

## Fixed in this pass

- `analysis/capture_planning.py` `best_session_copy`: fixed spacing (`dated =[` →
  `dated = [`). This is cosmetic only.
- `analysis/README.md`: the capture_planning entry now states the rule that subagents are
  looked for beside every copy of a session. The code and both comments already described
  that rule, but the README did not.

## Escalated to the next round

1. **No test covers looking for subagents beside every copy of a session.**
   `capture_feature` (`:3518`) and `last_branch_instant` (`:2625`) both look for a
   session's subagents under every copy's project directory (`copy_dirs`). Phase 19's
   fixtures have no subagents at all, so the test suite would still pass if either
   function went back to `subagent_transcript_paths(transcript_dir, session_id)`. The two
   functions keep this logic separately, each in its own copy, and nothing checks that they
   still match. That is the same kind of one-sided drift that caused round 1's finding.
   This needs a test only, with no change to production code. Add to
   `self/tests/capture-guard.sh` phase 19 a case where the short copy of `SESSION_C` is in
   `$PROJECTS` (the walked directory). The long copy goes in `$OTHER_PROJECT`, and a
   subagent transcript for that session goes under
   `$OTHER_PROJECT/$SESSION_C/subagents/` (the layout `subagent_transcript_paths`
   expects). The subagent's last instant must be later than the long copy's. Assert:
   - (a) the priced total includes the subagent's tokens;
   - (b) `--last-branch-instant --ignore-to` prints one second past the subagent's last
     instant, not the parent's.

   Update the phase-19 entry in `self/tests/README.md` to match.
