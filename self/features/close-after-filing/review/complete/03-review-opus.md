# 03 — review: close-after-filing, round 3

Round 3 of this feature. Round 2's review escalated on its security audit's B2 (E1 in
`review-report.md`; `audit-report.md` C18/S1/S2/S4, C24). Read those first. "No findings" is a
legitimate verdict: say `Verdict: clean` when the diff does what is listed and holds the
contracts, and do not invent findings to fill a report.

## What the feature was supposed to do

Everything rounds 1 and 2's briefs list (`review/complete/01-review-opus.md`,
`02-review-opus.md`) still applies: the close accepts, after a clean judged head, one
coordinator commit `<slug>: backlog` whose whole change is the layout's BACKLOG file left a
regular file, refuses everything else (naming that path), keeps F1, and the docs agree.

This round's rework:

- B2: a gitlink beside the BACKLOG, hidden from the porcelain `git diff` by a worktree
  `.gitmodules` with `ignore = all` (kept out of the stray check by info/exclude) or by
  `diff.ignoreSubmodules=all`, passed `commit_changes_only`. Every name list the close judges a
  commit by now reads `--ignore-submodules=none`: `commit_changes_only`, the cost/PR case's
  `git show`, and `audit_paths_in_range` (`plan-runner-roots.sh`, so F1 sees a gitlink at an
  audit path).
- C24 (non-blocking, pre-existing): the `100644` check moved into `commit_changes_only`, so a
  stamps commit may not make `timing.jsonl` executable either.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`. Round 3's own change is the commit after round 2's
`close-after-filing: review stamps` (`git log --oneline origin/main..HEAD`).

## Contracts to hold it to

- `commit_changes_only <sha> <path>`: one parent; the `--no-renames --ignore-submodules=none
  -z` diff against it is exactly `<path>` (sentinel-compared); `<path>` is mode `100644` at
  `<sha>` (`REGULAR_FILE_MODE`). Both `: review stamps` and `: backlog` use it; nothing else
  carries a mode check of its own.
- `audit_paths_in_range` reads `--ignore-submodules=none`; `run-review.sh`'s audit queuing,
  which reads the same function, still behaves for ordinary diffs (the gate's
  `security-audit.sh`-driven and lifecycle tests show it).
- `self/tests/close-backlog.sh` K13a/b/c (gitlink hidden by `.gitmodules`, under both
  subjects, and at `hooks/sub` by `diff.ignoreSubmodules`) and K14 (stamps making
  `timing.jsonl` executable) are refused; K1/K2/K9 still pass.
- NOTES.md records round 3's ruling; `self/tests/README.md` lists K13/K14.

## Verdict

First line `Verdict: clean` or `Verdict: escalated`. Escalate only on a defect the diff
introduces or a listed contract it fails; list anything else as a non-blocking note.
