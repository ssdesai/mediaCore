# 01 — review: propagation-as-feature

## What the feature was supposed to do

Close the `self/BACKLOG.md` entry "Propagation has no cost record." Per the ruling, each
pull of the agentTooling subtree into a consuming repo now runs as its own
`--method hand` feature there (`pull-agenttooling-pr<N>`): start → subtree pull inside the
worktree → pin the session or delegate → review (a stated decision) → `feature-close.sh`
→ the human merges. So the pull's session is routed and its cost lands in that feature's
record, and the residue stops listing that spend. `LIFECYCLE.md` → "Propagate" describes
the recipe; `update.sh`, if it performs the pull, runs inside the feature worktree and
refuses a pull straight onto `main`; any deny rule that would block the pull's merge in a
consumer worktree is narrowed. The 24 historical delegates stay a disclosed remainder in
NOTES.md.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Read
`self/features/propagation-as-feature/NOTES.md` for the implementer's rulings, but judge
against this brief, not against the notes.

## Contracts to hold it to

- The recipe in `LIFECYCLE.md` is complete enough to run from: slug convention, what the
  manifest prose records (the agentTooling sha and PR pulled), who pins what, whether the
  review runs, and that the human merges. It does not contradict LIFECYCLE §2 or
  `ORCHESTRATION.md`.
- `update.sh`'s behaviour matches its README entry and the recipe: it creates no branch
  or worktree itself, and its refusal on `main` is tested if it is testable in the
  lifecycle fixture — otherwise NOTES.md says why not and a backlog entry names the
  missing test.
- `git subtree pull` performs a merge: confirm the consumer deny rules from
  `hooks/wire-settings.py` let it run in a feature worktree, or that the branch adds the
  narrowest allow with a test.
- The entry's assertion is either shown in a test or stated as a dry description in
  NOTES.md with a backlog entry for the missing test.
- The gate is green; READMEs of every touched folder are current.

Fix local findings in the pass; escalate structural ones. "No findings" is a legitimate
verdict.

## Verdict

First line of `self/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
