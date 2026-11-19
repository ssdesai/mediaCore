# 04 — review: close-after-filing, round 4

Round 4 of this feature. Round 3 escalated on its security audit's B3 (`escalations/03-audit-opus.md`
and `escalations/03-review-opus.md` → E1). Read those first. "No findings" is a legitimate
verdict: say `Verdict: clean` when the diff does what is listed and holds the contracts, and do
not invent findings to fill a report.

## What the feature was supposed to do

Everything rounds 1–3's briefs list (`review/complete/0{1,2,3}-review-opus.md`) still applies:
the close accepts, after a clean judged head, one coordinator commit `<slug>: backlog` whose whole
change is the layout's BACKLOG file left a regular file, refuses everything else (naming that
path), keeps F1, and the docs agree.

This round's rework:

- B3: a local `git replace <real> <fake>` made the close judge a stand-in BACKLOG-only commit
  while `git push` sent the real one (an unreviewed `hooks/policy.py` change); the same under
  `<slug>: review stamps` (A09) was pre-existing. `feature-close.sh` now exports
  `GIT_NO_REPLACE_OBJECTS=1` before its first git call. NOTES.md → "Round 4" rules why
  `run-review.sh` does not need it.
- Round 3's review note: L2 calls `audit_paths_in_range` directly to show its
  `--ignore-submodules=none`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`. Round 4's own change is the commit after round 3's
`close-after-filing: review stamps` (`git log --oneline origin/main..HEAD`).

## Contracts to hold it to

- `export GIT_NO_REPLACE_OBJECTS=1` precedes every git call in `feature-close.sh`, including
  the sourcing of `plan-runner-roots.sh` and `resolve_roots`; it is commented with why.
- `self/tests/close-backlog.sh` K15a/b (a replace-ref stand-in under each subject) and L2 pass;
  K1/K2/K9 still pass; the gate is green.
- NOTES.md's round-4 ruling on `run-review.sh` holds: whatever the review read, the close's own
  checks (the subject loop, F1, `audit_paths_touched`) run with replace refs off.
- `self/tests/README.md` lists K15 and L2.

## Verdict

First line `Verdict: clean` or `Verdict: escalated`. Escalate only on a defect the diff
introduces or a listed contract it fails; list anything else as a non-blocking note.
