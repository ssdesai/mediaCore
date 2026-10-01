# 01 — review: pull-agenttooling-pr73

## What the feature was supposed to do

Propagate agentTooling `main` at `bd603c3` (PR #73; the range since this repo's last
pull at `c9f073b9`, PR #63, carries #65 backlog-rulings, #66 manifest-pin-subagent, #67 start-takeover, #68 hook-pipe-redirect, #69
self-settings-untracked, #70 rates-tier-check, #71 propagation-as-feature, #72
runner-sandbox, #73 sandbox-consumer-reads) into the vendored `agentTooling/` subtree
by `agentTooling/update.sh`, and commit what the pulled `sync-plans.sh` wrote. No
repo code changes.

## The diff

The branch was cut from `main`; judge `git diff main...HEAD --stat`, then the full diff
of everything outside `agentTooling/`. Inside `agentTooling/` the subtree commit's
message names the squashed range; confirm it ends at `bd603c3` and do not re-review
agentTooling's own code.

## Contracts to hold it to

- The subtree split is `bd603c3`; `agentTooling/sync-plans.sh --check` is clean.
- Outside `agentTooling/`, the only changes are what the sync writes: the root
  `.claude/settings.json` (now with a `sandbox` block whose `enabled` is **false**, three
  `denyRead` paths, seven `allowedDomains`, and the Bash deny / Edit deny / `hooks/` ask
  rules intact), the deletion of `agentTooling/.claude/settings.json`, any `plans/*.sh`
  template update the sync's `DRIFT` lines asked to hand-merge (the repo's own additions
  kept), and the feature's manifest. Anything else is an escalation.
- The manifest prose names the PR and the split sha; the fenced block is untouched.
- The gate is green (`plans/gate-report.txt`); a red check that predates the pull is
  named as such in the implementer's report, not hidden.

Fix local findings in the pass; escalate structural ones. "No findings" is a legitimate
verdict.

## Verdict

First line of `plans/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
