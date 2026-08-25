@agentTooling/CONVENTIONS.md

# Project-specific instructions

This repo is the **contract package** between vinylCatalogue (source) and
humanNetworkMap / musicMap (consumers). `INTEGRATION.md` is the cross-repo design and
decisions log — read it before changing anything under `src/`. It is also the
management home for that integration: work in the other repos is briefed from here.

## Concrete examples for the README rules

**Rule 1 — field lists for cross-module data shapes.** Every model in
`src/mediacore/release.py` is consumed by three other repos, so its README entry lists
every field:
> - `release.py` — `Release { schema_version, refs, provenance, title, artists, labels, year, released, country, medium, format, genres, styles, tracks, credits, notes, tags, media, audio, links }` — the on-disk `release.json` shape.

**Rule 2 — naming non-obvious cross-layer dependencies.**
> - `normalize.py` — `normalize_text` must stay byte-for-byte equivalent to `vinylcat.normalize.normalize_text` in the vinylCatalogue repo; `tests/test_normalize.py` pins the samples both must agree on.

## Commands

- Install: `python -m venv .venv && .venv/bin/pip install -e ".[dev]"`
- Tests: `.venv/bin/python -m pytest -q`
- Lint: `.venv/bin/python -m ruff check src tests`
- Regenerate the fixture: `.venv/bin/python scripts/make_fixture_its_saxy.py`

## Branch naming

Bare camelCase, no prefix and no slash (`releaseContract`, `fixtureItsSaxy`). Manifests
copy the name from `git branch --show-current`.

## Delegated plan execution

`agentTooling/AGENT_PLANS.md` governs plan authoring. Before writing plans, read
`plans/PROJECT_FACTS.md`.
