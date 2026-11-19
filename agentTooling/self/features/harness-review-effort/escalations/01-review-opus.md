Verdict: escalated

# Review: harness-review-effort

## What the batch was supposed to do

Add `HARNESS_REVIEW_EFFORT`, the `--effort` level for the harness review stage and its usage-limit retry. These are the same calls `HARNESS_REVIEW_MODEL` covers. The spec:

- Unset or empty falls back to `HARNESS_EFFORT`. With both unset there is no flag, so the argv is byte-identical to before.
- It is validated against the same levels, and a bad value is refused with `harness_die`.
- Rework, the methods and the program orchestrator stay on `HARNESS_EFFORT`.
- Both row shapes record `review_effort`.
- `--dry-run` prints the effort of every stage.
- `harness/README.md` and `harness/SPEC.md` document it.

## Does it do it

Yes. The code is correct.

- **Resolution and validation:** both are in `lib.sh`.
- **Review call:** `do_review` (`run.sh`) passes `--effort $HARNESS_REVIEW_EFFORT` on the review call and on its retry. A program cell's per-feature review goes through the same `do_review` (`program-stages.sh:773`).
- **No doubled flag:** `harness_claude` drops its own `HARNESS_EFFORT` when the caller names `--effort`, so no call gets the flag twice.
- **Unset behaviour:**
  - With both variables unset, no flag is added anywhere.
  - With only `HARNESS_EFFORT` set, the review argv is the same as before: `--effort E` comes right after `--output-format json`, now from the caller and not from `harness_claude`.
- **Rows:** cell rows and program rows both gain `review_effort`, with empty recorded as null. `effort` is unchanged.
- **Dry runs:** cell and program dry runs pass the review effort on the review line only.
- **Scope:** the diff stays inside the allowed paths.

## Fixed in this pass

- `harness/README.md`, the cell ledger-row field list (Rule 1): added `review_effort` after `effort`, and a line on what it means (resolved value, falls back to `effort`, null when both are unset, absent on older rows).
- `harness/README.md`, the program-row field list and the "mean what they mean on a cell row" list: added `review_effort`.
- `harness/tests/README.md`: the gate's harness test count said "nine" and its list of step names left out `harness review effort self-test`. It now says ten and names that step.

## Escalated to the next round

1. **Untested invariant: no call carries two `--effort` flags.** This is one of the brief's contracts, and the code depends on the guard loop in `harness_claude` (`harness/lib.sh`, the `for arg in "$@"` loop after `effort_args`). No test runs a real `harness_claude` call with both `HARNESS_EFFORT` and `HARNESS_REVIEW_EFFORT` set:
   - The full smoke run sets only `HARNESS_REVIEW_EFFORT`, so `HARNESS_EFFORT` is empty and doubling cannot happen there.
   - The `HARNESS_EFFORT=max` smoke run starts at `--from rework`, so the review call never runs.
   - `review-effort.sh` checks dry-run text, which never goes through `harness_claude`.

   Failure scenario: delete the guard loop. Every check stays green, but under `HARNESS_EFFORT=low HARNESS_REVIEW_EFFORT=max` the real review call is `claude -p --output-format json --effort low --effort max …`, and the effort it runs at depends on how the CLI parses a repeated flag.

   Work for the next build plan: add a case to `harness/tests/review-effort.sh`.
   - Source `lib.sh` with `HARNESS_CLAUDE_BIN` pointing at a stub that writes its argv to a file.
   - Call `harness_claude <out> <prompt> <cwd> --effort max --model m` under `HARNESS_EFFORT=low`.
   - Assert that exactly one `--effort` is in the argv and that it is `max`.
   - Also call `harness_claude` with no `--effort` and assert that `--effort low` is present, so the fallback is pinned too.
