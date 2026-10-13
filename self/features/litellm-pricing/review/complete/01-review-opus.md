# 01 — review: litellm-pricing

feature: agentTooling/litellm-pricing

Review a direct one-shot build independently. This brief was written from the spec before
the build. Read the spec in `self/features/litellm-pricing/README.md` → "Spec" and
"Deliberately excluded" first, and hold the diff to that spec, not to the implementer's
`NOTES.md`. Read `NOTES.md` only to judge whether each ruling in it is sound.

## What the feature was supposed to do

Replace the hand-kept `RATES` dict in `analysis/pricing.py` with a dated, append-only rate
history, `analysis/rates_history.json`. `pricing.get_rates` reads the history, and a new
command, `analysis/refresh_rates.py`, appends to it from LiteLLM's
`model_prices_and_context_window.json`. `feature-capture.sh` reports whether the history is
stale and runs `refresh_rates.py --check` as a warning. It never writes the history.

## The diff

Base is `main`. Run `git diff main...HEAD --stat`, then read the full diff. Also read
`analysis/README.md` and `self/tests/README.md` as they are at `HEAD`.

## Contracts to hold it to

1. **No figure moves.** For every model the old `RATES` priced, and for dates on both sides
   of 2026-08-22, `get_rates` at `HEAD` must return the same `input`, `output`,
   `cache_read`, `cache_creation_5m` and `cache_creation_1h` as `main`'s `pricing.py`.
   Check this yourself: write a scratch script that imports both copies (`git show
   main:analysis/pricing.py` into the scratchpad) and compares them. Don't rely on the
   build's own test for it. Any difference beyond float rounding is a finding.
2. **Append-only.** `refresh_rates.py` never edits or deletes an existing entry. Running it
   twice against the same source adds nothing the second time; only `checked` may change.
   A model LiteLLM lacks is left untouched.
3. **Re-pricing is reproducible.** After a refresh that changes a model's rate, a session
   dated before that refresh prices at the old rate. That is the property that lets
   `--recapture` reproduce frozen figures.
4. **Unknown model is `(None, None)`**, never 0, exactly as before.
5. **`rates_applied` shape.** It gains `source` and `from`, and every existing field is
   kept (`model, input, output, cache_read, cache_creation_5m, cache_creation_1h, tier`).
   Every README that lists `rates_applied` fields (the field lists in
   `analysis/README.md`) must be updated to match (CONVENTIONS Rule 1).
6. **Offline tests.** The new `self/tests/*.sh` must never touch the network. They must go
   through `--source <fixture>`. Each new test file has its row in `self/tests/README.md`.
7. **The capture never writes the history and never refuses on it.** A `--check` that
   finds differences, or that cannot fetch, prints a warning and the capture carries on.
   Check `feature-capture.sh`'s stray-path rules as well: nothing new may appear in the
   worktree after a capture.
8. **Stdlib only, bash 3.2, named constants** (`self/PROJECT_FACTS.md`, `CONVENTIONS.md`),
   including the LiteLLM URL, the exit codes and the float tolerance.
9. **Every caller of the removed names still works.** The removed names are `RATES`, the
   cache multiplier constants and the `intro` handling. The callers to check are
   `capture_planning.py`, `recover_attempts.py`, `routing.py`, `report.py`,
   `feature-capture.sh`, and any `self/tests/` script or fixture that imported them.
   `./self/gate.sh` must be green; run it yourself.
10. **The excluded items stay out.** Long-context pricing must have its `self/BACKLOG.md`
    entry.

## Verdict

Open the report with exactly one line: `Verdict: clean` or `Verdict: escalated`. "No
findings" is a legitimate verdict. Fix local defects yourself, commit the fixes, and say
what you fixed. Escalate only what is structural: something the spec got wrong, or a
change too large to make in a review.
