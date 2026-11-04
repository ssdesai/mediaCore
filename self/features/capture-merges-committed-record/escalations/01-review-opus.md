Verdict: escalated

# Review: capture-merges-committed-record

## What the batch was supposed to do

Make `analysis/capture_planning.py` merge into a committed `planning.json` by default
instead of refusing when a priced session or subagent's transcript can't be reached. In a
Claude Code cloud container that refusal fired at every multi-round close: each round runs
in a new container, so the previous round's transcripts are gone. Rows the scan can't
reach are kept, each stamped `carried_from` with the date it was first captured, and a
stamp that's already there is never replaced. A session dropped on purpose (a narrowed
window, corrected branches, or one a usage.json now claims) is still dropped. `--force`
rebuilds the record from scratch. `--carry-lost` still works but does nothing extra and is
marked deprecated. `report.py` adds one line when carried rows exist. Docs and tests were
updated to match.

## Does it do it

Yes. I checked each contract in the brief against the diff:

- **The merge keeps only what it can't see.** `check_frozen_cost` treats a prior row as
  lost only when the scan can't reach it and `excluded_ids` doesn't list it.
  `excluded_ids` covers both runner sidecars and the manifest's `exclude_sessions`
  (`capture_planning.py:3252`). A reachable session that has been deselected is not lost,
  so it is dropped. Lost rows are carried unless `--force` is passed. The refusal block is
  gone. The two refusals that remain (nothing matched, a delegate another feature already
  claims) are unchanged.
- **Provenance.** `carry_lost_entries` stamps a row only if it has no `carried_from` yet.
  The top-level `carried_from` is the earliest stamp across carried sessions and
  subagents, and it is written only when something is carried. `priced[]` rows are carried
  alongside their parent rows, so the totals include them (capture-merge A4/B7).
- **The ledger.** Carried subagents feed `agent_selected_by`, as they did before. Carried
  sessions now feed `session_selected_by` through `setdefault`, so `record_session_claims`
  records each one with its own `selected_by` (see the escalation below).
- **`--carry-lost`** is accepted, still implies `--recapture`, and its help text says it is
  deprecated. The hook's `CAPTURE_WRITING_FLAGS` still lists it, which is correct.
- **`report.py`.** `compute_carried` counts session and subagent entries, not `priced[]`
  rows. `carried` appears in `report.json` only when it is non-empty. The carried line
  prints once on stdout and once in `report.md`. Constants follow the naming convention
  (`CARRIED_KEY`, `CARRIED_LINE`).
- **`feature-capture.sh`.** The rollback still runs only when the capture exits non-zero,
  and the header now describes the merge. `feature-close.sh` needed no change, and I agree:
  it only passes the capture's exit code through.
- **Docs.** I checked the `analysis/README.md` field lists for both `planning.json`
  (`carried_from?` at the top level and on sessions and subagents) and `report.json`
  (`carried{rows,captured_at[]}?`). I also checked the repair-tools paragraph, the root
  README rows, LIFECYCLE, AGENT_PLANS, design doc §12 and the tests README. No live text
  still recommends `--carry-lost` as a step; the only mentions are historical, in dated
  DESIGN/TRIAGE docs. `NOTES.md` explains why refusal was right on a laptop, why it was
  wrong in the cloud, and why merging is safe in both.
- **Tests.** `self/tests/capture-merge.sh` covers cases (a) through (e) plus the alias. It is
  listed in `shell_scripts` and recorded in `self/gate.sh`. `capture-guard.sh` phases 3, 8
  and 13 and `subagent-capture.sh` phases 5 and 15 now check the merge. The gate report is
  green with nothing skipped.

## Fixed in this pass

- `analysis/README.md`, the capture entry's merge paragraph: it said the merge "can never
  lower the figure", which isn't true. A deliberate deselection of a reachable session
  lowers it, and capture-merge C1c tests exactly that. The sentence now says the merge
  never drops a row it can't see, and that a deliberate deselection may lower the figure.

## Escalated to the next round

1. **No test checks that carried rows reach the claims ledger.** The brief names this as a
   contract ("The carried rows reach the ledger"), and the batch added a line for it at
   `analysis/capture_planning.py:3883-3884`. That line passes each carried session's own
   `selected_by` into `session_selected_by`, so a carried *pinned* session is now
   ledgered as `pinned`; before, it fell back to `branch`. Nothing tests this:
   - `subagent-capture.sh` phase 5 (5–5c) checks that the delegate is carried and stamped,
     but not its entry in `~/.claude/subagent-claims.json`.
   - `capture-merge.sh` never reads the session-claims ledger, and `subagent-capture.sh`
     15d checks only the newly added pin, not the carried session.

   **Action:** add these assertions. After capture-merge phase A (or subagent-capture 15b),
   the session-claims ledger under the fake HOME should hold a claim for the carried session
   with this feature's slug and the `selected_by` from the carried row. Pin a session in
   the manifest, so the row says `pinned`; that tells the new `setdefault` apart from the
   old `branch` fallback. After subagent-capture 5, `claim $AGENT_1` should still name this
   feature. Only tests change, no code.
