# 03 — review: hook-role-hardening, round 3

Round 2's review came back clean; its security audit (`02-audit-opus`) escalated with two
bypasses (`escalations/02-audit-opus.md`). This round fixes them. Read the whole diff against
the spec in `01-review-opus.md`'s brief (it still holds), and check these two fixes in
particular. "No findings" is a legitimate verdict; say it outright if that is what you find
(AGENT_PLANS.md → "Review plans").

## What round 3 was supposed to do

1. **A1 — `git add` staged a planted nested repository** (through pathspec magic, a glob, `:/`
   or a parent directory), after which `git status` ran its `core.fsmonitor`. In
   `hooks/allow-repo-commands.sh`, `orchestrator_git_allowed` must admit `git add` only for
   arguments that are existing regular files (no symlink), with no leading `:` or `-`, no glob
   character and no `.git` component — the choice over walking directories is recorded in
   NOTES.md ("Lifecycle round 2").
2. **A2 — `date MMDDhhmm` set the clock.** `date` is admitted for an orchestrator only when
   every operand is a `+FORMAT`, the values of `-d`/`--date`, `-f`/`--file`,
   `-r`/`--reference` taken as theirs (`orchestrator_date_reads_only`).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. Round 3's own change is
`git diff <round 2's review-stamps commit>..HEAD`.

## Contracts to hold it to

- Everything listed under "Contracts to hold it to" in `01-review-opus.md`.
- `self/tests/hook-orchestrator-role.sh` H24 holds both fixes in both directions, H21's
  admitted set no longer holds the `git add` and `date MMDD…` rows the fix denies, and H20
  (non-orchestrator answers byte-identical to `origin/main`'s hook) still passes.
- `hooks/README.md`, `ORCHESTRATION.md` and NOTES.md describe both rules as built.

## Verdict

First line exactly `Verdict: clean` or `Verdict: escalated`, then the report.
