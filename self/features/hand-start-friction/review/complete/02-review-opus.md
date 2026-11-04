# 02 — review: hand-start-friction, round 2

The re-review after round 1 escalated. Read the spec first: the manifest
`self/features/hand-start-friction/README.md` (its opening paragraph and "Deliberately
excluded"), and round 1's brief, `review/complete/01-review-opus.md`, whose contracts all
still hold. Then read the escalation, `escalations/01-review-opus.md` → "Escalated to the
next round". That is this round's work order. Read `NOTES.md` → "Round 2" after the diff,
to check its claims. "No findings" is a legitimate verdict (AGENT_PLANS.md → "Review
plans").

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. The round-2 change is the commits
after `hand-start-friction: review stamps`:
`git diff <that commit>..HEAD`.

## Contracts to hold it to

- Each of the four escalated contracts is asserted by a test that would fail if the
  contract broke:
  - **W1f:** `--wait` exits 1 and says "without recording an exit code" for a dead pid
    with no `cloud-setup.rc`.
  - **W1g:** `--wait` exits 1 with "still running after" when the copy's
    `WAIT_TIMEOUT_SECONDS` is below the step's length.
  - **W1h:** under the local profile, both the setup and `--wait` exit 0 and write no
    `cloud-setup.*` file in the git dir.
  - **R4** in `self/tests/cloud-start.sh`: a resumed `--method hand` cloud start keeps an
    existing, extended brief byte for byte, and its review line says "kept from the
    earlier start".
- The new tests leave no background process running past their own scenario, and use
  named constants for their timings.
- The two round-1 pass fixes in `feature-start.sh` stand: the wait refusal says to re-run
  `plans/cloud-setup.sh`, and the hand brief tells the reviewer not to re-run the gate.
- `self/tests/README.md` describes W1f–W1h and R4.
- The gate's report (`self/gate-report.txt`) shows it green on this tree. Read it; do not
  re-run the gate.
- Nothing under `hooks/` changed, and nothing beyond the escalation was widened.

## Verdict
