# 04 — review

Feature: two ways a recovered total still looks whole and is low.

Read the diff; the gate is green on arrival. Read the manifest's three design resolutions
first — they are decided.

This batch closes two escalations from the batch before it, both of the same class: a total
that reads complete and is low. The question worth your attention is whether it closed them
or moved them.

- **Is there a third instance?** Both defects were a `None` or a missing key coerced to zero
  on the way to a total. Look for the pattern anywhere else in `analysis/` — a `get(..., 0)`,
  an `or 0.0`, a `sum()` over a list that may contain `None`, a bucket assignment that
  defaults. `pricing.py:117-118` states the rule; find who else breaks it.
- **Does `recovered_is_partial` actually reach the top?** The chain is
  `recover_attempts.py` → sidecar → `report.py` → `report.json` → `report.md`. A flag that
  is written and never read is the same bug wearing the fix's clothes.
- **The cross-check.** When top-level and attempt-level disagree, which wins, is that
  documented, and is the warning worded so a reader knows what to do about it?
- **The two new assertions.** Can they fail? Assertion 13 depends on a model id staying
  absent from `RATES`; assertion 14 depends on a hand-built sidecar shape matching what
  `write_usage_sidecar` really produces. Check the second against
  `plan-runner-lib.sh:554-581` rather than trusting the fixture.
- **README field lists.** Rule 1 in `agentTooling/CONVENTIONS.md` applies to `usage.json` and
  `report.json` — both are cross-module on-disk shapes and both gained fields.
