# Notes: capture-merges-committed-record

Rulings made during the hand build, each with its reason. The brief is the spec; these
are what it left open, plus the design reasoning the spec asked to have recorded here.

## Why refusal was right on a laptop, wrong in the cloud, and why merge is safe on both

1. **What the refusal protected.** `planning.json` is derived from session transcripts
   under `~/.claude/projects/`, which are on a retention clock. Once a transcript ages
   out, the committed record is the only account of that session's cost, and a capture
   that re-derives the file from what it can see writes `$0.00` over a real figure. That
   happened: one cadence run over humanNetworkMap zeroed eleven features, and two more
   were re-zeroed after the first guard let a worktree's transcript through on a
   filename glob. On a laptop every round of a feature runs on one machine, so a priced
   row whose transcript the scan cannot reach had exactly two explanations — it expired,
   or the capture is running from the wrong checkout — and both are reasons to stop and
   ask. Refusing, with `--carry-lost` as the explicit "I know, keep them" and `--force`
   as the explicit "discard them", was the right rule for that world.
2. **What changed in the cloud.** A Claude Code cloud feature's rounds run in separate
   containers, and `~/.claude` is new with each one (design 2026-10-05, §0). Round 2's
   close reaches only round 2's transcripts; round 1's exist nowhere but as the rows
   round 1's close committed to the branch. So from round 2 on, the "unreachable priced
   row" that was a laptop anomaly is the normal shape of every capture, and the refusal
   fired at every multi-round cloud close — `propagate-agenttooling-access` ruling 9, and
   PRs #92 and #94 — each time answered by a human running `capture_planning.py
   --carry-lost` by hand. A rule that fires on the normal case and is always answered
   the same way is not a guard; it is a step the script should take.
3. **Why merge is safe on both.** The merge re-prices every row the scan reaches and
   keeps every priced row it cannot, so nothing a scan *fails to see* can lower the
   figure, which is the whole of what the refusal protected (a deliberate deselection
   still can, as it should — below). The
   laptop accident is impossible under it — the expired rows are kept, not dropped. The
   two cases where dropping is *right* are both still dropped, because neither is in
   `lost`: a session deselected on purpose (a narrowed window, a corrected branch) is
   still reachable, and a session a usage.json has since claimed as runner cost is in
   `excluded_ids`. What is lost is only the ability to notice a wrong-checkout run by
   its refusal; that run now carries the rows it should have re-priced, and the WARN
   names them, which is a figure that is right and a warning to read rather than a
   figure that is gone. `--force` stays as the one way to discard.

## Rulings

4. **Provenance: a carried row keeps its first stamp.** The old `carry_lost_entries`
   stamped every carried row with the prior record's `captured_at`, so a row carried
   through two containers read as measured by the second. Now `mark` sets
   `carried_from` only when the row has none. A row lost for the first time is stamped
   with the prior record's `captured_at` — the last capture that priced it from its
   transcript, which may be later than the capture that first saw it (a row re-priced
   in round 2 and lost in round 3 says round 2). That is the right date: it is when the
   figure was last measured.
5. **The top-level `carried_from` is the earliest stamp.** It keeps the field's type
   (a string, as before), and the one question a reader asks of the file alone is "how
   far back does this figure's chain reach". The full set of dates is on the rows, and
   `report.py` lists them; a list at the top level would have changed the type for a
   reader `report.py` already serves.
6. **`report.py` counts entries, not priced rows.** One session holds several `priced[]`
   rows (per model, per sidechain); "2 planning rows carried" should mean two sessions
   or delegates, which is what a reader can match against `sessions[]`. The line shows
   dates (`YYYY-MM-DD`) rather than full stamps — which container's scan measured them
   is the point — and `report.json` keeps the full stamps.
7. **`check_frozen_cost` keeps its name.** It no longer refuses, but it is still the one
   reader of "which prior rows can this scan not reach", and every test and doc that
   names it stays valid. Its docstring says what it feeds now.
8. **`--carry-lost` still implies `--recapture`.** It always did, the hook's
   `CAPTURE_WRITING_FLAGS` treats it as a writing flag on that basis, and a deprecated
   alias that silently became a skip would be a worse surprise than one that still
   rebuilds.
9. **The carried session's `selected_by` reaches the ledger.** Under `--carry-lost` a
   carried session's claim was recorded with the default `"branch"`;
   `session_selected_by.setdefault` from the carried entry keeps a pinned session pinned.
10. **`feature-close.sh` needed no change.** Its capture step only reports the capture's
    exit code and skips the merge request on a non-zero one; with no refusal over lost
    rows there is nothing for it to say differently. `feature-capture.sh`'s rollback is
    likewise untouched: it still fires only on a non-zero exit, which the remaining
    refusals (nothing matched, a claimed delegate) still produce.
11. **Tests that asserted the refusal were rewritten, not deleted.** `capture-guard.sh`
    3, 8 and 13 and `subagent-capture.sh` 5 and 15 now assert the merge at the same
    points — the figure survives, the row is stamped, one WARN names it — so the
    scenarios the refusal was written for are still exercised. The new
    `capture-merge.sh` holds the provenance rules across three containers.
12. **Round 2 (the round-1 escalation): the ledger contract gets its assertions, tests
    only.** The review found ruling 9's line untested. `capture-merge.sh` A7 reads the
    session-claims ledger for the carried branch-selected row, and its new phase G pins
    a session in `sessions` (launched on `main`, so only the pin selects it), loses its
    transcript, and asserts the carried row and its ledger claim both still say
    `pinned` — the value the old `branch` fallback could not produce, which is what
    tells the fix apart. `subagent-capture.sh` 5c2 asserts the carried delegate's claim
    still names this feature as `parent`-selected, and 15f the carried session's as
    `branch`; the ledger readers moved up with the helpers so phase 5 can use them.
    The round-1 review also corrected one sentence in `analysis/README.md` itself: the
    merge never drops a row it cannot see, but a deliberate deselection may lower the
    figure (C1c tests exactly that) — ruling 3 above says the same in those terms.
