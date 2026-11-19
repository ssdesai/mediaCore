# 05 — review: close-after-filing, round 5

Round 5 of this feature. Round 4 escalated on its security audit's B06
(`escalations/04-audit-opus.md`, `escalations/04-review-opus.md` → E1). Read those first. "No
findings" is a legitimate verdict: say `Verdict: clean` when the diff does what is listed and
holds the contracts, and do not invent findings to fill a report.

## What the feature was supposed to do

Everything rounds 1–4's briefs list (`review/complete/0{1,2,3,4}-review-opus.md`) still applies:
the close accepts, after a clean judged head, one coordinator commit `<slug>: backlog` whose whole
change is the layout's BACKLOG file left a regular file, refuses everything else (naming that
path), keeps F1, and the docs agree.

This round's rework:

- B06: a cyclic `.git/info/grafts` gave an unreviewed `<slug>: backlog` commit a fabricated parent
  differing from it in the BACKLOG alone (B08, the same under `<slug>: review stamps`, was
  pre-existing). `feature-close.sh` now exports `GIT_GRAFT_FILE=/dev/null` (`GRAFTS_OFF_FILE`)
  beside `GIT_NO_REPLACE_OBJECTS=1`, before its first git call.
- The ruling on shallow clones (tolerated, with the reason) and the corrected round-4 claim are in
  NOTES.md → "Round 5".

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`. Round 5's own change is the commit after round 4's
`close-after-filing: review stamps` (`git log --oneline origin/main..HEAD`).

## Contracts to hold it to

- Both exports precede every git call in `feature-close.sh` (including sourcing
  `plan-runner-roots.sh`), the value a named constant, the comment saying why.
- `self/tests/close-backlog.sh` K16a/b: each first shows the graft live (plain git, grafts on,
  lists only the allowed file), then the close refuses; K1/K2/K9 still pass; the gate is green.
- NOTES.md's shallow-clone ruling holds against the code: a parentless commit fails
  `commit_changes_only`; nothing else in the close assumes full history in a way a shallow
  boundary turns into an accept.
- `self/tests/README.md` lists K16.

## Verdict

First line `Verdict: clean` or `Verdict: escalated`. Escalate only on a defect the diff
introduces or a listed contract it fails; list anything else as a non-blocking note.
