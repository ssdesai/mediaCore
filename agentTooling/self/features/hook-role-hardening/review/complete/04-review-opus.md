# 04 — review: hook-role-hardening, round 4

Round 3's review came back clean; its security audit (`03-audit-opus`) escalated with one
bypass, C1 (`escalations/03-audit-opus.md`). This round fixes it. Read the whole diff against
the spec in `01-review-opus.md`'s brief (it still holds), and check the fix in particular.
"No findings" is a legitimate verdict; say it outright if that is what you find
(AGENT_PLANS.md → "Review plans").

## What round 4 was supposed to do

**C1 — `date -Id MMDDhhmm` set the clock.** GNU date's `-I` takes the rest of its word as an
optional attached argument, so `-Id` is `--iso-8601=date`, not `-d`. In
`hooks/allow-repo-commands.sh`, `orchestrator_date_reads_only` must stop its short-cluster
scan at `I` (`ORCHESTRATOR_DATE_OPTIONAL_ATTACHED`), so the next word is checked as an operand
and refused unless it is a `+FORMAT`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. Round 4's own change is
`git diff <round 3's review-stamps commit>..HEAD`.

## Contracts to hold it to

- Everything listed under "Contracts to hold it to" in `01-review-opus.md`.
- `self/tests/hook-orchestrator-role.sh` H24 denies `date -Id 010100002020`, `-uId`, `-uuId`
  and admits `date -Id` and `date -uId +%s`; H20 still passes.
- NOTES.md records the fix ("Lifecycle round 3").

## Verdict

First line exactly `Verdict: clean` or `Verdict: escalated`, then the report.
