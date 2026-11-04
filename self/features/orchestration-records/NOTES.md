# orchestration-records — notes

Rulings and facts the build rested on.

- **Branch.** The session came up on a detached HEAD with no assigned branch named in the
  brief; the start was run with `--branch claude/orchestration-records` (the conventional
  name its own refusal suggests), so the PR comes from that branch.
- **Where records live.** Always `self/orchestrations/` (`roots.orchestrations_root()`), no
  `--self`: the brief's commands (`report.py --orchestration <slug>`) name no mode.
- **One pricing path.** `capture_planning.price_session_in_window` is new (nothing priced a
  bare session id inside a window); `orchestration_capture.py` only reads the record and
  writes `planning.json`. `routing.price_lines` stays the router's.
- **Scope selection.** `manifest.py --orchestration` is a scope only as the first word; after
  a slug it is `init`'s flag. Dispatching on "anywhere in argv" broke `init` and was caught
  by the test.
- **`add-feature` replaces in place** (order of addition is kept), resetting unset fields.
- **`routing.py`.** `--orchestration` added to `START_VALUE_FLAGS` so a start line carrying
  it does not read its value as the slug. `--branch` is missing from that set too; left to
  the sibling that fixes the capture defect (not this feature's).
- **`feature-start.sh --orchestration` end to end** is `self/tests/feature-lifecycle.sh`
  S2g–S2i (round 2, closing round 1's escalation): a bad slug is refused creating nothing, a
  good one lands in the committed fence, a plain start has no key. `routing-record.sh` R10a2
  pins the flag in `START_VALUE_FLAGS`. `orchestration-records.sh` S4 covers the
  `manifest.py init --orchestration` half.
