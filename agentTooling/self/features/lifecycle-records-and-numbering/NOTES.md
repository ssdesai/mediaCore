# Notes — lifecycle-records-and-numbering (slice A)

Rulings, deviations and open questions from the records half of this feature (slices A,
A1–A4 of the manifest). Slice B (`feature-start.sh`, `self/tests/plan-numbering.sh`,
`self/PROJECT_FACTS.md`, `self/features/README.md`, `AGENT_PLANS.md`,
`analysis/report.py`, `analysis/README.md`) reports its own to the coordinator.

## Rulings

1. **The path labels are globals a shared `stray_labels` sets, not arguments.** The
   manifest left the choice open. `stray_paths` needs five facts beyond its input —
   `FEATURE_REL`, `FEATURES_REL`, `ROUTING_REL`, `ROUTING_RECORD_SUFFIX` and the slug — and
   a five-argument bash function whose arguments are positional strings is a call site
   nobody can read twice the same way. But "globals the caller sets" is the shape that
   drifted in the first place, so the callers do not set them: `stray_labels <slug>
   <checkout>` derives all four from the three facts both callers already have (this copy's
   `REPO_DIR`, the checkout it lives in, the slug) and sets them, and each caller calls it
   once. The names are the ones `feature-capture.sh` already used, plus `STRAY_SLUG` so the
   reader does not have to know whether its caller spells the slug `SLUG` or
   `FEATURE_SLUG`. Documented in the function's own comment, as the manifest asked.

2. **The admitted-siblings list is the second argument, and `NO_SIBLINGS` is a named
   constant for the empty one.** Three call sites pass it: the capture's pre-run check
   (none), the capture's pre-commit check (`${ANNOTATED[*]:-}`) and the close (none). A
   bare `""` at two of them would read as an oversight; `NO_SIBLINGS` says the two empty
   ones are the same decision — nothing has been annotated yet, or ever will be here.

3. **`ROUTING_DIR_NAME` and `ROUTING_RECORD_SUFFIX` moved with the reader**, though the
   manifest names only the latter. `stray_labels` builds `ROUTING_REL` from the directory
   name, so leaving it in `feature-capture.sh` would have put half of one path in each
   file. The capture now takes `ROUTING_REL` from `stray_labels` for its `git add` too, so
   the label the commit uses and the label the check uses cannot differ.

4. **`report_verdict` folds and trims the first line BEFORE matching the prefix.** It
   already folded the *value* after the match, so `Verdict: CLEAN` read clean while
   `  VERDICT: clean ` read `unreadable` — a distinction nothing wanted and no test saw.
   The manifest's A2 assertion (`  VERDICT:  CLEAN ` with a trailing `\r` reads clean)
   settles it in favour of folding both. This is a behaviour change, not only a test: a
   report that used to be treated as escalated (fail closed) can now close a round. The
   direction is safe — the label is the thing being matched, and a first line that says
   anything else is still unreadable — and it is the rule `RUNNER.md` and the root
   `README.md` now state.

5. **The close reads `round` off the stamp and validates it with a `case`, not `[[ =~ ]]`.**
   `(( ROUND < 1 ))` on a non-numeric string is a bash error, so an unreadable detail must
   not reach it. `case "$ROUND" in ''|*[!0-9]*)` falls back to `completed_review_count`,
   which is the same fallback a stamp with no `round` at all takes — one path for "the
   stamp does not answer this", whatever the shape of the non-answer.

6. **The close keeps the `ROUND < 1 → 1` floor**, as the manifest says. It is now reachable
   only from the fallback (a stamp's `round` is never below 1), and it is what makes a
   first close of a feature whose review predates rounds print `round 1` rather than
   `round 0`.

7. **`self/tests/verdict-readers.sh` sets `FEATURES_DIR` itself rather than staging a
   checkout for `resolve_roots`.** The manifest allowed either. The three readers under
   test use no other global, and a fake checkout complete enough for `resolve_roots` would
   be fixture nobody reads. The file says so where a reader will look for it — in its own
   header and in `self/tests/README.md`.

8. **The lifecycle test's capped-round fixture deletes the previous round's report.**
   `run-review.sh`'s capped-after-report branch compares the report's content with a
   fingerprint taken before the pass, and this file's stub `claude` writes the same bytes
   every round — so round 2's report read as "not written by this pass" and no verdict was
   stamped. A real round never rewrites its predecessor's report byte for byte; removing it
   is how the fixture says that, and it is a fixture fact rather than a contract change.

9. **The `08-review-opus` expectations in `self/tests/feature-lifecycle.sh` moved to
   `01`, and its `old` fixture feature kept its `07`.** Slice B owns the numbering rule;
   this file is slice A's, and the assertions are collateral. Keeping the other feature's
   `07` in the corpus turns S1f/S1i into the control the rule wants: another feature's
   plan numbers do not move this one's. S1n2 changed with it — the start's "Next" block now
   names `feature-close.sh` as what opens the PR, which the old assertion forbade.

10. **`NOTES.md.tmp` is the stray file X4 uses.** The backlog entry named it, and it is the
    honest case: an implementer's half-written note inside the feature directory, which is
    neither a cost record nor anything the capture would commit. The assertion checks the
    forge stub's log is *empty* rather than merely free of `pr create`, so a refusal that
    happened after some other forge call would still fail.

11. **The pre-4 `pr.sh` fixture is the real template with one line rewritten.** Anything
    hand-written would assert against a shape no consuming repo has. The close never calls
    `--merge-request` on it, so the body below the version line is never exercised — which
    is exactly the point of the version line being what the close reads.

## Deviations from the manifest

- **`RUNNER.md` was touched** (the manifest says "if needed"): its "It writes a verdict"
  bullet describes how the first line is read, and ruling 4 changed that.
- **Nothing else outside the slice's file list changed.** In particular `hooks/` is
  untouched, and the two backlog entries about its wording are left for the policy feature.

## Open questions

- **`stray_paths` still returns paths under a sibling's directory one at a time.** A
  capture refused by three of them prints three lines, which is right, but the refusal
  says "commit or discard them first" without distinguishing "this is another feature's
  record" from "this is your own half-written file". Not worth a second message shape
  today; if a capture ever refuses on a sibling's record in practice and the human is
  confused by it, the wording is the fix, not the reader.

## Slice B's rulings, reported to the coordinator

Slice B (`feature-start.sh`, `self/tests/plan-numbering.sh`, `self/PROJECT_FACTS.md`,
`self/features/README.md`, `analysis/report.py`, `analysis/README.md`,
`self/tests/report-rounds.sh`) ran on sonnet, its decisions all made in the manifest.

12. **The report's refusal test lives in `report-rounds.sh`, not `report-footnotes.sh`.**
    That file's phase 5 already stands up a feature with no `planning.json` for
    `--rounds-md`, which tolerates the absence; the new phase 7 is the same fixture in
    plain mode, where the absence is refused, so the two behaviours sit side by side.

13. **The `planning.json` check runs before `parse_manifest`.** The cheapest reading of
    "when the file does not exist": nothing else is opened first, and `--all`'s
    `fill_missing_reports` globs `*/planning.json` and never reaches the check, verified
    by a live run with one captured and one uncaptured feature.

14. **The message and the start's "Next" text say `[--self]` literally** rather than
    conditioning on the mode, matching how `LIFECYCLE.md`, `README.md` and the manifest
    write every two-mode command.

15. **Nothing keys a plan by bare stem across features** — the manifest asked for the
    check before the sequence was deleted. Grepped `analysis/*.py`, `check-plans.sh`,
    `plan-runner-lib.sh`, `plan-runner-roots.sh`, `run-*.sh`, `sync-plans.sh`: every
    stem-keyed structure in `report.py` (`build_usage_index`, `build_skipped_index`, the
    `compute_*` roll-ups) is built from one `feature_dir`; `capture_planning.py`'s
    `stem` hits are `Path.stem` on `agent-<id>.jsonl` and its ledger keys by session id;
    `check-plans.sh` takes one slug; the roots file's two readers glob one feature's
    `review/`; `report.py --all` keys by the feature directory's name. So two features
    sharing `01-review-opus` collide nowhere.

16. **Two commits for the slice, test and fix together in each**, after the red state
    was verified in the terminal: `AGENT_DIRECT.md`'s "commit the tests on their own" is
    the feature's first acceptance-tests commit, which slice A made for its scope.

17. **A `chmod +x` that leaked into the numbering commit was reverted in a follow-up
    commit**, never by amending.

## The coordinator's own

18. **Slice B ran on sonnet.** The design was decided in the manifest and every edit had
    an assertion written for it; the review pass is the check on the cheaper model's work.
    Slice A ran on opus because moving the reader changes what two scripts refuse.

19. **This feature's review stub was renamed `111` → `01` before the brief was written**,
    so the feature that deletes the exception is the first numbered under the rule.
    The fence's `plans` says `01-review-opus`; nothing else in the corpus is renumbered.

20. **Slice B's report commit carries slice A's `NOTES.md`** through a shared-index
    race between two `git add` calls in one worktree. The content is what slice A
    meant, byte for byte, and no history was rewritten to move it. Two implementers in
    one worktree is a coordination cost this shows; the fix, if it recurs, is a worktree
    per slice, not a rewrite.

## Round 2

21. **`stray_paths` now fails CLOSED on its own — a return code, not a stdout
    sentinel — when `stray_labels` has not derived its four globals.** Escalated from
    round 1 (`escalations/01-review-opus.md`): `stray_paths` read
    `FEATURE_REL`/`FEATURES_REL`/`ROUTING_REL`/`STRAY_SLUG` as plain globals with no
    guard, so a caller that ever skipped `stray_labels` — or called it and then lost the
    value some other way — hit `set -u` inside the command substitution wrapping the
    call. `set -u` kills only that subshell; the assignment's variable comes back empty,
    and both callers (`feature-capture.sh`'s pre-run and pre-commit checks,
    `feature-close.sh`'s pre-PR check) read empty as "nothing is stray." The close would
    open a PR over a dirty tree and the capture would push it — the exact failure the
    reader exists to prevent.

    The escalation offered two contracts: a sentinel line on stdout (so the callers'
    existing `-n "$STRAY"` branch would refuse it as if it were a stray path), or a new
    return-code convention. We chose the **return code**, `STRAY_UNJUDGED_RC=2`, because
    it also catches every OTHER way the subshell can die — not only the four named
    globals going missing, but any other unset variable, any other command inside
    `stray_paths` failing under `set -e`-like conditions the function might grow later,
    or a future edit to the function that adds a fifth precondition and forgets to teach
    the sentinel about it. A stdout sentinel only ever protects the cases someone
    remembered to emit it for; a return code protects the shape of the call itself —
    `STRAY="$(stray_paths …)"` failing is failing, whatever killed it. `stray_paths` now
    checks all four labels with `${X:-}` before its loop (never triggering `set -u`
    itself) and, if any is empty, names the missing one(s) and `stray_labels` on stderr
    and returns `STRAY_UNJUDGED_RC`; on success it still returns 0 with its findings on
    stdout exactly as before (empty = nothing stray). All three call sites are now
    `if ! STRAY="$(stray_paths …)"; then refuse …; fi` — `feature-capture.sh`'s pre-run
    check (refuses "the capture stopped before its commit"), its pre-commit check (same
    wording), and `feature-close.sh`'s pre-PR check (refuses "nothing was written and no
    PR was opened") — followed by the existing `-n "$STRAY"` branch, unchanged.

    Assertions: a new "stray reader" phase in `self/tests/verdict-readers.sh`, which
    already sources `plan-runner-roots.sh` with no runner. (a) `stray_paths` called with
    no `stray_labels` call anywhere above it in the script — so the four globals are
    genuinely unset, not merely empty — returns non-zero and names `stray_labels` on
    stderr; this is RED against the pre-round-2 reader, which instead let `set -u` kill
    the subshell with a bare "unbound variable" message naming no function at all. (b)
    after `stray_labels x "$TMP/checkout"`, with `REPO_DIR="$TMP/checkout"` and
    `FEATURES_LABEL="self/features"` set by hand first (this test never calls
    `resolve_roots`; the two are the minimal layout `stray_labels` needs to derive its
    labels for a `--self`-shaped checkout, read from `stray_labels` and `resolve_roots`
    rather than guessed), the identical status line returns 0 and reports the path as
    stray. (c) a `planning.json` path under the same feature directory returns 0 and
    reports nothing — the ordinary case, now backed by a return code a caller can trust.
