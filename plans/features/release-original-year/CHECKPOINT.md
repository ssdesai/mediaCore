# Checkpoint: release-original-year

status: committed
updated: 2026-09-24T16:41:55Z
gate: === gate: done — all checks passed === (install, lint, fixture idempotent, wheel contains fixture, tests: 307 passed)

## Slices
- [x] acceptance tests — tests/test_release.py, tests/test_bundle.py, tests/test_fixture.py,
      frozen asset tests/assets/its-saxy-schema-2/release.json; committed c4eeaa25
- [x] 1. `Release.original_year` + `_original_year_is_plausible`; `EARLIEST_ORIGINAL_YEAR`;
      `SCHEMA_VERSION` 3 (src/mediacore/release.py); bundle.py docstring
- [x] 2. package 0.4.0 (pyproject.toml, src/mediacore/__init__.py)
- [x] 3. fixture generator `ORIGINAL_YEAR = None`; fixtures/its-saxy regenerated
- [x] 4. INTEGRATION.md §3, §5 layout comment, §6, §12, §13; PROJECT_FACTS.md; root README
- [x] 5. READMEs: src/mediacore, tests, tests/assets, fixtures; BACKLOG.md two entries
- [x] gate green; build committed 80863bb6, then this checkpoint

## Learned
- The gate's fixture-idempotence check reads `git status --porcelain fixtures/`, so a
  regenerated fixture must be committed before the gate runs.
- Pytest before the gate shows the version-metadata test red until the gate's install
  step re-installs 0.4.0 into the venv.

## Resume
- Nothing to resume: review pass (`review/incomplete/01-review-opus.md`) is next.
