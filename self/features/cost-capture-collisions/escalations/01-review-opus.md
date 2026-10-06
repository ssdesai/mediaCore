Verdict: escalated

# Review: cost-capture-collisions

Base `3de1580` (cloud-close, #79) → `62d296b`. Commit order is right: `acceptance tests`
(`6b9afef`) comes before the implementation (`255880d`). Gate: `self/gate-report.txt`,
level `final`: **`all checks passed`**. Every touched test (`subagent-capture.sh`,
`claims-ledger.sh`, `session-share.sh`, `stream-capture.sh`) is recorded green there, and
no check is SKIPPED.

## What the batch was supposed to do

1. **§4:** stop runner children from inheriting the parent's session id, at the source.
   Also handle transcripts that were already written that way: a usage.json id whose
   transcript also holds interactive lines is a *collision*. In that case the capture
   prices the coordinator's lines, drops the runner tree's lines and warns. A pinned
   delegate the main walk did not reach is looked for everywhere, except under a genuine
   runner session.
2. **§6:** a ledger that has never seen a claimant must not delete that claimant's
   `also_claimed_by` mention. The ledger gains a `seen` provenance section,
   `--annotate-frozen` registers the corpus first, and repo identity is normalised for
   comparison only.
3. **The sole-claimant cut:** a pinned session is cut to its window even when it has only
   one claimant. A branch-selected sole claimant is still billed whole.

## Does it do it

For the main paths, yes. I read the code, not the notes.

- **Runner (`plan-runner-lib.sh:820-846`).** There is a single `claude -p` launch site,
  and every runner goes through it. It runs `env -u` for both names, built from the
  `EXECUTOR_SCRUBBED_ENV_NAMES` constant. `mint_session_id` tries `uuidgen`, then
  `/proc/sys/kernel/random/uuid`, then python3. Each result is lowercased and checked
  against the regex. If no uuid can be minted, the runner warns and leaves the flag off
  rather than passing an empty one. The code is bash-3.2-safe: the empty array is guarded
  with `${a[@]+…}`, and the regex is held in a variable. `stream-capture.sh` 11a–11h test
  the change through `run-review.sh`, using a stub that reports the inherited id the way
  the real CLI does. If the scrub were reverted, 11a, 11b, 11d and 11e would fail.
- **Collision (`tree_flags`, `runner_collision`, `capture_planning.py:3188-3232`).** A
  tree's kind is decided by the marker in its opening prompt. Unknown trees count as
  neither kind, so a transcript with no recognisable runner tree falls back to the old
  exclusion. That is the safe direction, and the ruling is recorded in `NOTES.md` 4–5.
  The marker is pinned in all four runner prompts by 11i–11m. Delegates spawned by the
  runner tree are added to `reachable_agent_ids` before the `continue`, so the fallback
  cannot pick them up again. If the `continue` for a usage.json id were restored, every
  check in `subagent-capture.sh` C would fail.
- **§6.** `claimant_seen` is checked per feature, not per repo. A legacy or flat ledger
  loads with `seen = {}`. `save_ledger` carries the `seen` section over when a caller
  passes none. Every `(repo, slug)` comparison goes through `claim_key`. Display names
  never pass through the normaliser, so `share_basis` and `also_claimed_by` strings cannot
  move. `NOTES.md` 16 records an empty-`HOME` annotate run over the real corpus: it changed
  no file. Letting annotate delete an unseen mention would turn `claims-ledger.sh` E1–E3
  red.
- **Cut (`select_parent:2903`).** The cut applies only to a pinned session whose first or
  last instant falls outside its own window plus the head bound. So sessions 6 and 11, and
  every frozen-record test, stay byte-identical. `session-share.sh` 21a–21o assert the
  split and that the sums are exact. Phases 12 and 14 were moved to branch selection, and
  their `check` lines are unchanged; `NOTES.md` 20 justifies this. No other assertion was
  weakened.
- **Scope.** The only feature directory under `self/features/` that changed is
  `cost-capture-collisions/`. No sibling's `planning.json`, `report.json` or `report.md`
  appears in the diff. `stream-capture.sh` was touched in place of `session-claims.sh`,
  which is within the brief's "at least".
- **Docs.** All of these match the code:
  - `analysis/README.md`: the collision rule, the full `seen` field list, and the
    replacement for "priced whole".
  - The new paragraph in `RUNNER.md`.
  - The rows in `self/tests/README.md` and `self/README.md`.
  - The design doc's §10.
  - The three `BACKLOG.md` entries.

## Fixed in this pass

Nothing. I found no local drift.

## Escalated to the next round

1. **A pinned coordinator found outside this repo's directories loses its pinned
   delegates. This is the §4 symptom again, in its cross-directory form.**
   - **Where:** `analysis/capture_planning.py:3339-3341` and `:3375-3384`.
   - **The bug:** `runner_only_ids = runner_excluded_ids - collided_ids` is computed, and
     `find_pinned_anywhere` is run, *before* the pinned-session fallback loop. That loop is
     the only place a session found via `find_session_elsewhere` can be marked collided.
     Its `collided_ids.add(session_id)` at `:3380` is therefore never read again.
   - **The failure case:** the coordinator is pinned, its transcript is under another
     project directory, a runner child collided with it, and the manifest pins its
     implementer. The coordinator's interactive lines are priced. But the implementer's
     transcript has a parent id that is still in `runner_only_ids`, so it is skipped and
     reported only as unmatched.
   - **A related gap:** when the fallback does reach a delegate of a collided parent (a
     collided session in this repo's directories that the walk skipped for an unclaimable
     `cwd`), it never calls `spawning_tree`. A pin on a delegate the runner tree spawned is
     then priced, and it is also in the usage.json: a double count with no warning.
   - **The fix is a design call, not a one-line move:** the fallback should judge a hit's
     parent from that parent's transcript (`runner_collision` plus `spawning_tree`)
     instead of from set membership. Alternatively, run the session fallback first and
     carry its flags forward.
   - **Assertion that would catch it** (in `subagent-capture.sh` C): a pinned coordinator
     whose collided transcript is filed under a second project directory, with a pinned
     implementer under it, prices the implementer. In the same fixture, a pinned delegate
     whose `meta.json` `toolUseId` points into the runner tree is not priced, and the
     capture warns that the pin is ignored.

## Not escalated, noted

- `branches_seen_anywhere` (`:3179`) also unions the dropped runner tree's branches. That
  is a true observation, since the branch was really seen, so I am not counting it as a
  defect.
- `report.py` does not render `unclaimed_usd` for any session. This predates the batch.
  The cut is disclosed in the capture's warnings, as shared sessions always were.

## Files touched by this pass

- `self/review-report.md` (this file).
