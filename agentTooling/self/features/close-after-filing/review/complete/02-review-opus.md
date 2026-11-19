# 02 — review: close-after-filing, round 2

Round 2 of this feature. Round 1's review came back clean; its security audit escalated on
one blocking finding, B1 (`escalations/01-audit-opus.md`). Read that file first. "No
findings" is a legitimate verdict: say `Verdict: clean` when the diff does what is listed
and holds the contracts, and do not invent findings to fill a report.

## What the feature was supposed to do

Everything round 1's brief (`review/complete/01-review-opus.md`) lists still applies: the
close accepts, after a clean judged head, one coordinator commit `<slug>: backlog` whose
whole change is the layout's BACKLOG file left a regular file, refuses everything else
(naming that path in the refusal), keeps F1, and the docs agree.

This round's rework:

- B1: a commit adding a file named `self/BACKLOG.md<LF>` (a trailing newline in the path)
  passed the check, because the NUL-separated name list was compared after `$(…)` stripped
  trailing newlines. The fix must compare the name list exactly, in bash 3.2 (no
  `mapfile -d`).
- The `<slug>: review stamps` case had the same comparison; it is moved to the same helper,
  which also requires one parent and renames off for it. That must not refuse the stamps
  commit `run-review.sh` itself makes.
- Round 1's review note: K5 asserts the refusal names the allowed path.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff. Round 2's own change is `git diff <round 1's stamps commit>..HEAD`
(`git log --oneline origin/main..HEAD` names it).

## Contracts to hold it to

- `commit_changes_only <sha> <path>` in `feature-close.sh`: true only for a single-parent
  commit whose `--no-renames -z` diff against its parent is exactly `<path>` — no name with
  a trailing or embedded newline folds into it, no second name rides along. Both the
  `: review stamps` and `: backlog` cases use it; `: backlog` adds the `100644` mode check.
- Magic values are named constants (`SINGLE_PARENT_WORDS`, `NAME_LIST_SENTINEL`).
- `self/tests/close-backlog.sh` K11 (`self/BACKLOG.md<LF>`, an executable
  `self/BACKLOG.md<LF><LF>`) and K12 (`timing.jsonl<LF>` under `S: review stamps`) are
  refused; K1/K2/K9 still pass; the gate records the test (round 1 added the `record` line).
- Every other test that drives a close through a real `run-review.sh` stamps commit
  (`feature-lifecycle.sh`, `security-audit.sh`) still passes — the gate shows it.
- `self/features/close-after-filing/NOTES.md` records the round-2 ruling; `self/tests/README.md`
  lists K11/K12.

## Verdict

First line `Verdict: clean` or `Verdict: escalated`. Escalate only on a defect the diff
introduces or a listed contract it fails; list anything else as a non-blocking note.
