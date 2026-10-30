# 02 — review: propagate-agenttooling-access (round 2)

"No findings" is a legitimate verdict (AGENT_PLANS.md → "Review plans"). Fix local
findings in the pass; escalate structural ones.

## What the feature was supposed to do

Unchanged from round 1 (`review/complete/01-review-opus.md`): document that a Claude Code
cloud session must attach `ssdesai/agentTooling` with `add_repo` (read access) before a
propagation pull, because the session's git proxy serves only attached repos. Also,
optionally, make `update.sh` print one `remedy` line when the subtree fetch fails to
authenticate under the cloud profile, tested offline in `self/tests/`.

Round 1 found no defect in the code. It escalated two contracts that no test held, both
in `escalations/01-review-opus.md`:

1. A successful pull's stdout and stderr must stay separate through the new `tee`.
2. No `update-pull.*` temp file may be left behind, on the success path or the failure
   path.

The rework added U5h, U5i and U6e to `self/tests/update-cloud-branch.sh`, and their
description to `self/tests/README.md`, with ruling 8 in `NOTES.md`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. The round-2 change on its own is
the diff from the `review stamps` commit of round 1 to `HEAD`.

## Contracts to hold it to

- Every round-1 contract still holds (`review/complete/01-review-opus.md` → "Contracts
  to hold it to"). `update.sh` must be unchanged since round 1.
- U5h fails if `update.sh`'s `2>&1 1>&3` is reordered so that the two streams swap. U5i
  fails if the success-path `rm -f "$errlog"` is removed, and U6e if the failure-path one
  is. Check this by reading the code, or by making the edit in a scratch copy.
- The new checks need no network, and they do not change what U1–U8 assert.
- `self/tests/README.md` describes U5h, U5i and U6e.

## Verdict

The first line of the review report the runner names: `Verdict: clean` or
`Verdict: escalated`.
