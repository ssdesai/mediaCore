# Checkpoint: bounded-opening-stretch

status: committed          planned | tests-written | implementing | gating | committed
updated: 2026-09-10T04:25:01Z
gate: all checks passed

## Slices (rework — the review's four escalations)
- [x] acceptance tests: session-share.sh phase 16 (a remainder that is all head prints no
      zero "rest") + phase 17 (a response exactly ON head_bound is paid) + 15f-duration*
      (the in-flight exemption on the seconds) + 8c (the no-head sentence). RED against
      the pre-rework tree: 16c, 16d. RED under the `<`→`<=` mutation: 17a, 17b, 17c
      (and 16a/16b, which move with it). The rest are guards.
- [x] 1. capture_planning.py: the head branch drops the "and … is the rest" clause and
      the "For the rest" sentence when rest_cost and rest_seconds are both zero, and the
      head's remedy stops being introduced as "For the head" when there is no rest
- [x] 2. docs: analysis/README.md's bound paragraph, self/tests/README.md's
      session-share row (16, 17, 15f-duration*, 8c) and its phase-8 clause,
      session-share.sh's header phase list and red-proof notes
- [x] 3. NOTES.md — "The rework: the review's four escalations": rulings, both mutations,
      the red-proof table, and the correction to finding 2's "all 84 green"
- [x] gate green (67 sections, 666 checks, 0 FAIL, 0 SKIP; session-share 97/97);
      one commit `rework — review escalations 1–4`

## Learned
- `in_window` is half-open (`from` inclusive, `to` exclusive), so two claimants chain at
  `to == from` with no gap — that is how phase 16's "every unclaimed instant is head"
  fixture is built without a third claimant.
- `head_bound == session start` means `partition_seconds` adds no cut point for it (its
  guard is `start < head_edge < end`); the `[bound, from)` segment is then judged at
  `start` by `share_owners`' fallback directly, which is what phase 17 exercises.
- Finding 2's "leaves all 84 checks green" is not quite right: the `<`→`<=` flip is
  caught on the SECONDS by 15d/15d-unclaimed. The dollars at the edge were the real gap.

## Resume
- Nothing outstanding. One rework commit on `bounded-opening-stretch` above a3b1ebd.
  Not pushed, no PR — PR #39 is already open on this branch from the review pass.
- Verify: bash self/tests/session-share.sh (97/97); bash self/gate.sh (~3 min).
