Verdict: clean

# Review — hand-start-friction, round 2

## What this round was supposed to do

Round 1 found that the feature's code met its contracts, but escalated four contracts that
no test asserted (`escalations/01-review-opus.md` → "Escalated to the next round"). This
round adds those tests and changes no code. The round-2 diff is `7bcb839..HEAD`:
`self/tests/cloud-setup-wait.sh`, `self/tests/cloud-start.sh`, `self/tests/README.md`,
and the feature's `NOTES.md` and manifest.

## Does it do it

Yes. I checked each test against the template (`templates/plans/cloud-setup.sh`) and
`feature-start.sh`, and each one would fail if its contract broke:

- **W1f.** It runs after W1d, where the step has finished and the pid file is left behind.
  It deletes `cloud-setup.rc`, so `--wait` gets past the liveness loop and the "no pid file"
  exit, then reaches the empty-rc branch. It asserts exit 1 and "without recording an exit
  code".
- **W1g.** It uses `awk` to rewrite the copy's `WAIT_TIMEOUT_SECONDS` to
  `SHORT_TIMEOUT_SECONDS=2`, which is below `SLOW_STEP_SECONDS=4`. `--wait` hits the timeout
  on its second poll, and the test asserts exit 1 and "still running after".
- **W1h.**
  - The consumer has the profile script, which W1a–e already show, so the
    `PROFILE_SCRIPT`-missing early exit can't make this test pass by accident.
  - If the local profile were treated as cloud, the setup run would write `cloud-setup.pid`
    and the `ls` glob check would fail.
- **R4.**
  - A hook refusal leaves a lock. The test then plants a marker-free brief and resumes.
  - `cmp` against a copy proves the brief is kept byte for byte. R4b checks for the exact
    phrase `01-review-opus.md  (kept from the earlier start)`.
  - NOTES says plainly that the brief is planted, since a hook refusal comes before the
    point where the brief is written. That is an honest stand-in.
- **Named constants.** The new timing is `SHORT_TIMEOUT_SECONDS`, and the existing
  `SLOW_STEP_SECONDS` is reused.
- **Round-1 pass fixes.** Both still stand:
  - `feature-start.sh:784`: the wait refusal says to run `plans/cloud-setup.sh` again,
    because `--wait` only reads the recorded result.
  - The hand brief tells the reviewer not to re-run the gate (`feature-start.sh:932`).
- **Docs.**
  - `self/tests/README.md` describes W1f–W1h under cloud-setup-wait and R4 under
    cloud-start.
  - Both test headers list the new assertions.
  - NOTES "Round 2" matches the diff, including "No code changed in round 2".
- **Gate.** `self/gate-report.txt` ends "all checks passed" and shows R4a/b and W1f–W1h as
  `ok`.
- **Scope.** Nothing under `hooks/` changed in the feature's diff against `origin/main`.
  Round 2 touches only tests, docs and the feature's own records.

## Fixed in this pass

1. **W1g's cleanup could leave its background step running.**
   - **Problem:** The "let the step end" `--wait` ran against the copy that still had the
     2-second timeout. The first `--wait` used about 2s of the 4s step, and the cleanup
     `--wait` makes its final liveness check at about 4s. That is a sub-second race with
     the step's own end, so on a loaded machine the cleanup could time out with the step
     still alive. This broke the brief's "no background process past its own scenario"
     contract.
   - **Fix:** The test now saves the unmodified copy (`$TMP/full-timeout`) and restores it
     before the cleanup `--wait`. That `--wait` then runs under the template's own 1800s
     timeout and returns only once the step has ended.
   - **Checked:** `bash -n` is clean. I did not re-run the gate, and the green report
     predates this edit, so the edit itself has only been syntax-checked.

## Escalated to the next round

None.
