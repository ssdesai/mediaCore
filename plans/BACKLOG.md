# Backlog

Escalations and decisions left open by finished batches — one entry per item, phrased as
the assertion that would catch it, with the batch that raised it. Remove an entry in the
batch that closes it.

- **A schema-1 bundle re-written by 0.3.0 keeps its `schema_version: 1` label while
  carrying `artist`, so §12's promised refusal message never fires.** `read_bundle`
  (`src/mediacore/bundle.py:90`) preserves whatever `schema_version` the file carried,
  and `_populate` (`bundle.py:181`) writes `release.model_dump(mode="json")` whole — it
  never stamps `SCHEMA_VERSION`. So `write_bundle(read_bundle(old_bundle), dest, files)`
  — and `BundleStore.put` with a `Release` that came from `open`, `store.py:347` and
  `store.py:453` — emits a `release.json` labelled `schema_version` 1 whose tracks carry
  `"artist": null`. On a 0.2.0 reader that file fails `extra="forbid"` and raises
  `BundleError("invalid release payload in …")`, not the "upgrade mediacore to read it"
  message `INTEGRATION.md` §12 (2026-09-06 paragraph) promises consumers will get; in a
  store, `BundleEntry.schema_version` reports 1 for a payload only a 0.3.0 reader can
  parse, which is exactly what §5.1's "`list` surfaces a too-new `schema_version`
  instead of refusing it" contract rests on. Not a local fix: whether re-writing an old
  bundle silently *upgrades* its label (stamp `SCHEMA_VERSION` in `_populate`) or the
  reader refuses to hand back a stale-versioned model is a §12 versioning decision, and
  whichever way it goes belongs in §13 beside the 2026-09-06 entry. Assertion once
  decided: read `tests/assets/its-saxy-schema-1/` with `verify=False`, `write_bundle` it
  to a tmp path with no media, and assert the written `release.json`'s `schema_version`
  agrees with the shape it actually contains (`2` if the writer stamps; unreachable if
  the reader refuses).
  Raised by `track-artist-field`.

- **`__version__` and the packaging version are mirrored by hand and nothing asserts they
  agree.** `src/mediacore/__init__.py:8` and `pyproject.toml`'s `version` were both moved
  to `0.3.0` by this batch, correctly, but a future bump that edits one and not the other
  is green everywhere: no test reads either value, and consumers pin a git tag whose name
  is a third hand-kept copy (`README.md`'s `@v0.3.0` lines). Assertion:
  `importlib.metadata.version("mediacore") == mediacore.__version__` in
  `tests/test_release.py` (or a new `tests/test_package.py`) — the gate installs the
  package with `pip install -e .`, so the metadata side is real.
  Raised by `track-artist-field`.
