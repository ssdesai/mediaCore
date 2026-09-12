# Checkpoint: claim-window-precision

status: committed              planned | tests-written | implementing | gating | committed
updated: 2026-09-09T15:31:00Z
gate: all checks passed (67 checks, 0 SKIP)

## Slices

The build, verify and review passes are committed (`34fbfee`). What is left is the rework
one-shot over the review's five escalations (`self/review-report.md` → "Escalated to the
next batch"; `self/features/claim-window-precision/rework-brief.md`).

- [x] rework acceptance tests, committed alone — `feature-lifecycle.sh` W1/W3/W4 amended
      and a new W5, `session-share.sh` phase 14, `user_line` in `build-transcript.sh`
- [x] 1. item 1 — a subagent under W1's session outliving it moves the bound
      (fixture and assertion only; the code already does it)
- [x] 2. item 2 — W1's fixture carries sub-second precision, the bound does not
      (fixture and assertion only)
- [x] 3. item 3 — `WIDEN_REFUSED_EXIT = 3` in `manifest.py`; `feature-close.sh` tolerates
      exactly that code and REFUSES on any other non-zero, rolling back the carry and the
      recovery on that path
- [x] 4. item 4 — `set-window-to --tighten` refuses a bound at or before the fence's `from`
- [x] 5. item 5 — the boundary warning drops the dollars and the seconds when both are
      nothing, and says no billable response falls past `to`
- [x] 6. READMEs (`analysis/`, `self/tests/`), `feature-close.sh`'s header
- [x] 7. red-proof every new assertion by mutation; record each in NOTES.md's rework table
- [x] 8. gate green, commit

## Learned
- The reviewer's two fixture lines for items 1 and 2 collide if taken literally: a subagent
  ending at `13:00:00Z` makes the session's `…:00.700Z` irrelevant to the bound. Both
  fixture instants therefore carry `.700`, so W1b is red against the subagent-loop deletion
  AND against dropping the truncation, and W1d pins the truncation on its own.
- The stamp step runs AFTER the carry and the recovery and BEFORE the capture, so a refusal
  there rolls those two back — but never `rollback_stamp`, which by construction has
  nothing to undo: `set-window-to` writes nothing on a refusal.
- W5's feature needs a real branch session, or the close would refuse at the capture anyway
  and "refuses on a non-widen stamp failure" would pass vacuously under its mutation.
- The tolerated exit code lives in two files (bash cannot import it), so W6 pins it from
  the close's side. The evidence is clamped by the window it is derived under, so the only
  bound it can widen is one written BETWEEN a selected session's first and last line —
  hence the 12:45 middle line in the W1 fixture.

## Resume
- `git -C /Users/sahildesai/dev/agentTooling-claim-window-precision log --oneline shared-session-share..HEAD`
- `bash self/tests/feature-lifecycle.sh`, `bash self/tests/session-share.sh`
- `bash self/gate.sh` (~3 min), verdict in `self/gate-report.txt`
