# 99 — review: bounded-opening-stretch

## What the feature was supposed to do

Bound the opening-stretch fallback in `share_owners`, so that the stretch of a shared
session before every claimant's `from` is paid to the earliest claimant only as far back
as that claimant's own window is long, and falls to the unclaimed remainder — disclosed,
with the remedy named — beyond that. Read
`self/features/bounded-opening-stretch/brief.md` for the defect and the rulings, which
are settled and not reopened here:

1. `share_owners` paid the whole head to the earliest claimant however long it was.
   Session `2d8b1236` ran 45 hours before the first of its three claimants opened; the
   earliest, windowed 25 minutes, owned $50.12 of a $50.92 share.
2. The bound is relative (the earliest claimant's `to - from`), not a fixed duration; an
   earliest claimant still in flight (`to` null) keeps the unbounded head.
3. One helper answers "where does the paid head begin" for both `share_owners` and
   `partition_seconds`, so dollars and seconds cannot disagree.
4. No new `planning.json` field; the head nobody owns goes into `unclaimed_usd` and
   `unclaimed_duration_s`, and the unclaimed warning discloses the head separately from
   the tail with both remedies (pin the session; move `from` back by hand).

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Read
`self/features/bounded-opening-stretch/NOTES.md` for the implementer's rulings and
`CHECKPOINT.md` for the shape of the build.

## Contracts to hold it to

- **One bound, one place.** `share_owners` and `partition_seconds` derive the head bound
  from the same helper; neither re-derives it inline. The cut point is in
  `partition_seconds`' edge set, or the paid part of the head is lost from `duration_s`.
- **The ranking pool is unchanged.** The earliest claimant is still the `min` on
  `(from, feature)` over dated, non-empty claims; `is_empty_window` and
  `check_empty_window` are untouched; phases 9–11 of `session-share.sh` are unchanged.
- **The sum invariants hold on every path.** Claimants' shares plus `unclaimed_usd` equal
  `session_cost_usd`; apportioned spans plus `unclaimed_duration_s` equal
  `session_duration_s`. Phase 15 asserts both; check that phase 1 and 5 still do too.
- **The no-change halves are asserted, not assumed.** Phase 3 (a head inside the bound is
  still paid) and 15f (an in-flight earliest claimant keeps the unbounded head) are
  green before and after. Nothing under `self/features/*/planning.json` changed.
- **The disclosure is actionable.** The warning states the head's dollars and seconds
  when there is a head, and names both remedies; when the remainder is all tail the
  sentence is the one that was there before.
- **Every red assertion was proved red.** `NOTES.md` records the mutation and which of
  15a–15f were red against `main`'s `capture_planning.py`. Spot-check one.
- **README rules.** `analysis/README.md`'s share paragraph states the bounded rule and
  the empty-window paragraph after it still reads true; the docstrings say the same;
  `self/tests/README.md`'s row for `session-share.sh` names phase 15.

The highest-value finding is a missing assertion. Local fixes here; structural ones
escalated with the assertion that would have caught them.

## Verdict

What the feature was supposed to do; whether it does it; fixed here / escalated to the
next batch. "No findings" is a legitimate verdict.
