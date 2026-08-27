# Level 1 level-verify — the store seam and the `file://` backend

Feature `bundle-store-plans` (level-verify for sentinel `05-gate.md`). Runs only when
level 1's gate is red.

Must be green at this level: `install`, `lint`, `fixture idempotent`,
`wheel contains fixture`, `tests`. `tests/test_store_fixture.py` and
`tests/test_store_s3.py` are expected-red here — they belong to levels 3 and 2, and
neither is yours to fix. Read `plans/gate-report.05.txt` first; do not re-run install,
lint or the suite before triaging it.

Contract rows this level owns, and may therefore change: `BundleEntry`'s five fields
and its frozen/`extra="forbid"` config, the
`<root>/<record ULID>/<exported_at>/<slug>/` layout, `record_id` and `exported_at`
coming from the `vinylcat` provenance entry, `bundle_slug`, the shared helpers plan 07
reuses (`S3_LIST_PAGE_SIZE`, `_import_boto3`, the raw-payload parse, the
latest-per-record selection), `open` accepting an entry or its `uri`, and the
`mediacore[s3]` / dev extras in `pyproject.toml`. Fix the tree to those contracts;
plans 06, 07 and 09 are queued against these names, so renaming or re-typing any of
them makes them wrong.
