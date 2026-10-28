# 01 — review: pull-agenttooling-pr101

## What the feature was supposed to do

Propagate agentTooling PR #101 (detached-at-branch-tip-attach) into this repo's vendored
`agentTooling/` subtree via `./agentTooling/update.sh`: a subtree pull of upstream
`60534226efb80b3b40ff01344b044156e297e8cf`, preceded by a re-anchor of the broken trailer
chain (a no-change `ours` merge), then `sync-plans.sh`. Nothing outside `agentTooling/`
and this feature's own directory (`plans/features/pull-agenttooling-pr101/`) should
change. "No findings" is a legitimate verdict.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- The prefix diff is the upstream range and nothing else: no hand edit under
  `agentTooling/`; the changed files are the 23 `update.sh` listed (new `attach-branch.sh`,
  hook, `session-start.sh`, `plan-runner-roots.sh`, docs, self tests and the
  `detached-at-branch-tip-attach` self feature).
- `./agentTooling/sync-plans.sh --check` is all `in-sync`, so no repo-owned `plans/` file
  needed adopting and none was edited; `.claude/settings.json` is unchanged or only
  gains wiring the generator owns.
- `./agentTooling/update.sh --check` says the chain is `intact`.
- `./plans/gate.sh` is green (install, lint, fixture idempotent, wheel, tests).
- The repo's README rules: root and `agentTooling/` README entries are vendored, not
  repo-owned, so no mediaCore README should need an edit for a vendored-only change.

## Verdict

First line of `plans/review-report.md` is `Verdict: clean` or `Verdict: escalated`.
