# Level 3 level-verify — fixture seeding

Feature `bundle-store-plans` (level-verify for sentinel `10-gate.md`). Runs only when
level 3's gate is red.

Everything must be green at this level: `install`, `lint`, `fixture idempotent`,
`wheel contains fixture`, and the whole suite including
`tests/test_store_fixture.py`, the batch's acceptance test. Nothing is expected-red and
nothing is deferred. Read `plans/gate-report.10.txt` first; do not re-run install, lint
or the suite before triaging it.

Contract rows this level owns, and may therefore change: `seed_its_saxy_store` and its
idempotence, and `scripts/seed_bundle_store.py`. `mediacore.store`'s surface is fixed
by levels 1 and 2 — fix the seeding to the store, never the store to the seeding.

If `fixture idempotent` is the red section, suspect seeding that wrote into the
checkout: nothing may change under `fixtures/`.
