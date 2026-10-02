# 01 — review: start-takeover

## What the feature was supposed to do

Close the `self/BACKLOG.md` entry "A start interrupted between `git worktree add` and its
`<slug>: start` commit blocks its own slug for good." `feature-start.sh` now takes over
its own abandoned half-start instead of refusing it, under a predicate that never takes a
live concurrent start of the same slug:

- the branch tip is still its `Created from` commit (no `<slug>: start` commit),
- the worktree is clean,
- the earlier start is provably dead: a lock written at `worktree add` time carries the
  start's PID and that process is gone (a missing lock on an otherwise-untouched
  half-start counts as the pre-fix shape and is also dead).

A live PID refuses, naming the PID. The prune of merged worktrees uses the same predicate.
Agents still never delete refs by hand.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Read
`self/features/start-takeover/NOTES.md` for the implementer's rulings, but judge against
this brief, not against the notes.

## Contracts to hold it to

- The assertion from the entry, as tests in `self/tests/`: a start killed during its gate,
  re-run with the same slug, succeeds; a second start of a slug whose first start is still
  running is refused. Plus the negative: a dirty half-start worktree is still refused.
- The lock is written after `worktree add -b` and before anything that can fail; its removal
  on the success path happens after the `<slug>: start` commit. Whatever the refusal path
  does with it is stated in NOTES.md and consistent with the takeover predicate.
- The takeover never resets, force-moves or deletes a branch that has moved since creation.
- The prune's new behaviour is the same predicate, not a second one; a live lock is skipped.
- The consumer layout (`plans/`, no `--self`) works too — `feature-lifecycle.sh` drives a
  fixture consumer; check the new cases run there or say why the self layout suffices.
- New test wired into `self/gate.sh` with its row in `self/tests/README.md`; the gate is
  green.
- `LIFECYCLE.md` and the root `README.md` describe the new behaviour in the files' voice.
- READMEs of every touched folder are current (CONVENTIONS "Keeping READMEs up to date").

Fix local findings in the pass; escalate structural ones. "No findings" is a legitimate
verdict.

## Verdict

First line of `self/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
