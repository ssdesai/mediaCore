# 04 — level 1 verify: core

Feature: a killed attempt's cost is recoverable from its session transcript, and
`pricing.py`'s intro tier must not apply to dates before the promotion began.

Tier 1 of level 1's ladder. Read `self/gate-report.04.txt` first — the checks already ran;
do not re-run what it reports. Your job is to make the tree match the contract, not to
change the contract.

Level 1 owns `self/tests/cost-recovery.sh`, `analysis/pricing.py`, `analysis/transcript.py`,
`analysis/recover_attempts.py`, and `capture_planning.py`'s refactor onto the shared helper.

Priorities, in order:

1. **All 12 assertions pass.** If one fails, fix the production code, not the assertion. The
   assertions encode the contract; an assertion edited to match a bug is the failure mode
   this tier exists to prevent.
2. **Assertion 7 in particular.** It is the guard against pricing from `usage.json`'s flat
   `cache_creation_input_tokens` instead of the transcript's 5m/1h split. Confirm by reading
   `recover_attempts.py` that the tokens genuinely come from
   `usage.cache_creation.ephemeral_{5m,1h}_input_tokens`, not merely that the assertion is
   green — a stubbed split would pass the test and be wrong in production.
3. **`capture_planning.py`'s output is unchanged by the refactor.** It has no test of its
   own. Run it against a real feature slug in the consuming repo and diff the resulting
   `planning.json` against `git show HEAD:<path>` for the same file. Any difference other
   than `captured_at` is a regression — report it and fix it.
4. `python3 -m py_compile analysis/*.py` clean, `bash -n` clean on every shell script.

You may edit anything level 1 owns. You may not touch `report.py`, `self/gate.sh`, or the
READMEs — level 2 owns those and its plans are queued behind you.
