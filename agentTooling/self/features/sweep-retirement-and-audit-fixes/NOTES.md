# Notes: sweep-retirement-and-audit-fixes

Rulings made while building, each with its rationale (`AGENT_DIRECT.md` → "The
procedure", step 4). Deliberate exclusions also carry a `self/BACKLOG.md` entry.

This build was **resumed**: the first implementer was killed at the gate, having written
the acceptance tests (commit `49c2e7b`) and the whole of slices 1–8 uncommitted, and
having left its rulings in the code's own comments rather than here. Rulings 1–10 are
those, written down from the tree they are implemented in; 11–14 are the resume's own.

## Rulings

1. **The annotation gets its own entry point rather than a corpus-wide capture.**
   `capture_planning.py --annotate-frozen [--except SLUG]` (`annotate_corpus`) is
   `--all`'s already-captured branch on its own: it loads the claims ledger, walks this
   corpus's frozen `planning.json`s, and prints the slug of each record whose
   `sessions[].also_claimed_by` changed. No transcript is opened and no dollar, duration,
   `captured_at` or `share_basis` moves. Reusing `--all` would have made every capture
   walk every feature's transcripts — the thing whose cost and expiry the restructure is
   removing — to reach one key on one record.

2. **`--except <slug>` is the feature whose capture is running.** Its record was written
   by that capture moments earlier, from the same ledger, with the same annotation; a
   second pass over it would report a record as "changed" that this run itself had just
   written. It is a hard error to pass `--except` without `--annotate-frozen`, so the
   flag cannot silently do nothing.

3. **The annotation is never fatal to the capture.** A failed `--annotate-frozen` warns
   ("every other record is as it was") and the capture carries on; a failed `report.py`
   on an annotated sibling warns that its record is annotated and its report is not. This
   feature's own capture has already succeeded by then, and losing it over another
   feature's bookkeeping would cost transcripts that expire.

4. **`stray_paths` accepts exactly three file names under another feature's directory.**
   `ANNOTATION_FILES="planning.json report.md report.json"`, and only under
   `$FEATURES_REL/<other-slug>/`. The capture refuses a dirty tree holding anything that
   is not a cost record, and the annotation by construction dirties a sibling's record —
   so refusing it would refuse every capture that found a shared session. Widening the
   exemption to "anything under the features root" instead would let the cost commit
   carry a plan, a brief or a note somebody was still writing. The commit's `git add`
   names each annotated slug's directory one by one for the same reason.

5. **The residue is printed, never enforced.** `feature-capture.sh` step 8 prints the rate
   table's verified date (with a WARN when stale) and the corpus-wide unclaimed sessions
   and delegates over `RESIDUE_LOOKBACK_DAYS=7`. It reports on the *corpus*, not on this
   feature, and nothing in it can refuse a capture that has already done its job: an
   unclaimed session is a question for a human and a stale rate table is a reason to
   re-check it, not a reason to leave a feature uncaptured while its transcripts exist.
   Seven days is the cadence the retired sweep ran at. Routers are excluded for free —
   `--list-sessions --unclaimed` already drops them (`is_router_lines`), because a
   router's spend is routing overhead, a category of its own rather than a remainder.

6. **`run-review.sh` commits the pass; `pr.sh` keeps its identical commit as the
   fallback.** This reverses `capture-on-branch`'s ruling 3 for the runner side only, on
   that review's own escalation: `pr.sh` returns 0 without committing on four ordinary
   paths (no forge CLI, not authenticated, detached HEAD, not seeded), and each left the
   pass's files dirty for the capture, which refuses them as stray — so every clean review
   in such a repo ended "capture exited 1". The subject is byte-identical
   (`<slug>: build, verify and review passes`) so a consumer's un-updated `pr.sh` finds a
   clean tree and commits nothing rather than adding a second, differently-named commit.
   Both copies' contract comments and both READMEs say which is which.

7. **The runner's commit is advisory and refuses on the base branch.**
   `commit_pass_output` returns 0 on every failure path (detached HEAD, on the base, add
   failed, commit failed), each with a line saying the output was left uncommitted — a
   review that succeeded is never unwound by a git failure after it, exactly like `pr.sh`
   and the gate. On the base branch it commits nothing: committing the primary's work in
   progress is what `LIFECYCLE.md` rule 2 exists to prevent, and `pr.sh`'s own base-branch
   refusal still prints below it.

8. **`report.py --all` fills gaps before it ranks, and says so on every run.** The trend
   table reads `*/report.json` alone, so a feature captured but never reported is absent
   from it — not partial, not warned about, absent (three of this corpus were). Filling
   them carries none of the capture's risk: `report.py` reads what is on disk and
   re-prices nothing (its no-recompute contract). `GAP_FILL_LINE` prints even at zero, so
   "nothing was missing" is a statement rather than a silence, and one feature's failure
   is named and skipped rather than taken as the run's.

9. **Check 7 stays one check over the whole `session_window`.** Zone and ordering print
   one line with a joined detail, rather than two lines about one fence. Bounds are
   compared as **instants**, not as text (`2026-09-04T14:00:00-04:00` sorts before
   `2026-09-04T17:00:00Z` and is an hour after it), a null `to` is "in flight" and never
   out of order, and `to` at exactly `from` fails — an empty window owns nothing and the
   feature reports `$0.00` with no refusal anywhere downstream.

10. **`run-batch.sh` lints once per batch, at the first moment there is a slug.**
    `run_corpus_lint` is idempotent through `LINTED`: it runs before the build pass when
    the slug was an argument, and otherwise right after the build pass resolves it —
    which is the earliest it can, since resolving the slug is what the build pass does —
    stopping the batch before the gate and the verify and review passes.

11. **The tombstones keep the name `sweep.sh`.** `analysis/README.md`, `self/PROJECT_FACTS.md`
    and `self/README.md` say in so many words that `sweep.sh` is retired and where each of
    its steps went. The review contract asks that `grep -rn "sweep.sh"` find only the
    historical corpora and records, and these three are a deliberate exception: naming the
    script is the whole point of a tombstone, since the name is what a reader greps for
    when the command they remember is gone.

12. **`hooks/` was left alone although it still names `sweep.sh`.** Out of scope for this
    feature (`hook-opaque-commands-and-audit` owns it in parallel), so
    `hooks/allow-repo-commands.sh` and `self/tests/allow-repo-commands.sh` still approve
    `agentTooling/sweep.sh` as an entry point. Harmless — the command now fails at exec —
    and filed with the sibling `feature-close.sh` drift in `self/BACKLOG.md`.

13. **`RUNNER.md` states the derivation without repeating the superseded number.** The
    review cap reads `$7.00` in both places, and the sentence that read "`$5.00` was the
    starting estimate" now says the figure supersedes an estimate no measured run fitted
    inside. The contract is that `RUNNER.md` carries no `$5.00` for the review cap, and a
    reader greps rather than parses; the full derivation, the old number included, stays
    in `run-review.sh`'s comment beside the constant it explains.

14. **`templates/plans/pr.sh` needed no `template-version` bump.**
    `self/tests/template-versions.sh` hashes a template with its comment lines stripped,
    and the change to that file is entirely its contract comment — so no consuming repo's
    seeded copy is reported as drifted, which is right: nothing a seeded copy *does*
    changed. `templates/plans/README.md`'s `pr.sh` row carries the same correction in
    prose, since that is what a consumer reads.

## Deliberately excluded

Each has a `self/BACKLOG.md` entry (see the three raised by this feature):

- **`hooks/`** and its test's `sweep.sh` approvals — ruling 12.
- **`feature-start.sh`'s plan numbering across branches** — two features started from one
  base get the same stub number, found while starting this one (107 and 108 were each
  issued twice on 2026-09-17 and renumbered by hand).
- **The audit's two open design points** — a per-feature budget in the fence and relaxing
  the `git stash list` deny. Undecided, not defects.
- **The shared-session machinery** (ledger, split, `--recapture`, `--carry-lost`) is
  **kept**, not retired with the sweep: the existing corpus needs it, and the annotation
  built here is a read of the same ledger.
