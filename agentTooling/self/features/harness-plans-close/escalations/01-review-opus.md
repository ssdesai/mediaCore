Verdict: escalated

# Review — harness-plans-close

## What the batch was supposed to do

Fix the two reasons the `plans` method (`harness/methods/plans/run.sh`) could not finish a cell:

1. Write the batch log outside the arm tree (under `HARNESS_LOG_DIR`), still appended with `>>`.
2. Return `METHOD_USAGE_LIMIT_RC` (2) only when the batch's output for this run shows it stopped on a usage limit or an interrupt. Any other non-zero exit returns 1 straight away, prints the log tail, and does not run the batch a second time.

## Does it do it

Mostly yes. Checked against the brief's contracts:

- **Log outside the tree.** The log is `$HARNESS_LOG_DIR/${HARNESS_BRANCH_NAME:-$SLUG}-plans-batch.log`, appended. `harness/run.sh:234-235` and `program-stages.sh:197` export both variables. A run without the harness falls back to `$TMPDIR`. Nothing else the method writes lands in the tree: the resume prompt and `RESULT` already lived outside it.
- **The evidence strings match the library.** They match `plan-runner-lib.sh:261` (interrupt) and `:1106` (usage limit). Test 7 pins both, so if the library rewords them the gate fails.
- **Only this run's output counts as evidence.** The script records the log's byte offset before the run and reads from there with `tail -c +N`. Test 5 covers this.
- **An escalation or a `failed/` plan still wins.** `batch_stopped_hard` runs before the evidence check. Test 6 covers this.
- **Exit codes** 0/1/2 are unchanged. `harness/lib.sh`, `harness/run.sh` and `feature-close.sh` are untouched.
- **The new test** is registered in `self/gate.sh` and listed in `harness/tests/README.md`. It covers (a), (b) and (c) from the brief and spends nothing.
- **The docs** (`methods/plans/README.md`, `harness/README.md`, `harness/SPEC.md`) no longer say the log is in the tree or that a bare non-zero exit gets one resume.

## Fixed in this pass

- `harness/README.md`: its file table has a row for every other `tests/*.sh`, but none for the new `tests/plans-method.sh`. Added one.

## Escalated to the next round

### 1. After exit 2, the harness's retry runs the architect again instead of resuming the batch

The new `methods/plans/README.md` says: "The harness waits and calls the method again on exit 2, and that call resumes the batch." The code does not do that.

- `harness/run.sh:347-351` handles exit 2 by running the whole `methods/plans/run.sh` again.
- That script always starts at step 1, the architect (`run.sh:49-75`). It adds the "you are resuming" note only when `auto/incomplete/` still holds plans. Once the batch has drained the auto queue, the architect gets the plain brief, as if nothing had been written.
- Step 2 (`run.sh:81-89`) then requires `auto/incomplete/`, `verify/incomplete/` and `review/incomplete/` to be non-empty. A batch stopped by a usage limit after its auto pass has already moved those plans to `inprogress/` or `complete/`.

**Result:** the retry pays for a second architect session, which may write a duplicate corpus. Unless that session rewrites the queues, step 2 exits 1. A usage limit hit after the auto pass therefore still ends the cell with no PR.

**Why this is new:** this path existed before, but only after a second consecutive limit. The old in-script "resume once" handled the common case. This batch removed that resume (correctly, for exits with no evidence), so every usage-limit stop in the batch now takes this path.

**What it should be (a change to `harness/methods/plans/run.sh`):** detect that the batch has already started and skip steps 1–2, going straight to `run_batch`. For example, treat any plan under `*/inprogress/` or `*/complete/` in `$FEATURE_DIR`, or a non-empty `$BATCH_LOG`, as "the batch has started".

**Missing test (`harness/tests/plans-method.sh`):** after a `limit` run, run the method again in `ok` mode with the queues as the runners would leave them (plans moved to `inprogress/` or `complete/`). Assert that it exits 0, that the fake `claude` was not called, and that `run-batch.sh` was called once.

### 2. (minor, same file) The warning's log tail can show an earlier run's lines

On a failure with no evidence, `tail -n 20 "$BATCH_LOG"` reads the whole appended log. If this run printed fewer than 20 lines, the warning also shows lines from earlier runs, which can include an old usage-limit summary. That is the opposite of the verdict the method just reached. Read the tail from the same `BATCH_RUN_START` offset as the evidence check: `tail -c +"$((BATCH_RUN_START + 1))" "$BATCH_LOG" | tail -n "$BATCH_LOG_TAIL_LINES"`.
