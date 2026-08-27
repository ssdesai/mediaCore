# scripts

Standalone maintenance scripts. Each one is run by hand or by `plans/gate.sh`, never
imported. They require `mediacore` to be installed (`.venv/bin/python -m pip install -e
".[dev]"`).

- `make_fixture_its_saxy.py` — regenerates the IT'S SAXY contract fixture
  (`INTEGRATION.md` §11) into `fixtures/its-saxy/`, or into a destination given as the
  first argument. Deterministic by construction: the metadata is a set of module
  constants, the placeholder PNGs and WAVs are synthesized from constants with stdlib
  `struct`/`zlib` only, and `EXPORTED_AT` is fixed — no clock, no randomness, no
  network. That matters because every filename in the bundle is the sha256 of its own
  bytes, so a non-deterministic generator would rewrite the whole fixture on every run.
  `plans/gate.sh`'s "fixture idempotent" section runs it twice and requires both trees
  to be byte-identical and `git status --porcelain fixtures/` to be clean. It writes
  through `mediacore.write_bundle`, so the fixture is also a live test of the writer.
- `seed_bundle_store.py` — seeds the committed IT'S SAXY bundle into a bundle store
  (`INTEGRATION.md` §5.1 "Fixture") via `mediacore.seed_its_saxy_store`. Takes the
  store URI (`file://` or `s3://`) as its only argument and refuses to guess one — a
  missing argument prints a usage message and exits non-zero. Idempotent, so it is safe
  to rerun; prints the seeded entry's `uri` on success. Run by hand when setting up a
  dev stack for WP7b/7c/7d, never by `plans/gate.sh`, which never writes outside the
  checkout.
