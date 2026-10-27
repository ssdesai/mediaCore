# 02 — review: cloud-off-branch-remedy, round 2

## What the feature was supposed to do

Everything round 1 held it to (`../complete/01-review-opus.md`, "What the feature was
supposed to do" and "Contracts to hold it to" — read those two sections; they still
apply in full): when a restarted cloud container is on `main` or detached, a refused
switch/checkout to a branch some manifest records as `branches[0]` gets the off-branch
reason (fresh session on that branch, or the human checking it out; never "commit on /
push only `main`"); `session-start.sh` prints one fixed restart line there; no answer of
the hook changes; docs and the docs-only model-tiering bullet as listed.

Round 1 escalated one finding (`../../escalations/01-review-opus.md`): the off-branch block
in `cloud_git_deny_reason` read the checkout's head with a git probe on EVERY cloud
refusal, before checking that the command was a switch or checkout — one extra git call
for every refused `git push`, `git reset`, `git branch -D`, contradicting the contract
that the new probes run only on the refused switch/checkout path.

Round 2, built by hand: that block now runs only when `switch_target_names(args)` is
non-empty, and `self/tests/hook-cloud-profile.sh` gained X5, which pins the git calls of a
refused cloud non-switch (`git push origin x`: two head reads plus the reason's one
manifest grep; `git reset --hard`: one plus one).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff. Round 2's own change is the commit `cloud-off-branch-remedy: rework
round 2` (`git show` it), but judge the whole diff.

## Contracts to hold it to

- Round 1's contracts, all of them.
- The guard: no refused cloud command other than a `git switch`/`git checkout` naming a
  branch reaches `checkout_state`, `repo_shape` or any manifest probe from the off-branch
  block. X5 would fail if the guard were removed.
- `hooks/README.md` ("The extra probes run only on that refused path") and `NOTES.md`
  ruling 2 are now true as written.
- `./self/gate.sh` is green.

"No findings" is a legitimate verdict.

## Verdict

The first line of `self/review-report.md` is `Verdict: clean` or `Verdict: escalated`.
