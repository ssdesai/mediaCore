Verdict: clean

# Review: orchestration-records (round 2)

## What this round was supposed to do

The round had two jobs. The first was to close the two missing tests that round 1
escalated (`self/features/orchestration-records/escalations/01-review-opus.md`). The second
was to keep holding the whole feature to its spec, `self/features/orchestration-records/README.md`,
and to the contracts in the round 1 review.

The feature adds the **orchestration record**:

- `orchestration-start.sh`
- `manifest.py --orchestration`
- `orchestration-capture.sh` together with `capture_planning.price_session_in_window`
- the optional `orchestration` key that `feature-start.sh --orchestration` writes
- `report.py --orchestration`
- the docs that go with them

## Does it do it

Yes. Both escalations are closed by tests that would fail without the code they protect.

- **`feature-start.sh --orchestration`** is covered in `self/tests/feature-lifecycle.sh`:
  - **S2g:** a start with `Bad/Slug` exits 1 and leaves the branch set and the worktree
    path unchanged. Deleting the slug-shape refusal would let that start succeed and create
    a branch, so the test would fail.
  - **S2h:** a start with `grp-x` writes `grp-x` to the committed fence's `orchestration`
    key. Deleting the `orchestration_args` pass-through would leave the key missing, so the
    test would fail.
  - **S2i:** the earlier plain start's fence (`$FD`) has no `orchestration` key.
- **`routing.START_VALUE_FLAGS`** is covered by R10a2 in `self/tests/routing-record.sh`. If
  `--orchestration` were taken out of that set, `slug_of_start_line` would skip the flag as
  a bare one and read `grp-x` as the slug. The flag-first form would then fail the test.

The rest of the diff matches what round 1 reviewed, with no new drift. The gate report is
green with no SKIPs, and it includes `feature-lifecycle.sh` ("all assertions passed") and
`routing-record.sh`.

## Fixed in this pass

- `self/features/orchestration-records/NOTES.md`: the last bullet still said
  `feature-start.sh --orchestration` was "not exercised end to end". That stopped being true
  this round. The bullet now names S2g–S2i, R10a2 and `orchestration-records.sh` S4 as the
  coverage.

## Escalated to the next round

None.

## Noted for the reader (not escalated)

Round 1 already listed these as known limits, and they are unchanged:

- `orchestration-start.sh` does not escape a hand-typed `--session` before writing it into
  the JSON fence. A bad value fails loudly rather than silently.
- `report` paths in the record resolve against the agentTooling root. This is documented.
