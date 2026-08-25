# Level 2 sentinel — the IT'S SAXY fixture

The gate runs here, labelled `10`, and this level owns everything: install, lint,
`fixture idempotent`, and the whole test suite including `tests/test_fixture.py`.

The `fixture idempotent` section runs `scripts/make_fixture_its_saxy.py`, so it is what
first writes `fixtures/its-saxy/` — build executors have no bash and could not. It runs
before the test section for exactly that reason.

No `expected-red:` and no `defer:`: a red section here is a real failure.
