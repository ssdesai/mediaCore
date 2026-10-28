# 02 — review: subtree-pull-keeps-base, round 2

## What the feature was supposed to do

The whole spec is round 1's brief, `review/complete/01-review-opus.md`; read it first.
Round 1's verdict was clean. Round 2 does two things after it:

1. **Merges `origin/main`**, with a merge commit, to bring in PR #98
   (capture-record-wording-and-carried-rows). It auto-merged. `self/gate.sh` and
   `self/tests/README.md` must keep both sides' entries: `report-carried-streams.sh` from
   main and `subtree-chain.sh` from this branch.
2. **Acts on three of round 1's non-escalated notes**:
   - **The `resolve` advice is replaced.** `git checkout --theirs -- <prefix>` failed on a
     modify/delete conflict, after which a `git add` would commit conflict markers. The
     advice is now `git rm -r -q -- <prefix>`, `git read-tree --prefix=<prefix>/ -u
     MERGE_HEAD`, and `git commit`, which takes upstream's whole tree, deletions included.
     It is changed in `update.sh` and in `LIFECYCLE.md`, `README.md`, `ORCHESTRATION.md`
     and `NOTES.md`.
   - **The anchor's guarantee is made explicit.** After `anchor`, `update.sh` re-runs
     `latest_squash` and refuses to pull unless the lookup lands on the new squash
     commit; `anchor` now echoes that commit.
   - **The tests**: C8 adds a modify/delete conflict and resolves it with exactly the
     printed commands. A new C10 squash-merges a PR that re-anchored, using GitHub's body
     with commits oldest first. `NOTES.md` 9 records why the order matters: git subtree
     takes the last split line.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

For round 2 alone, read `git diff <round-1 head>..HEAD`, where the round-1 head is the
`subtree-pull-keeps-base: review round 1` commit. Leave out the merge's own side with
`git diff <round-1 head>..HEAD -- . ':!self/features/capture-record-wording-and-carried-rows'`.
Then check that the merge itself left nothing out: `git show --stat <merge>`.

## Contracts to hold it to

- **Everything in round 1's brief still holds.**
- **The resolve advice.** Under `-Xsubtree`, is `MERGE_HEAD`'s tree upstream's tree at
  the root, so that `read-tree --prefix=<prefix>/` puts upstream exactly at the prefix?
  Does `git rm -r` on a prefix with unmerged entries clear them, so the `read-tree` does
  not refuse? Is the result committed as the in-progress merge? C8 asserts all of this;
  check that its assertions mean what they say.
- **The post-anchor check.** `anchor`'s stdout must be exactly the squash sha.
  `git merge -q` must print nothing to stdout there, or every anchor is refused. A
  refusal leaves the anchor merge on the branch: is that state safe to rerun?
- **The merge from main.** Nothing dropped, and both gate entries present.
  `./self/gate.sh` must be green.
- **Docs.** Every place that named `git checkout --theirs` for a conflicted pull now names
  the `read-tree` resolution. `NOTES.md` 8 must say that the transitional pull runs the
  old `update.sh`, which prints no `resolve` line, so the docs are the session's only
  guide for that pull.

"No findings" is a legitimate verdict.

## Verdict
