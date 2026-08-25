# Level 1 level-verify — the `mediacore` package

Feature `release-contract` (level-verify for sentinel `08-gate.md`). Runs only when
level 1's gate is red.

Must be green at this level: `install`, `lint`, `tests`. `tests/test_fixture.py` is
expected-red here and `fixture idempotent` is deferred — both belong to level 2, and
neither is yours to fix. Read `plans/gate-report.08.txt` first; do not re-run install,
lint or the suite before triaging it.

Contract rows this level owns, and may therefore change: the `Release` field list
(`src/mediacore/release.py`), the ref-key grammar (`src/mediacore/refs.py`), the bundle
layout (`src/mediacore/bundle.py`), and `its_saxy_bundle()`
(`src/mediacore/fixtures.py`). Fix the tree to those contracts; the queued plan 09
pins their names and shapes, so renaming or re-typing any of them makes it wrong.
