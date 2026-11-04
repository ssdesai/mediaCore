Verdict: escalated

# Review — hand-start-friction

## What the batch was supposed to do

Three fixes for snags that every hand-method session in a consuming repo hit
(`self/features/hand-start-friction/README.md`):

1. **Cloud setup race.** In the cloud, a consuming repo's `feature-start.sh` waits for the
   setup `session-start.sh` started in the background (`plans/cloud-setup.sh --wait`)
   before it runs the setup hook and the base gate.
2. **Review stub refusal.** Under `--method hand`, the start writes a complete brief with no
   `@@TODO@@`. `plans` and `direct` starts keep the stub, and the runner still refuses it.
3. **Chain line.** `update.sh`'s `chain intact` line is now a whole sentence.

## Does it do it

Yes. Checked against the brief's contracts, from the diff against `origin/main`:

- **Wait.**
  - The wait runs only when all of these hold: `profile_is_cloud`, not `--self`, and the
    copy exists and contains `--wait`.
  - It sits after the cloud lock is written and before the hook and the gate.
  - It prints exactly one `setup` line, because `--wait` prints nothing on success.
  - It refuses on a non-zero exit and leaves the lock in place, so the start can be
    resumed.
  - `feature-start.sh` reads no profile variables itself.
  - Under the local profile nothing runs.
- **Template v3.**
  - `--wait` is bounded by `WAIT_TIMEOUT_SECONDS`.
  - It exits 0 when no pid file was ever written, and 1 when the recorded exit code is
    non-zero or missing.
  - `setup_in_background` starts nothing while an earlier step is still alive, and writes
    only under `git rev-parse --absolute-git-dir`.
  - The detached subshell's stdout and stderr go to the log, with stdin from `/dev/null`.
  - Outside the cloud profile the script still exits 0 before any of this, `--wait`
    included.
  - The skeleton's unconfigured behaviour is unchanged.
  - The code uses only bash 3.2 constructs.
  - The version line is 3, `TEMPLATE_VERSIONS` is re-recorded, and `sync-check.sh` 1m and
    `template-version-bump.sh` B2/B7 have moved to 3.
  - The only remaining "1 < 2" text is the historical "Adopting cloud-setup.sh version 2"
    section, which is correct to keep.
- **Hand brief.**
  - It names the manifest as its spec, gives the diff and the gate, and asks for the
    feature's own contracts.
  - A resumed start keeps an existing brief that has no marker.
  - `plans` and `direct` still get the stub.
  - The refusal in `run_all` names the queued path and the `failed/` path relative to the
    repo root, plus the three things a brief holds.
  - "Next" step 1 tells the truth in each branch: a kept stub, hand, and a kept real brief.
- **Chain line.** The text matches exactly, and C4b asserts the whole line.
- **Tests.** `cloud-setup-wait.sh` is registered twice in `self/gate.sh`. W2a2 (waited at
  least 1s) and W2c (the hook saw the step finished) fail without the wait.
- **Gate.** `self/gate-report.txt` says "all checks passed". The cloud-setup-wait,
  feature-lifecycle, subtree-chain, sync-check and template-version-bump checks are all in
  it.
- **Scope.**
  - Nothing under `hooks/` changed.
  - The new literals are all named constants.
  - NOTES' `.venv` claim holds: the templates only create a venv with `python3 -m venv`,
    which succeeds on an existing one, and `uv` appears only as `uv run` / `uv pip`.
- **READMEs.** The root `README.md` (feature-start row, templates row, "Adopting
  cloud-setup.sh version 3"), `LIFECYCLE.md`, `templates/`, `self/` and `self/tests/` all
  describe the change.

## Fixed in this pass

Both fixes are in `feature-start.sh`. No test asserts the changed text: W3b matches only
the refusal's prefix, and S3d3 matches only `self/gate.sh`. `bash -n` is clean.

1. **The wait refusal didn't say how to recover.**
   - `--wait` only reads the exit code the failed step recorded. After the human fixes the
     cause, re-running the start re-reads that same code and refuses again.
   - Only re-running `plans/cloud-setup.sh` retries the step. The old text said "fix it,
     then run this again", which is exactly the loop this feature exists to remove.
   - The message now says to run `$CLOUD_SETUP_LABEL` again, so the step is retried, and
     then the start.
2. **The hand brief told the reviewer to re-run the gate.**
   - Its contract line said the gate "is green on this tree: run it."
   - This contradicts the review pass's own instructions: read `gate-report.txt` and don't
     re-run the gate. It would also spend a full gate run at review-model rates.
   - It now says the gate's report shows it green and the review doesn't re-run it.

## Escalated to the next round

1. **Several contracts the brief names have no test.** They hold on reading, but nothing
   keeps them true. Add these to `self/tests/cloud-setup-wait.sh` and
   `self/tests/feature-lifecycle.sh`:
   - **W1f, missing exit code.** Kill a background step's pid, or leave a pid file whose pid
     is dead with no `cloud-setup.rc`. `--wait` must exit 1 with "without recording an exit
     code".
   - **W1g, timeout.** Make the copy with `setup_copy`, then use `awk` to replace
     `WAIT_TIMEOUT_SECONDS=1800` with a value below `SLOW_STEP_SECONDS`. `--wait` on a
     running step must exit 1 with "still running after".
   - **W1h, local no-op.** Run the template under `AGENTTOOLING_PROFILE=local` with
     `--wait`. It must exit 0 and write no `cloud-setup.*` file in the git dir.
   - **S3d5, resumed cloud start keeps a hand brief.** On a resumed cloud start, an existing
     hand brief that the coordinator extended must be kept byte for byte, and the review
     line must say "kept from the earlier start". The existing cloud-start resume fixture
     in `self/tests/cloud-start.sh` is the natural place.

No other findings.
