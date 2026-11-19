Verdict: clean

# Review: harness-review-model

## What the batch was supposed to do

Add `HARNESS_REVIEW_MODEL`, the model the harness review stage runs on. Unset or empty
means `HARNESS_MODEL`. Rework, the methods, the program orchestrator and the implementers
stay on `HARNESS_MODEL`. Both ledger row shapes record the resolved value as
`review_model`, and `--dry-run` names the model on every stage line. The README has to
document the variable and the two facts about effort and the methods directory, and
offline tests have to cover it, registered in `self/gate.sh`.

## Does it do it

Yes.

- **Resolution.** `harness/lib.sh:149` resolves the value with
  `${HARNESS_REVIEW_MODEL:-$HARNESS_MODEL}`, so an unset or empty value falls back to
  `HARNESS_MODEL`.
- **Review calls.** Both review call sites in `do_review` use the review model: the first
  call and the usage-limit retry (`harness/run.sh:552-563`). No other call site does.
  Program cells reach the same `do_review` through `do_program_review`
  (`program-stages.sh:773`), so they inherit the knob.
- **Unset behaviour.** With the variable unset, every call's arguments are the same as
  before.
- **Ledger rows.** `review_model` is added to the ordinary row (`run.sh:776,812`) and the
  program row (`program-stages.sh:911,933`). `model` still holds `HARNESS_MODEL`.
- **Dry run.** The ordinary review line names `$HARNESS_REVIEW_MODEL`. The program cell's
  per-feature review and rework lines now carry `--model` explicitly.
- **Docs.**
  - `harness/README.md` has the variable, the "rework is building" statement and both
    limits (effort only through `harness_claude`; a method's `run.sh` runs from the
    driver's checkout).
  - Both row field lists in the README carry `review_model` (Rule 1).
  - `SPEC.md` is extended: its "every implementer runs at `HARNESS_MODEL`" line is still
    true.
  - No stale statement remains that the review runs at `HARNESS_MODEL`.
- **Tests.**
  - `harness/tests/review-model.sh` is registered in `self/gate.sh` with a `record` line.
    It is syntax-checked through the existing `harness/tests/*.sh` glob.
  - It is named in both READMEs, and the count line reads "all nine", which is correct.
  - `smoke.sh` checks the review call, the rework call and the row.
- **Scope.** The diff touches only `harness/`, `self/gate.sh` and the feature folder.
  Nothing under `.claude/`.
- **Gate.** The gate report is green with no SKIPPED checks.

## Fixed in this pass

1. **The program-cell half of the contract had no test.** The program row's
   `review_model` and the program dry run's review/rework model lines were never asserted:
   the existing checks only count `--effort`, so they would have stayed green if
   `program-stages.sh` dropped or swapped the field. Added to `harness/tests/smoke.sh`:
   - a program dry run under distinct build and review model names. The review model
     appears on exactly one line (the per-feature review line), and the rework line keeps
     the build model.
   - `program row: review_model equals model when HARNESS_REVIEW_MODEL is unset`.

   `harness/tests/README.md` now describes both. I ran `smoke.sh` once to confirm the new
   checks: all checks passed.
2. **Model names in the README.** The example in `harness/README.md:157-158` named
   concrete models (`HARNESS_MODEL=sonnet HARNESS_REVIEW_MODEL=opus`), against the "no
   model name in any file" contract. It now reads `<cheaper model>` / `<stronger model>`.
3. **A default copied by hand into the test.** `harness/tests/review-model.sh` hard-coded
   lib.sh's default (`DEFAULT_MODEL="opus"`). It now reads the default from `lib.sh`, with
   a guard check that the value is non-empty, so the "unset" check cannot pass vacuously.
   I re-ran the test: all checks passed.

## Escalated to the next round

None.

## Notes (not findings)

- **Values come from the environment at record time.** `review_model`, like `model` and
  `effort` before it, is filled in when the row is recorded. A `--from capture`/`record`
  re-run made under different environment variables than the original review would record
  those, not the ones the review actually ran with. This is the existing pattern for all
  three fields, not something this batch introduced.
- **The new test is not executable.** `harness/tests/review-model.sh` is committed with
  mode 100644. That means the `./agentTooling/harness/tests/review-model.sh` invocation
  listed in `tests/README.md` gets "permission denied" unless it is run with `bash`, as
  the gate does. `arm-spec.sh` and `plans-method.sh` have the same mode, so it is the
  existing convention, but a `chmod +x` would make the README line true.
