@CONVENTIONS.md

## What this directory is

The shared Claude Code conventions and delegated-plan harness, vendored into each repo
with `git subtree`. A change here ships to **every** consuming repo on its next
`subtree pull` — there is no such thing as a local-only fix in this directory.

## Self-hosted work

agentTooling builds its own features with its own harness. Its plan corpus is
`self/features/<slug>/`, drained by `./run-plans.sh --self` and friends; the facts a
plan author needs are in `self/PROJECT_FACTS.md`. See `RUNNER.md` → "Self-hosted mode"
for how `--self` differs from an ordinary run, and `AGENT_PLANS.md` for how to author
the plans themselves.

This file exists for the standalone checkout, where nothing else imports
`CONVENTIONS.md`. In a consuming repo the root `CLAUDE.md` already imports
`@agentTooling/CONVENTIONS.md`, and this file loads lazily the first time a session reads
anything under `agentTooling/`; Claude Code loads an import it has already loaded once
only, so that costs this file's own lines and nothing more (measured with an
`InstructionsLoaded` hook on Claude Code 2.1.314,
`self/features/claude-md-chain/NOTES.md`). A `--self` executor launched inside a vendored
copy also loads the consuming repo's root `CLAUDE.md`, as it does any ancestor's.

### Commands

- Mechanical gate: `./self/gate.sh` (syntax checks, the settings check and `self/tests/`)
- Build a self feature: `./run-plans.sh --self <slug>`, then `./run-verify.sh --self <slug>`,
  then `./run-review.sh --self <slug>` (or `./run-batch.sh --self <slug>` for all three)
- Cost report: `python3 analysis/report.py --self <slug>`
