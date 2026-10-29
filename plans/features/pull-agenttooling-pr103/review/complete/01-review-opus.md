# 01 — review: pull-agenttooling-pr103

## What the feature was supposed to do

Propagate agentTooling main (PR #102 hand-start-friction: `cloud-setup.sh` template
version 3 with `setup_in_background` and `--wait`, feature-start waiting for cloud setup;
PR #103 fable-plan-model: `fable` accepted as a plan/review model suffix) into the
vendored `agentTooling/` subtree via `update.sh`, and adopt `plans/cloud-setup.sh`
version 3 by hand per `agentTooling/README.md` → "Adopting cloud-setup.sh version 3":
template header and everything from `REPO_DIR=` down to `REPO-SPECIFIC`, the template-version
line set to 3, every repo-specific line kept. This repo backgrounds nothing (the venv
install is synchronous), so nothing is routed through `setup_in_background`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff. The `agentTooling/` subtree content is upstream's and is not to be
reviewed line by line; review `plans/cloud-setup.sh`, `plans/README.md` (generated, synced)
and the merge shape.

## Contracts to hold it to

- `plans/cloud-setup.sh` above `REPO-SPECIFIC` matches `agentTooling/templates/plans/cloud-setup.sh`
  byte for byte; the REPO-SPECIFIC venv block is preserved unchanged from before.
- `./agentTooling/sync-plans.sh --check` is all in-sync; `./agentTooling/update.sh --check`
  says intact.
- No hand edits inside `agentTooling/`.
- "No findings" is a legitimate verdict.

## Verdict

First line of `plans/review-report.md` is `Verdict: clean` or `Verdict: escalated`.
