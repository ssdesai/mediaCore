Verdict: escalated

# Review: one-feature-per-branch

## What the batch was supposed to do

1. Withdraw the merged-manifest exception: a cloud `feature-start.sh` refuses any branch a
   tracked manifest names, merged or not, and names that feature; `started_features_on`
   names it too; `STARTED_MERGED_REF` is gone; the docs describe one branch, one feature;
   `cloud-start.sh` S2 asserts the inverse of the old behaviour.
2. Document orchestrator and implementer sessions in `LIFECYCLE.md`, plus a pointer in
   `self/PROJECT_FACTS.md`.
3. Price a session once when its id has transcripts under several project directories,
   using the copy that ends latest, and warn about it (`capture-guard.sh` phase 19).

## Does it do it

**Items 1 and 2: yes.** `feature-start.sh` and `plan-runner-roots.sh` no longer skip a
manifest that is already on the base, and `STARTED_MERGED_REF` is gone. S2a–S2c assert the
refusal, the feature name, that nothing is written, and the `started_features_on` answer.
The root `README.md`, `self/tests/README.md` and the comments now describe the rule. A grep
outside `self/features/` turns up no remaining description of the exception. The two hits
it does find are unrelated: `feature-capture.sh:218` is about the post-merge capture, and
the S2a label tests the new rule. The `LIFECYCLE.md` section sits before "5. Review",
names `orchestration-records` without defining it, and is about the right length. Nothing
under `harness-cloud-pins/`, `claude-md-chain/` or `.claude/` was touched.

**Item 3: yes in `capture_feature`, with one reader left behind.** The walk visits each
session id once (`walked_session_ids`). It swaps in the copy that ends latest, looks for
subagents beside every copy and prices each agent id once (`agent_start`). It warns only
inside `if parent_selected`. The pinned-elsewhere loop uses the best copy outside the
walked directories. I found no path where both copies get priced, and none where the walk
prices the shorter copy. What is missing is the window evidence, below.

## Fixed in this pass

- `analysis/capture_planning.py` `best_session_copy`: a session with only one copy (nearly
  every session) is now returned without reading it again. Before this, `last_instant`
  parsed every transcript in the walk a second time just to take the max of a one-item
  list. The result is the same either way.
- `analysis/capture_planning.py`: removed `find_session_elsewhere`. It had become a one-line
  wrapper that nothing called, since its only caller now uses `best_session_copy`.
- I re-ran `self/tests/capture-guard.sh` after these edits. All checks pass, phase 19
  included.

## Escalated to the next round

1. **`last_branch_instant` still reads only the walked copy, so the window it stamps no
   longer matches what the capture prices.** `analysis/capture_planning.py`,
   `last_branch_instant`, which starts at the
   `for transcript_dir in find_transcript_dirs(sessions_dir)` loop:
   - It reads `jsonl_path` from the repo's own project directories only.
   - It never calls `best_session_copy`, and it looks for subagents only under
     `transcript_dir`.
   - Its docstring says the evidence "cannot drift from what `capture_feature` will count".
     This batch made them drift.

   **What goes wrong.** When the cwd moves and the longer copy lands in a directory the walk
   does not scan, `feature-capture.sh` stamps `session_window.to` one second past the end of
   the *short* copy (`--last-branch-instant --ignore-to`). `capture_feature` then prices the
   long copy against that `to`:
   - A branch-selected session that only this feature claims is priced whole, but draws a
     spurious "runs past `to`" boundary warning.
   - A **pinned** session that only this feature claims is cut to the window
     (`pin_is_cut`), so everything past the short copy's end is dropped. That is the
     under-pricing item 3 was meant to remove.
   - A shared session is split at the wrong bound.
   - The claim index's `provisional_to` for an open co-claimant has the same gap.

   **The fix.** Do the same per-id dedupe in `last_branch_instant`: a `seen` set, the lines
   of `best_session_copy(session_id)[0]`, and subagents from every copy's directory. Making
   the two readers share a helper may be cleaner.

   **The missing test.** `capture-guard.sh` phase 19 never runs `--last-branch-instant`. Add
   a case with the short copy in the walked directory and the long copy elsewhere, and
   assert that `--last-branch-instant --ignore-to <slug>` prints one second past
   `LATER_INSTANT`, not past `FIRST_INSTANT`. A second case should pin the session,
   stamp `to` from that evidence, and assert the total equals the long copy's total.

## Not verified

The gate report shows every check passing, and none is listed as SKIPPED. Apart from the
`capture-guard.sh` re-run after my own edit, I ran nothing.
