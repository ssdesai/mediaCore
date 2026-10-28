# 97 — review: claim-window-precision

## What the feature was supposed to do

Close the four `self/BACKLOG.md` entries `shared-session-share` raised — read that
feature's manifest and `self/features/claim-window-precision/brief.md` for the rulings,
which are settled and not reopened here:

1. **`session_window.to` is stamped from evidence, not the wall clock.**
   `feature-close.sh` stamps `to` one second after the last instant of the feature's own
   branch-selected sessions and their subagents (`capture_planning.py
   --last-branch-instant <slug>`), *before* the capture, so the share split runs against
   the real bound; rolled back if the capture refuses; falls back to now with a warning
   when the feature has no branch session. `--recapture` may only tighten a bound
   (`manifest.py set-window-to --tighten`), never widen one.
2. **A single-claimant session that outruns its window says how much lies outside.** The
   `may span the window boundary` warning names the dollars and seconds past `to`, and
   whether they were counted.
3. **The `predates the share rule` warning fires on every sweep**, not only the one that
   changed the annotation — `annotate_frozen_record` returns what changed separately
   from what is annotated.
4. **The claimant scan runs once per capture**, not once per selected session — the
   manifests are indexed into `share_ctx` before the walk.

## The diff

Base is `shared-session-share`. `git diff shared-session-share...HEAD --stat`, then the
full diff. Read `self/features/claim-window-precision/NOTES.md` for the implementer's
rulings and `CHECKPOINT.md` for the shape of the build.

## Contracts to hold it to

- **Nothing frozen moves.** No `planning.json` outside this feature's own directory may
  change a dollar, a duration, `started_at`, `ended_at` or `captured_at`. Verify from
  `git diff shared-session-share...HEAD -- 'self/features/*/planning.json'`.
- **The stamp is tighten-only.** No path — close, `--recapture`, `set-window-to` — may
  move a `to` later than it already is. A widened bound re-admits sessions another
  manifest may chain onto.
- **The stamp precedes the capture and is rolled back with it.** A refused capture
  leaves the manifest byte-identical to HEAD, as `rollback_carry` and
  `rollback_recovery` already guarantee for their files.
- **`--last-branch-instant` selects exactly what the capture would select by branch** —
  same window test, same `exclude_sessions`, pinned sessions excluded from the evidence
  (a pinned coordinator outlives the feature by design). Two selection rules would drift.
- **The unshared path is byte-identical** to what `shared-session-share` left it: the
  quantified warning is prose only; `session-share.sh` phase 6 must still pass unchanged.
- **The index is a refactor.** `session_claim_intervals`' answer for every session is the
  same as before — `session-claims.sh` and `session-share.sh` are the proof; a test now
  asserts the parse count is independent of the session count.
- **README rules.** `analysis/README.md`'s CLI docs and `feature-close.sh` ordering,
  `self/tests/README.md`'s rows, `LIFECYCLE.md` step 6 and `feature-close.sh`'s own header
  all describe the new ordering; `AGENT_PLANS.md`'s "Set `to` as soon as the feature is
  done" paragraph must not contradict the close now stamping from evidence.
- **Every new assertion is red without its change.** The brief requires the implementer
  to record, in NOTES.md, the mutation each new assertion was checked against. Spot-check
  one: the tighten refusal, or the twice-fired warning.

The highest-value finding is a missing assertion. Local fixes here; structural ones
escalated with the assertion that would have caught them.

## Verdict

What the feature was supposed to do; whether it does it; fixed here / escalated to the
next batch. "No findings" is a legitimate verdict.
