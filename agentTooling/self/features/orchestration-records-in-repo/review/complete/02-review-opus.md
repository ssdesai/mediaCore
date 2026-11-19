# 02 — review: orchestration-records-in-repo (round 2)

Re-review after the rework of round 1's escalation
(`self/features/orchestration-records-in-repo/escalations/01-review-opus.md`). Hold the diff
to `NOTES.md` → "Rulings" 1–7, "Rulings made in the build" 8–13, and "Round 2 rulings"
14–17 (the coordinator's, written before the rework). "No findings" is a legitimate
verdict.

## What the feature was supposed to do

Everything round 1's brief (`review/complete/01-review-opus.md` → "What the feature was
supposed to do") names, plus round 2:

- Only a **stranded** legacy record (vendored `agentTooling/self/orchestrations/<slug>`
  whose last fence lists a feature whose `repo` is the consuming repo, case-insensitively)
  gets the `git mv` advice, from every record tool. agentTooling's own shipped records
  (`readme-structure`, `agenttooling-roles`, `rehearsal-prep`, `ablation-wave`,
  `program-ab`, or any record with no consumer feature) never do; the start is not refused
  for such a name; the other tools say the record is agentTooling's own and name `--self`.
- In agentTooling's own checkout (the tooling directory is a checkout root), every record
  tool run without `--self` refuses before writing anything, naming `--self`; nothing is
  written outside the checkout.
- `hooks/orchestrator_role.py` reads the parent's `plans/orchestrations/` only from a
  vendored copy.
- `analysis/coordinator_check.py`'s advisory names `--self` when printed for a `--self`
  start.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff. Round 2's own changes are the commits after `review round 1`.

## Contracts to hold it to

- Round 1's contracts (`review/complete/01-review-opus.md` → "Contracts to hold it to").
- The stranded classifier and the standalone refusal are each defined once in
  `analysis/roots.py` (named constants), mirrored in the shell with a test asserting the
  mirror.
- Tests in `self/tests/orchestration-records-in-repo.sh` (or a sibling recorded by
  `self/gate.sh`) cover: a consumer-shaped tree where a vendored shipped record (no
  consumer feature) named like the new slug draws no `git mv` and does not block the start;
  a stranded record does draw it; a no-`--self` start, capture, manifest and report in a
  standalone agentTooling checkout refuse and write nothing (in particular nothing in the
  checkout's parent); the hook ignores a parent `plans/orchestrations/` from a standalone
  checkout; the advisory's `--self`.
- README entries amended for every folder touched; `check-readme-index.py` green.

## Verdict
