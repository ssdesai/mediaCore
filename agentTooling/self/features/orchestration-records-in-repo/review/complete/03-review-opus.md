# 03 — review: orchestration-records-in-repo (round 3, merge of main)

Round 3 merges `origin/main` into the branch after round 2's clean verdict: `main` gained
`hook-role-hardening` (PR 140), which rewrote `hooks/orchestrator_role.py` and touched
`analysis/manifest.py`, `hooks/README.md` and `self/tests/README.md` — the four files that
conflicted. Hold the merged tree to every ruling in `NOTES.md` (1–22 and any round-3 ruling)
AND to `self/features/hook-role-hardening/`'s rulings and tests: neither feature's behaviour
may be lost in the resolution. "No findings" is a legitimate verdict.

## What the feature was supposed to do

Everything `review/complete/01-review-opus.md` and `review/complete/02-review-opus.md` name
under "What the feature was supposed to do", now on top of `hook-role-hardening`. In
particular the orchestrator-role rule must both (a) read records under `self/orchestrations/`
and, from a vendored copy only, the consuming repo's `plans/orchestrations/` (rulings 4, 16),
and (b) keep every role check `hook-role-hardening` added (role by shape and every fence, the
session-id check, the committed-record role, the orchestrator allowlist) — applied to records
in both roots.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`. Round 3's own work is the merge commit and the commits after
`review round 2`; read the merge's conflict resolutions (`git show --remerge-diff <merge>`)
closely.

## Contracts to hold it to

- Round 1's and round 2's contracts (their briefs → "Contracts to hold it to").
- `hook-role-hardening`'s tests all pass unchanged in intent, and any of them that reads only
  `self/orchestrations/` is extended (not weakened) where the role now spans both roots.
- One definition of each rule; mirrors asserted by tests; README entries true for the
  merged code.
- The gate report is green with nothing SKIPPED.

## Verdict
