# Level 1 sentinel — the `mediacore` package

The gate runs here, labelled `08`, over `pyproject.toml`, `src/mediacore/` and the four
unit-test files (plans 02–07).

What this level does **not** own:

- `tests/test_fixture.py` — the batch's acceptance test. It loads
  `fixtures/its-saxy/`, which is level 2's deliverable and does not exist yet.
- The `fixture idempotent` gate section — it runs
  `scripts/make_fixture_its_saxy.py`, written by plan 09 at level 2.

expected-red: tests/test_fixture.py
defer: fixture idempotent
