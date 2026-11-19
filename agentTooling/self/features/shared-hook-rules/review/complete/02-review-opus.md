# 02 — review: shared-hook-rules (round 2, scoped)

Round 1's review (`review/complete/01-review-opus.md`, report at `review-report.md`) came back
clean and its security audit (`01-audit-opus`) clean too, but the review's own fix edited an
audit path after the audit had finished, so the runner stamped that audit stale. This round
re-judges only what changed since round 1's audit; the runner queues a fresh audit beside it.
"No findings" is a legitimate verdict.

## What the feature was supposed to do

Unchanged from round 1: a pure refactor giving every rule the PreToolUse hook shares with
`analysis/` and the shell one definition in `hooks/shared_rules.py`, with no behaviour change
(`self/features/shared-hook-rules/NOTES.md`, coordinator rulings 1–10; `01-review-opus.md` →
"What the feature was supposed to do"). Round 1 found it met every contract.

What changed since round 1's audit: one comment line in `orchestration-start.sh` (~line 296),
rewritten by the round-1 reviewer so that it names `hooks/shared_rules.py` as where
`LEDGER_NAME` is read from, instead of `hooks/orchestrator_role.py`. Nothing else.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

For this round, read first `git show <the 'shared-hook-rules: review round 1' commit> --
orchestration-start.sh` (find the commit with `git log --oneline origin/main..HEAD`), then
confirm with `git diff <that commit> HEAD -- hooks/ analysis/ '*.sh'` that nothing else in an
audit path has changed since.

## Contracts to hold it to

1. The round-1 edit is a comment only: no executable line of `orchestration-start.sh` changed,
   and `bash -n orchestration-start.sh` passes.
2. The comment is true: `orchestration-start.sh` does read `LEDGER_NAME` from
   `hooks/shared_rules.py` (through its one CLI read), and `hooks/orchestrator_role.py` binds
   its own `LEDGER_NAME` to the same value.
3. No other file under `hooks/`, `analysis/` or a top-level `*.sh` changed after round 1's
   audit finished, apart from this round's own review/stamp commits.
4. Round 1's contracts 1–8 (`01-review-opus.md`) still hold for the tree as it stands — a
   confirmation, not a re-review: `grep -rn 'MIRRORS\|MIRRORED' hooks/ analysis/ *.sh` is
   empty and `bash self/tests/shared-rules.sh` passes.

## Verdict
