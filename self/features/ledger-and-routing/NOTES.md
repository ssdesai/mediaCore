# Notes — ledger-and-routing

Rulings, deviations and open questions from the direct build of `ledger-and-routing`
(`AGENT_DIRECT.md`), against `self/DESIGN-2026-09-18-ledger-and-routing.md` §1–§6 and the
manifest's slices A1–A2. Everything the design decided is built as written; below is what
it left open, plus the places the build had to choose between two readings of it.

Rulings 1–11 are **A1**'s (§1, the routing record per feature); A2's follow, appended by
the coordinator.

## Rulings

1. **A legacy record naming a slug this corpus has no directory for is skipped, and no
   directory is created for it.** The design's one open question. A directory under the
   features root *is* a feature to everything that walks that tree —
   `capture_planning.feature_slugs`, `report.py --all`, `check-plans.sh` — so a directory
   holding a routing record and no manifest would be a feature with no manifest, which is
   a louder wrong answer than a missing record. `--migrate` prints the skip and its
   reason, and moves on. This is not hypothetical: `self/routing/`'s own
   `654e3f53…` record names `tooling-backlog-2026-09-17`, a slug that never became a
   feature in this corpus, and the migration commit skipped exactly that one. Nothing is
   lost — the copies its other four slugs received carry the whole record,
   `features_started` and all, so what that router started is still readable wherever
   anything about that router is readable at all.

2. **A legacy record NONE of whose slugs has a directory is kept, not deleted.** The
   corollary, and the one place the migration is deliberately not idempotent-to-silence: a
   record with nowhere to go is the only copy of itself, and a migration that destroys
   data to reach a tidy end state is worse than one that leaves a file behind with a line
   saying why. Its line prints on every run, which is the standing notice; a human decides.
   A target *skipped as already later* counts as linked for this purpose (nothing is lost
   by deleting the older side), so the ordinary corpus still empties in one pass.

3. **`record_rank` is `(captured_at, len(features_started))`, and latest wins strictly.**
   The design fixes the first term. The second breaks the tie the first leaves: two copies
   written from one transcript in the same second, where the start that had already flushed
   is in both and the one still running is only in the copy written for it. A router only
   grows, so more features is the later read of that instant — and a tie broken the other
   way would drop a feature out of the Routing table until that router happened to start
   another. On a full tie the first copy in sorted-path order is kept, which is
   deterministic and, the records being equal by both terms, arbitrary only in name.

4. **`write_record` creates the feature directory; `--migrate` never does.** They are
   different questions. The start writes the record moments after `manifest.py init` made
   the directory, and a start that failed on the order of two writes would be a refusal
   about nothing; the migration's missing directory is ruling 1's evidence that the feature
   is not in this corpus. Said in both docstrings, because the asymmetry reads as an
   oversight otherwise.

5. **`routers_of` keeps returning a list, of at most one.** It reads one file now, so it
   could return a record or None. It stays a list because both callers
   (`report.render_routed_by`, `refresh_for`) loop over it and the empty case — a feature
   nobody started through the script — is the one that carries meaning; a `None` at those
   two call sites is two `if`s where there is now none.

6. **`analysis/report.py` needed no edit at all.** The brief scoped me to "the two routing
   renderers and the import line". Both take `features_dir` and ask `routing.py` for the
   paths, and the names they import (`load_records`, `routers_of`, `started_slugs`) are
   unchanged, so the move is invisible to them: `render_routing_table` gets one record per
   router because `load_records` collapses the copies, and `render_routed_by` gets this
   feature's own copy. A diff there would have been a diff for its own sake. Asserted in
   `routing-record.sh` R5 (one row for a router three features hold a copy of) rather than
   assumed.

7. **`self/tests/sync-check.sh` never listed `routing/`**, so it is untouched — the
   brief's "if it lists `routing/`" condition is false. `verdict-readers.sh` did name it,
   through `stray_labels`' fourth label, and follows.

8. **`sync-plans.sh` runs `--migrate` on the write path only, and it can never fail a
   sync.** `--check` reports drift and writes nothing, and a migration is not drift. The
   migration is advisory in both directions: idempotent and silent once the directory is
   gone, so every later sync costs one exit-0 process, and a non-zero exit prints a WARN
   rather than joining the "needs attention" count — a record left in the old place is a
   record nobody reads, not a broken repo. It commits nothing, because this script commits
   nothing; the moves are printed and handed to whoever ran the pull.

9. **The acceptance-tests commit is red, deliberately** (`AGENT_DIRECT.md` step 2): 36
   assertions in `routing-record.sh`, 14 in `feature-lifecycle.sh` — the second merge of
   two features one router started exiting 1 on an add/add conflict, which is the defect
   itself reproduced — and 1 in `verdict-readers.sh`. So the gate was not green at that
   one commit, and was run green before every commit after it.

10. **Two files outside A1's listed ownership were touched, both for the same reason.**
    `templates/plans/features/README.md` gains `routing.json` in its per-feature file list:
    it is the consuming-repo counterpart of `self/features/README.md`, which the brief does
    name, and removing `routing/` from `templates/plans/README.md` without it would leave a
    consuming repo's docs with the record in no file list at all. And this feature's own
    manifest (`self/features/ledger-and-routing/README.md`) had its trailer's
    `plans/routing/<session-id>.json` corrected, as the brief asks — it is template text
    copied by `feature-start.sh`, and `templates/plans/features/TEMPLATE.md`, which it was
    copied from, is corrected with it. That file carried an uncommitted fence edit of
    A2's (the two `subagents` pins) when it was staged; per the brief it was left exactly
    as found, and it rides A1's docs commit.

11. **No `stamp-timing.sh` milestones were stamped.** `AGENT_DIRECT.md` asks a direct
    implementer to stamp `planned` → `tests-written` → `gating` → `committed` into
    `timing.jsonl`. This feature has two implementers building at once in one worktree and
    `timing.jsonl` is in neither one's file list; two of them stamping one file would
    produce one interleaved sequence that `report.py` would read as one build's phases.
    The spans are left to the coordinator, which is the only party that can bound them.

## Rulings — A2 (§2–§4, the three ledger rules)

12. **`manifest.py` imports `routing`, and the direction was checked rather than
    assumed.** The design's parenthetical says `capture_planning` "imports `manifest`'s
    reader"; it does not — nothing in `analysis/` imports `manifest` at all
    (`grep -n "import manifest" analysis/*.py` is empty), and `manifest` imported only
    `roots`. The real constraint is the other way round: `capture_planning` is the module
    that READS this fence on every capture (`parse_manifest`), so a `manifest` →
    `capture_planning` import would make the writer import its reader, and
    `capture_planning` already imports `routing`. `routing` imports `pricing`, `roots` and
    `transcript` and nothing else, so `manifest` → `routing` cannot close a cycle. What
    `set-window-from` needed was the transcript lookup, and `routing.find_transcript` +
    `load_lines` are the copy of it that is not behind a capture. The already-captured
    note reads `planning.json`'s `captured_at` directly (`captured_at_of`) rather than
    calling `capture_planning.prior_capture`, for the same reason.

13. **A transcript with no `assistant` line was already captured into `subagents[]` when
    pinned; §3's "verify" needed no code.** Selection reads timestamps
    (`agent_start_of`), never usage, so the delegate reached `subagents[]` and only the
    LEDGER missed it — it was written from `priced[]`, which such a transcript never
    produces. The fix is therefore one line of scope in `record_claims` (walk the
    record's own `subagents[]`, `cost_usd` defaulting to 0), not a change to selection.
    `subagent-capture.sh` 19a asserts the half that needed no change, so a future
    "optimisation" that skips an unbillable transcript fails there rather than silently
    reopening the defect.

14. **`open_claimants` is always written, `[]` included.** A key present only sometimes
    cannot be read as "no open claimants" versus "a record too old to know", and the
    corpus is re-captured often enough that the stable shape is worth the one-line diff
    on every record. Its members are exactly the claims that reached a `share_basis` with
    `open: true` — an open feature that shares no session with this one is not a claimant
    and is not listed.

15. **An open co-claimant with no evidence is dropped by writing its window EMPTY, not by
    a second drop path.** `session_claim_intervals` already drops another feature's empty
    claim, and `select_parent` branches on `len(intervals) <= 1`, so a second path would
    be a second place for the two to disagree. What the open case adds is its own warning
    text ("still open … no branch session of its own to bound it by"), because the
    existing one advises fixing `session_window` and that manifest is exactly what
    `feature-start.sh` wrote. A claimant whose manifest has no `from` either is given
    `NO_EVIDENCE_INSTANT` (`datetime.min`, UTC) on both bounds, since `is_empty_window`
    needs both present.

16. **The capturing feature is exempt from provisional bounding, and that is what keeps
    the in-flight head rule alive.** Its own `to` was stamped from this same evidence by
    `feature-capture.sh` moments earlier, and its claim is `intervals[0]` by contract —
    so bounding it here would derive the same bound twice and would overrule a `to` an
    author had stamped by hand. It also preserves `head_bound`'s exemption for an
    earliest claimant still in flight (`session-share.sh` 15f), which is a rule about the
    feature being captured.

17. **The drift WARN goes to stderr.** `feature-capture.sh` reads
    `--annotate-frozen`'s **stdout** as a list of slugs, one per line
    (`ANNOTATED_OUT="$(… --annotate-frozen …)"`), and would read a `WARN:` line among
    them as a feature to re-report and `git add`. Nothing else in that pass prints to
    stderr, so the human still sees it.

18. **Drift is only announced against a bound that has actually been stamped.** A
    claimant still carrying `to: null` has nothing to disagree with (it has not closed),
    and one whose manifest neither corpus holds cannot be read at all; both are passed
    over silently. Only a stamped `to` that differs from the frozen `provisional_to`
    warns, once per (record, claimant), compared as instants rather than as strings.

19. **`set-window-from`'s refusals are all plain exit 1.** `set-window-to --tighten`
    reserves 3 because `feature-capture.sh --recapture` continues past that one refusal
    and no other; nothing reads this command's codes, so reserving another would be a
    contract with no second party. The same instant is a no-op at exit 0, mirroring
    `set-window-to`.

20. **A session whose transcript is gone is refused, not waived.** The first-instant
    guard is the whole safety of a command that widens a claim backwards, so when it
    cannot be evaluated the command refuses rather than applying unguarded — fail closed,
    the rule `run-review.sh`'s unreadable verdict already follows.

21. **`set-window-from` refuses a null `from` rather than filling it in.** An unbounded
    `from` already claims everything before `to`; there is no head in front of it to move
    over, and writing a bound where the author wrote none would narrow the claim, which is
    the one thing this command must never do.

22. **`self/tests/manifest-window.sh` is a new file, and `self/gate.sh` was edited to
    register it.** The design says the `from` cases go beside `set-window-to`'s, and
    `self/tests/README.md` puts those in `feature-lifecycle.sh` — A1's file under §6's
    table. The ownership boundary is hard, so the cases went into a file of their own; an
    unregistered test is run by nothing, hence the two additive lines in `self/gate.sh`
    (its `shell_scripts` list and one `record` line).

23. **`session-share.sh` phase 15f changed by design, and the change is now an
    assertion.** `15f-duration-b` read 1800 — head-b's half of an overlap with head-a,
    whose `to` was null and was therefore read as running to the end of the transcript.
    That reading IS the defect §2 removes: head-a's `branches` match no transcript, so it
    is an open co-claimant with no evidence, it is dropped, and head-b owns the session
    whole (18000s). The line now asserts that, and `15f-open-no-evidence` beside it
    asserts the drop is announced. head-a's own record (15f, 15f-duration) is unchanged —
    the in-flight exemption is the capturing feature's.

24. **No `stamp-timing.sh` milestones were stamped**, for the same reason A1 records in
    ruling 11: two implementers sharing one worktree would interleave `checkpoint` events
    in one `timing.jsonl`, and `compute_checkpoint_spans` reads the first instant of each
    status. The coordinator's own stamps bound this build.

## Coordinator's note on the shared-file rule

A1's docs commit (`c9f56c4`) staged `analysis/README.md`, `self/tests/README.md`,
`self/BACKLOG.md` and this feature's manifest while they carried A2's finished entries
and the coordinator's pin edit, so those rode A1's commit rather than their authors'.
Nothing was lost or reverted (A2 verified its content at HEAD); the §6 rule "each slice
`git add`s only its own paths" held for every code file and broke only on the four
shared files, which the design already accepted as a race. The warning text
`set-window-from` is asserted in `session-share.sh` (15e-remedy-from, 16e) rather than
in `manifest-window.sh`, because a capture produces it and the manifest test runs none.
