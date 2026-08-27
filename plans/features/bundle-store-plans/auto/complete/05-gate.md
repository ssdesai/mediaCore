# Level 1 sentinel — the store seam and the `file://` backend

The gate runs here, labelled `05`, over `pyproject.toml`, `src/mediacore/store.py`,
`src/mediacore/__init__.py` and the two unit-test files (plans 02–04). Every gate
section must be green, including `fixture idempotent` and `wheel contains fixture`,
which this level does not change and therefore must not break.

What this level does **not** own:

- `tests/test_store_fixture.py` — the batch's acceptance test. It needs
  `seed_its_saxy_store`, which is level 3's deliverable (plan 09).
- `tests/test_store_s3.py` — the `s3://` backend is level 2 (plans 06–07). The file
  does not exist yet; the glob is harmless until it does, and correct once it does.

expected-red: tests/test_store_fixture.py tests/test_store_s3.py
