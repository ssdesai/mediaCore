Verdict: escalated

# Review: harness-driver-measures

## What the batch was supposed to do

The rule for this feature: *measuring is the driver's, building is the arm's*. The arm's old vendored `agentTooling/` only builds. The driver's copy does all measuring and bookkeeping. The feature had five parts:

1. a literal template fill that `patsub_replacement` cannot break;
2. cost capture and the report run from the driver's `analysis/`, using `--arm-root`;
3. the PR lookup and open go through the driver's `forge.sh`, using `FORGE_CHECKOUT`, and the harness opens a missing PR itself (`pr_opened_by_harness` plus an intervention);
4. an unfetched base is fetched once by sha;
5. a cell recorded `no-pr` can be resumed with `--from review` without re-running the method.

## Does it do it

Mostly, yes. The gate is green, with nothing SKIPPED.

- **`forge.sh`:** `FORGE_CHECKOUT` is optional and defaults to `$SCRIPT_DIR`, so callers that don't set it behave as before.
- **`roots.py`:** `--arm-root` only changes the ordinary artifact root. With `--self` it is a usage error, which `T4g` asserts.
- **Bash 3.2 rules:** followed.
- **Out-of-scope files:** none touched. No method templates are in the diff.
- **Docs:** `harness/README.md`, `SPEC.md` and `EXPERIMENTS.md` carry the driver/arm rule and the full `pr_opened_by_harness` field.
- **Tests:** the smoke tests for the harness-opened PR, the no-commit method and the resume path actually check behaviour. Each would fail if that behaviour regressed.

One part of the spec was not fully met; I fixed it in this pass (below). One required behaviour has no test (escalated).

## Fixed in this pass

- `harness/lib.sh:743` (`harness_gate_counts`) still used `${counts//|/$GATE_COUNTS_JOIN}`. That is a variable replacement, which item 1 says must not remain anywhere in the harness. The output was not wrong today, because the join string `' | '` contains no `&` or `\`. But it is exactly the pattern the fix exists to remove. It now goes through `harness_replace_literal`.
- `self/tests/harness-driver-measures.sh`: added `T1e`, which greps `harness/*.sh` and `harness/methods/*/run.sh` for any `${x//pat/…$var}` outside a comment. Before this, nothing stopped the pattern coming back. I confirmed the grep matches the old line and finds nothing now, and the test file passes.
- `self/tests/README.md`: the `harness-driver-measures.sh` entry now mentions `T1e`.

## Escalated to the next round

- **Nothing tests that the method cost is re-captured on resume.** Item 5 requires a `no-pr` resume to price the method again at the driver's rates. In code, `do_pr_resume` sets `RECAPTURE_METHOD=true` and `capture_one` (`harness/run.sh` ~line 604) then passes `--recapture` for `$SLUG`.
  - **The gap:** the smoke resume section (`harness/tests/smoke.sh`, "9c2c") checks that no model call happens, the row and interventions, the stage outcome and the worktree cleanup. It never checks the cost. If `RECAPTURE_METHOD` were deleted, or the `elif` dropped, the resume would keep the method's old frozen `planning.json` and every check would stay green.
  - **Fix:** add an assertion to 9c2c. For example, seed the first run's frozen `planning.json` for the slug with a sentinel `cost_usd.total` or `captured_at` before the resume. Then assert that after `--from review` the record was rebuilt (its `captured_at` is newer, or the row's `cost_method_usd` is no longer the sentinel), or that `$LOG_DIR/<branch>-capture.log` shows the recapture. I did not add this myself because building that fixture needs a smoke run to check it, which is the next round's job.
