# Checkpoint: release-original-year

status: gating
updated: 2026-09-24T16:41:17Z
gate: not run yet

## Slices
- [x] acceptance tests — tests/test_release.py, tests/test_bundle.py, tests/test_fixture.py,
      frozen asset tests/assets/its-saxy-schema-2/release.json; committed c4eeaa25
- [x] 1. `Release.original_year` + `_original_year_is_plausible`; `EARLIEST_ORIGINAL_YEAR`;
      `SCHEMA_VERSION` 3 (src/mediacore/release.py); bundle.py docstring
- [x] 2. package 0.4.0 (pyproject.toml, src/mediacore/__init__.py)
- [x] 3. fixture generator `ORIGINAL_YEAR = None`; fixtures/its-saxy regenerated
- [x] 4. INTEGRATION.md §3, §5 layout comment, §6, §12, §13; PROJECT_FACTS.md; root README
- [x] 5. READMEs: src/mediacore, tests, tests/assets, fixtures; BACKLOG.md two entries
- [ ] gate green; commit

## Learned
- Pytest before the gate shows one red — the version-metadata test — only because the
  venv's installed metadata is 0.3.0 until the gate's install step re-installs.

## Resume
- git -C <worktree> status --short; plans/gate.sh; read plans/gate-report.txt
