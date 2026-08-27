# mediaCore

The shared contract between the owner's recorded-media repos: a neutral `Release`
schema, refs (evidence recorded by external sources, never identity), the shared
name-normalisation fold, a bundle reader/writer, a URI-addressed bundle store, and one
real-world test fixture. Python package `mediacore`, no app code, no database.

`INTEGRATION.md` is the cross-repo design — who produces a release bundle
(vinylCatalogue), who consumes it (humanNetworkMap, musicMap), what the contract is, and
every decision taken along the way. Start there.

## Contents

| Path | What it is |
|---|---|
| `INTEGRATION.md` | Cross-repo design and decisions log. The brief every implementing agent works from. |
| `CLAUDE.md` | Imports the shared conventions from `agentTooling/`, plus this repo's Rule 1/2 examples and commands. |
| `agentTooling/` | Vendored via `git subtree` — shared Claude Code conventions and the delegated-plan harness. Not edited here. |
| `plans/` | This repo's plan corpus (`features/<slug>/`), `PROJECT_FACTS.md`, the mechanical gate and PR hook. |
| `src/mediacore/` | The package — see its README. |
| `tests/` | pytest suite mirroring `src/`. |
| `fixtures/its-saxy/` | The contract fixture: a complete release bundle with real metadata and placeholder media. |
| `scripts/` | `make_fixture_its_saxy.py` — regenerates the fixture deterministically. |

## Consuming

```
mediacore @ git+https://github.com/ssdesai/mediaCore.git@v0.1.0
```

Pin a tag, never a branch. Version policy is in `INTEGRATION.md` §12.

The bundle store arrived in `v0.2.0`, and its `s3://` backend needs the optional extra:
`mediacore[s3] @ git+https://github.com/ssdesai/mediaCore.git@v0.2.0`. `v0.1.0` has
neither the module nor the extra.

## Working in this repo

Read `CLAUDE.md` first. Before authoring delegated plans, read
`agentTooling/AGENT_PLANS.md` and `plans/PROJECT_FACTS.md`.
