# 02 — review: hook-role-hardening, round 2

Round 1's review and its security audit both came back escalated, on the same two bypasses
(`escalations/01-audit-opus.md`, `escalations/01-review-opus.md`). This round fixes them.
Read the whole diff against the spec in `01-review-opus.md`'s brief (it still holds), and
check these two fixes in particular. "No findings" is a legitimate verdict; say it outright
if that is what you find (AGENT_PLANS.md → "Review plans").

## What round 2 was supposed to do

1. **B1 — `uniq - OUT` writes a file past the orchestrator allowlist.** In
   `hooks/allow-repo-commands.sh`, `orchestrator_operands` must count the bare `-` (stdin)
   as an operand, so every `uniq … - OUT` is denied for an orchestrator, while
   `echo '#!/bin/sh' | uniq - -hook` (one operand) stays admitted.
2. **B2 — the audit trigger misses what the allowlist executes.** `AUDIT_TOOLING_PATHS` in
   `plan-runner-roots.sh` must cover every file the orchestrator allowlist executes and
   everything those import. The decision taken: `analysis/` whole plus
   `orchestration-capture.sh` (NOTES.md, "Lifecycle round 1"). `LIFECYCLE.md` → "The
   security audit" and `hooks/README.md` list the same paths.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. Round 2's own change is
`git diff <round 1's review-stamps commit>..HEAD`.

## Contracts to hold it to

- Everything listed under "Contracts to hold it to" in `01-review-opus.md`.
- `self/tests/hook-orchestrator-role.sh`: the four `uniq - out` rows are in `ROUND3_ROWS`
  and not in `ROUND3_ADMITTED`; H20 (non-orchestrator answers byte-identical to
  `origin/main`'s hook) still passes.
- `self/tests/security-audit.sh` F6 names `orchestration-capture.sh` and an `analysis/`
  import; R3's non-hook fixture touches no audit path.
- NOTES.md records both fixes and the B2 decision.

## Verdict

First line exactly `Verdict: clean` or `Verdict: escalated`, then the report.
