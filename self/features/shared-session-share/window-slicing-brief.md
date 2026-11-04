# Brief: price a pinned session by its manifest window

**Repo:** agentTooling — standalone checkout at `/Users/sahildesai/dev/agentTooling`,
vendored into consumers as `agentTooling/`. Build it there as a `--self` feature.

## The bug

`analysis/capture_planning.py` uses the manifest's `session_window` to decide *whether*
to count a session, then prices the **entire** transcript regardless of that window.

`select_parent` (`capture_planning.py:1407`):

```python
selected = pinned or in_window(start_ts, window)      # :1430  membership — window used
...
session_start[session_id] = start_ts                  # :1451  min over ALL timestamps
session_end[session_id]   = end_ts                    # :1452  max over ALL timestamps
...
for model, usage, is_sidechain in iter_billable_messages(lines):   # :1465  window ignored
    add_usage(totals, (session_id, None, model, is_sidechain), usage)
```

For a branch-selected session this is nearly harmless — membership is decided on
`start_ts`, and a session that outruns `to` only earns a "may span the window boundary"
warning. For a **pinned** session it is unbounded: a pin is claimed "whatever the window
says", so one long coordinator session is billed in full to every feature that pins it.
`feature-start.sh` pins the session that runs it, so a session that starts N features
pins itself into N manifests as a matter of course.

## Evidence

Session `3571cc77-2693-49e4-983f-b3f730c0c106` (vinylCatalogue) started
2026-09-07T20:02:37Z and cost $47.18. It planned one feature and hand-built three more,
and is pinned by all four. After three of them closed, `~/.claude/subagent-claims.json`:

```
reading-search-followups     pinned  $47.18
group-photo-lightbox         pinned  $47.18
group-record-picker-search   pinned  $47.18
```

$141.54 booked for $47.18 spent. All three also report `duration 1367.1 min` — 22.8 h,
the session's whole span — for features that took an evening, eight minutes, and an
afternoon. And the session predates the earliest of the three by sixteen hours, so each
is charged for work no feature here owns.

Nothing refuses this, by design: `record_session_claims` says "two features may both
legitimately count one coordinator, so the ledger records both and neither is refused."
The `also_claimed_by` annotation discloses the sharing. Nothing splits the money.

## Fix, part 1 — slice pricing and duration by the window

In `select_parent`, price and time only the lines whose own timestamp is `in_window`:

- filter `lines` to the in-window subset before `iter_billable_messages`. Filter *lines*,
  not usages: `transcript.py` stays untouched, and since every content block of one API
  response shares a timestamp, the message-id dedup inside the iterator is unaffected.
- derive `session_start` / `session_end` from the in-window timestamps rather than the
  full min/max, or the 1367-minute durations survive the fix.

Decide these deliberately:

- **Branch-selected sessions too, or only pinned ones?** Both is more correct and
  subsumes the existing boundary warning — but it silently drops a tail that is counted
  today. Recommended: both, and change that warning from "may span the boundary" to a
  statement of how much was excluded.
- **`to: null`** must keep meaning "to the end of the transcript"; **`from: null`**,
  "from the beginning". Not "nothing".
- Sidechain lines in the parent transcript are priced here as well — slice them alike.

## Fix, part 2 — the windows have to be disjoint, and aren't

Slicing is only correct if windows don't overlap. `feature-close.sh` stamps
`session_window.to = now`, i.e. the moment the close was run, not when the feature's work
ended. The four in this repo:

```
reading-search              12:26:12 -> null (has not closed)
reading-search-followups    14:33:47 -> 18:50:00
group-photo-lightbox        14:58:09 -> 18:50:16
group-record-picker-search  15:06:30 -> 18:50:31
```

The `from` bounds chain correctly — each is the next feature's start. Every `to` is close
time, so three windows nest, and slicing alone would still triple-count 14:58 -> 18:50.
This never showed on an ordinary feature because branch selection did the work; it only
bites when one pinned session spans several features.

Options: stamp `to` from the feature branch's last commit instead of `now`; or, when a
feature's pinned session is also pinned by a later feature, chain `to` to that feature's
`from`. `in_window` is already half-open precisely so consecutive windows chain end to
end — the machinery exists, the stamp just doesn't use it.

## Tests

Nearest existing: `self/tests/claims-ledger.sh`, `self/tests/subagent-capture.sh`. Add
one that builds a synthetic transcript spanning two adjacent windows and asserts each
feature is priced only its own slice **and** that the slices sum to the undivided total —
the second half is what catches a filter that drops messages on both sides.

## What this does not fix

`--all` never re-derives a frozen `planning.json`. The three wrong records are repaired
only by `capture_planning.py --recapture <slug>` followed by `report.py`, and only while
the transcript survives — so do it promptly. `reading-search` has not closed yet (it
refused on an unpinned delegate), so it captures correctly the first time if the fix
lands before its close.

## Pushback caveat

agentTooling is vendored as a subtree and squash pulls break `git subtree push`. Apply
the patch onto a worktree of upstream main rather than pushing the vendored tree, then
`update.sh` in each consuming repo.
