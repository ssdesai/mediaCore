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
