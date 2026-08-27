# Level 2 sentinel — the `s3://` backend

The gate runs here, labelled `08`, over `src/mediacore/store.py`'s new `S3BundleStore`
and `tests/test_store_s3.py` (plans 06–07), on top of everything level 1 owns. Every
gate section must be green, `tests/test_store_s3.py` included: `moto` reached the dev
extra at level 1, so a failure here is a real one and not a missing dependency.

What this level does **not** own:

- `tests/test_store_fixture.py` — the batch's acceptance test. Its store cases pass by
  now, but it also calls `seed_its_saxy_store`, which plan 09 writes at level 3. Do not
  make it green by weakening it.

expected-red: tests/test_store_fixture.py
