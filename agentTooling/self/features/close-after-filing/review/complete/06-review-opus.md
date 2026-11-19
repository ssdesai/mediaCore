# 06 — review: close-after-filing, round 6

Round 6 of this feature. Round 5 came back `Verdict: clean`
(`review/complete/05-review-opus.md`, `review-report.md`, `audit-report.md`). Since then the
sibling feature `consumer-record-guard` (PR #156) merged into `main`, and this round's only
change is the merge of `origin/main` into this branch: commit
`close-after-filing: merge main (consumer-record-guard)`. Judge the merge resolution. "No
findings" is a legitimate verdict: say `Verdict: clean` when both features are intact and do
not invent findings to fill a report.

## What the feature was supposed to do

Everything rounds 1–5's briefs list (`review/complete/0{1,2,3,4,5}-review-opus.md`) still
applies: the close accepts, after a clean judged head, one coordinator commit `<slug>: backlog`
whose whole change is the layout's BACKLOG file left a regular file, refuses everything else
(naming that path), runs with grafts and replace objects off, keeps F1, and the docs agree.

`consumer-record-guard` (read `self/features/consumer-record-guard/NOTES.md` and its README)
refuses every record writer's `--self` write from a copy vendored in a consuming repo
(`roots.py`'s `record_write_refusal`, `roots.py self-write <slug>`), held by
`self/tests/consumer-record-guard.sh` C1–C6.

## The merge

One textual conflict, `README.md`, on adjacent table rows: main changed the
`orchestration-start.sh` and `orchestration-capture.sh` rows (the vendored-copy `--self`
refusal), this feature changed the `feature-close.sh` row (the `<slug>: backlog` allowance).
The resolution took main's two rows and this branch's row. `LIFECYCLE.md`, `self/gate.sh`,
`self/tests/README.md` and `self/PROJECT_FACTS.md` merged without conflict.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat` and the full diff — what this feature adds over the
merged `main`. Then the merge itself: `git show --cc HEAD~N` for the merge commit
(`git log --oneline --merges origin/main..HEAD`), and `git diff <merge>^1 <merge>` for what
main brought in.

## Contracts to hold it to

- Nothing from either side was dropped: every hunk of `git diff <merge-base> origin/main` and of
  `git diff <merge-base> <merge>^1` is present in the merge's tree, `README.md` included.
- `self/gate.sh` registers both `self/tests/close-backlog.sh` (and this feature's other tests)
  and `self/tests/consumer-record-guard.sh`, each in `shell_scripts` and as a `record` line;
  the gate is green on the merged head.
- `feature-close.sh` is this branch's version (main did not touch it); the
  `<slug>: backlog` allowance, K1–K16, L1, L2 and D1 still pass.
- The docs agree with each other across both features: `README.md`, `LIFECYCLE.md`,
  `self/tests/README.md`, `self/PROJECT_FACTS.md` and `analysis/README.md` describe both, with
  no sentence one side wrote contradicted by the other's.
- No check was weakened or dropped in the resolution.

## Verdict

First line `Verdict: clean` or `Verdict: escalated`. Escalate only on a defect the merge
introduces or a listed contract it fails; list anything else as a non-blocking note.
