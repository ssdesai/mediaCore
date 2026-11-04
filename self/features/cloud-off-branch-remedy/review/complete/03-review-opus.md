# 03 — review: cloud-off-branch-remedy, round 3 (reconciliation merge)

## What the feature was supposed to do

Everything rounds 1 and 2 held it to (`../complete/01-review-opus.md` and
`../complete/02-review-opus.md` — read both; they still apply in full): when a restarted
cloud container is on `main` or detached, a refused switch/checkout to a branch some
manifest records as `branches[0]` gets the off-branch reason (fresh session on that
branch, or the human checking it out; never "commit on / push only `main`");
`session-start.sh` prints one fixed restart line there; no answer of the hook changes; the
probes run only on that refused switch/checkout path (X5).

Round 3 changes no feature code. Since this branch forked, PRs #95
(`capture-merges-committed-record`) and #96 (`pr-body-refresh`) merged into `main`; this
round is the reconciliation merge of `origin/main` into the branch (merge commit, no
rebase).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat` and the full diff. The round's own change is the
merge commit `a0e2ffb` — `git show --stat --cc a0e2ffb` shows only what the merge
resolved by hand. One file conflicted, `README.md` (the `hooks/` row, edited here, and
the `templates/` row, edited on `main`); the resolution keeps this branch's `hooks/` row
and `main`'s `templates/` row. `LIFECYCLE.md`, `self/README.md`, `self/tests/README.md`
and `self/gate.sh` merged without conflict. The "Re-runnable" sentence is deliberately
untouched.

## Contracts to hold it to

- Rounds 1 and 2's contracts, all of them: the merge must not have altered the hook,
  `session-start.sh` or their tests.
- Both sides' additions survive everywhere: the `README.md` `hooks/` row still carries
  the off-branch sentence and the `templates/` row still says `pr.sh` is at 7; every
  self-test either side registered is in `self/gate.sh` (hook-cloud-profile O1–O7/X5,
  session-start C4b–C4d, capture-merge, pr-body-refresh).
- No conflict marker, duplicated row or dropped sentence remains in any merged doc.
- `./self/gate.sh` is green.

"No findings" is a legitimate verdict.

## Verdict

The first line of `self/review-report.md` is `Verdict: clean` or `Verdict: escalated`.
