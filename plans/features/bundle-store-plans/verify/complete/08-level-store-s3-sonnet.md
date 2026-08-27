# Level 2 level-verify — the `s3://` backend

Feature `bundle-store-plans` (level-verify for sentinel `08-gate.md`). Runs only when
level 2's gate is red.

Must be green at this level: `install`, `lint`, `fixture idempotent`,
`wheel contains fixture`, `tests` — including `tests/test_store_s3.py`.
`tests/test_store_fixture.py` is expected-red here: its `seed_its_saxy_store` case
belongs to level 3 and is not yours to fix. Read `plans/gate-report.08.txt` first; do
not re-run install, lint or the suite before triaging it.

Contract rows this level owns, and may therefore change: `S3BundleStore`'s key layout
under a prefix, the `release.json`-last upload order, and the `s3` branch of
`open_store`. Everything level 1 owns — `BundleEntry`, the layout segments, the shared
helpers, `StoreError` vs `BundleError` — is fixed, and plan 09 is queued against it.
If a level-1 name looks wrong, that is an escalation, not an edit.
