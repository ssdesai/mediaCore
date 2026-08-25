# Level 2 level-verify — the IT'S SAXY fixture

Feature `release-contract` (level-verify for sentinel `10-gate.md`). Runs only when
level 2's gate is red.

Must be green at this level: `install`, `lint`, `fixture idempotent`, and the whole
suite including `tests/test_fixture.py`. Read `plans/gate-report.10.txt` first; do not
re-run install, lint or the suite before triaging it.

Contract rows this level owns: the generator CLI
(`scripts/make_fixture_its_saxy.py [dest]`, which `plans/gate.sh` calls twice) and the
bytes under `fixtures/its-saxy/`. Everything the generator imports from `mediacore` is
level 1's and is green on disk — read it rather than changing it.

`tests/test_fixture.py` is the specification of what the generator must produce. When
the two disagree, the test is right unless it contradicts `INTEGRATION.md` §11; say so
in `escalations/10.md` if it does, rather than editing the assertion.
