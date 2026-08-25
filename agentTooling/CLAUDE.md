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

This file exists because a `--self` executor's cwd is this directory, not the consuming
repo root — without it, such an executor would never load `CONVENTIONS.md` at all. In a
consuming repo that root `CLAUDE.md` already imports `@agentTooling/CONVENTIONS.md`, so
editing inside this directory loads the conventions twice. That is the accepted cost;
see the `agenttooling-self-host` manifest's exclusions.

### Commands

- Mechanical gate: `./self/gate.sh` (syntax checks; there is no test suite)
- Build a self feature: `./run-plans.sh --self <slug>`, then `./run-verify.sh --self <slug>`,
  then `./run-review.sh --self <slug>` (or `./run-batch.sh --self <slug>` for all three)
- Cost report: `python3 analysis/report.py --self <slug>`
