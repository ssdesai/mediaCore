# Verify: the bundle store end to end

Feature `bundle-store-plans` (plan 11 of 12). WP7a of `INTEGRATION.md` §12: the
URI-addressed bundle store of §5.1 — `open_store(uri)` over `file://` and `s3://`,
`BundleEntry`, the versioned layout, and fixture seeding. `mediacore` goes to 0.2.0;
`schema_version` is unchanged. WP7b, 7c and 7d are blocked on the tag cut from this
branch.

Read `plans/gate-report.txt` first. It already ran install, `ruff check src tests`,
`fixture idempotent`, `wheel contains fixture` and `pytest -q`. **Do not re-run those.**
If a section failed, triage and fix it, then re-run only that section to confirm.

Then read `tests/test_store_fixture.py`, `tests/test_store_file.py` and
`tests/test_store_s3.py` before checking anything by hand — between them they cover
most of §5.1, and the point of this pass is what they leave uncovered.

## What must be true when you are done

1. The whole suite is green with zero skips.
2. `git status --porcelain fixtures/` is clean. A store is a runtime directory outside
   the checkout; nothing in this batch may write into `fixtures/`.

## Checks worth a model's time

- **`boto3` is genuinely optional.** The suite always has it, so no test can prove
  this. Build one scratch venv outside the repo, `pip install .` (no extras) into it,
  and confirm two things with one-liners: `from mediacore import open_store, Release`
  imports cleanly, and `open_store("s3://b/p")` raises `StoreError` whose message names
  `mediacore[s3]`. This is the packaging claim §5.1 makes and the one thing an
  installed consumer hits first. Delete the scratch venv afterwards. Do **not** touch
  the repo's own `.venv`.
- **`mediacore` takes no keys.** Grep `src/` for `aws_access_key`, `aws_secret`,
  `session_token`, `endpoint_url`, `region_name`, `profile_name`, `AWS_` and judge every
  hit: the client must be built from the ambient chain with no credential argument of
  its own. A test-only environment variable in `tests/conftest.py` is fine and is where
  it belongs.
- **Nothing deletes.** Grep `src/mediacore/store.py` for `unlink`, `rmtree`, `rmdir`,
  `remove`, `delete_object`, `delete_objects`, `replace`. §5.1: "Nothing in `mediacore`
  overwrites or deletes an entry." A hit inside a `tempfile.TemporaryDirectory` used
  for staging is fine; anything addressing the store is a defect. Check the same for
  `put_object` and `copyfile` overwriting an existing entry's key or path.
- **The two backends really do behave the same.** `tests/test_store_fixture.py`
  parametrizes the happy path over both. Read `FileBundleStore` and `S3BundleStore`
  side by side and name any behaviour that differs beyond "keys instead of paths" —
  ordering, what `list` skips, which exception a missing entry raises, whether
  `verify=False` means the same thing. A difference no test covers is the highest-value
  finding this pass can produce; write the assertion rather than only the observation.
- **The version moved as §12 says.** `pyproject.toml` is `0.2.0`,
  `mediacore.__version__` agrees (there is a test), and `SCHEMA_VERSION` is still `1`.
  A `schema_version` bump here would be wrong: this adds a module, not a field.
- **The README field lists match the code.** `src/mediacore/README.md`'s `store.py`
  entry lists `BundleEntry`'s fields and states the `StoreError` / `BundleError` split
  (CONVENTIONS.md Rule 1 and 2). Compare it to `src/mediacore/store.py`. Three other
  repos will read that entry as the contract.
- **`plans/PROJECT_FACTS.md`** describes the store accurately now that it exists.
- **§5.1, bullet by bullet, against the code**, for anything the three test files do
  not already assert. The bullets most likely to have slipped: `list` returning the
  latest per record; entry fields read from `release.json` and never from the key;
  `list` listing an entry whose `schema_version` is too new while `open` refuses it.

## Latitude

Fix local defects directly — a wrong assertion, a drifted README line, a missing
constant, an import ruff reorders, a message that does not name what it should.
Anything needing a new function, a changed signature, or a decision about §5.1 is a
finding for the review pass or the next batch; write it down rather than doing it here.

Do not tag a version, commit, or push — the review pass and `plans/pr.sh` own that. Do
not seed a store anywhere inside the repo.
