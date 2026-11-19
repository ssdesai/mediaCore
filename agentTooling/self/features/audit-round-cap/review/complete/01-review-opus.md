# 01 — review: audit-round-cap

A doc-only feature: two process rules, no code. Review the diff against the spec below, never against the builder's report. "No findings" is a legitimate verdict.

## What the feature was supposed to do

1. `LIFECYCLE.md` → "The security audit" states a cap: after 2 escalated audit rounds the coordinator stops and the owner rules which blocking findings move to the BACKLOG (`self/BACKLOG.md`, or `plans/BACKLOG.md` in a consuming repo); the feature then continues or closes per that ruling. It stays consistent with the existing rule that non-blocking findings are filed in a `<slug>: backlog` commit after the clean verdict. The BACKLOG entry "The security audit has no round cap." is removed.
2. A coordinator brief for a fix under `hooks/` names one gap; new findings a round turns up go to the BACKLOG, not into the open feature. It is stated where a coordinator writing a brief reads it (`ORCHESTRATION.md` → "Rules"), cross-referenced from `LIFECYCLE.md` if useful. The BACKLOG entry "Hook features grow past one gap." is removed.

Excluded: any change to scripts, hooks, templates, `.claude/`, or other BACKLOG entries; any other feature's folder.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Only `LIFECYCLE.md`, `ORCHESTRATION.md`, `self/BACKLOG.md` and this feature's folder change; in `self/BACKLOG.md` exactly the two named entries are removed.
- The cap's number (2), who stops (the coordinator), who rules (the owner), where blocking findings go, and that the feature continues or closes per the ruling are all stated, without contradicting the blocking/non-blocking rule or the `S: backlog` commit rule.
- The one-gap rule is stated as a rule a brief writer can follow, and names the BACKLOG as where new findings go.
- Cross-references name sections that exist. Any README that describes these files stays true.
- The gate (`./self/gate.sh`) passes.

## Verdict
