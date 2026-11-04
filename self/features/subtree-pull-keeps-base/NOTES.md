# Notes: subtree-pull-keeps-base

Rulings made during the hand build, each with its reason. The brief is the spec; these
are what it left open.

1. **The hypothesis, as stated, is refuted. The corrected form holds.** The brief
   supposed that a hand-committed merge without `git-subtree-*` trailers breaks the next
   pull's base lookup. `git subtree`'s own source says otherwise
   (`/usr/lib/git-core/git-subtree`, `find_latest_squash` and `cmd_merge`). The base is
   the newest commit reachable from `HEAD` whose message has `git-subtree-dir: <prefix>`
   and a `git-subtree-split:`. That commit is the `Squashed '<prefix>/' changes` commit
   `new_squash_commit` makes, and it becomes the merge's second parent. The merge commit
   carries no trailer even on a clean pull, and committing it by hand with `MERGE_HEAD`
   kept changes nothing. A synthetic reproduction, the session's scratch `repro.sh`
   (upstream `a1`, then `a2` pulled, then `a3` changing the same line again), ran each
   resolution shape once:

   | Shape of the round-2 resolution | Base of the round-3 pull | Round-3 pull |
   |---|---|---|
   | clean pull | the round-2 squash | clean |
   | merge committed by hand, `--theirs` | the round-2 squash | clean |
   | merge recorded as an ordinary commit | the original `subtree add` | conflicts |
   | PR squash-merged, title-only message | the original `subtree add` | conflicts |
   | PR squash-merged, bodies kept | text copied into the squash body | clean |

   So the chain breaks when the squash commit stops being reachable from `main`, not when
   the merge lacks a trailer.
2. **Evidence from the real consumers: squash-merged propagation PRs.** This session's
   `add_repo` was denied by the auto-mode classifier. The parent session read both repos'
   `main` (depth 300, read-only) and sent the logs:
   - **humanNetworkMap** (pulls clean): every pull since pr89 lands as a real two-parent
     merge whose parent 2 is the `Squashed` commit (`1f961379` pr97 → `418703fc`, split
     `5af67f7b`; `32421cee` pr92 → `7efaf857`; `eeb3ecf3` pr90 → `2f6cad71`). Each squash's
     parent is the previous squash. An old GitHub squash-merge, `1ee512e2`
     "pull-agenttooling-pr77 (#177)", copied the trailer text into its body, and later
     merge commits restored the chain.
   - **mediaCore** (conflicted in pr97): every propagation PR since pr73 is a GitHub
     squash-merge with one parent: `1c0b861` (#34, pr97), `c6f22eb` (#33, pr92),
     `cef1f8d` (#32, pr90), `ada5c92` (#31), `ca9c86d` (#30), `b4822b6` (#29), `1b26ed8`
     (#28), `caf50af` (#27), `3303278` (#25). The last real merge is `ba8b4c3` (pr64,
     squash `4fd5075`). `git log --grep='^git-subtree-dir: agentTooling/*$'` matches
     those squash-merge commits, because their bodies copied the collapsed `Squashed …`
     message, trailers included. `git subtree` therefore took a **mainline** commit as
     its base and read the split from its body, which worked by accident. `c6f22eb`, the
     hand-resolved pr92 pull, is missing from that list: its body has no trailer text. So
     the pr97 pull's base was `cef1f8d` (pr90), and every file upstream changed both in
     pr90..pr92 and in pr92..pr97 conflicted: LIFECYCLE.md, ORCHESTRATION.md, README.md,
     self/README.md. No local edits were involved.
   - vinylCatalogue and musicMap were not read. Their pr92 pulls were hand-resolved too,
     and they conflicted on the same four files, so they are presumably like mediaCore.
     `forge.sh auto-merge` asks for a merge commit, so the squash-merges came from merges
     made by hand in the GitHub UI.
3. **The fix rests on the vendored tree, not on the merge strategy.** `update.sh` cannot
   control how a PR is merged. Before each pull it fetches upstream and replays the base
   lookup (`latest_squash`, the same rules as `find_latest_squash`: last split line in
   the message, a mainline line means use the second parent). It then compares
   `HEAD:<prefix>` with the recorded split's tree. When they differ and some upstream
   commit's tree equals the vendored tree, the chain is `broken` and the base is
   re-anchored at that commit. That repairs any history whatever broke it, and needs no
   file a repo must keep honest.
4. **The anchor is a squash commit joined by an `ours` merge, not a mainline commit
   carrying trailers.** A mainline commit carrying trailers would make the
   fragile-by-accident base every squash-merging consumer has today, and `--check` would
   flag our own repair. A `git-subtree-mainline:` line on the merge, git subtree's rejoin
   shape, would be worse: once a forge squash-merge copies it into a one-parent commit's
   body, `find_latest_squash` asks for `^2` and dies. So the anchor is a parentless commit
   holding the upstream tree, with the trailers in its closing paragraph (a proper trailer
   block, so a squash body that keeps commit messages keeps them too). An `ours` merge
   whose own message names no trailer joins it to the branch, so no file changes.
5. **The manifest's split sha is prose, so the explicit fallback is `--base <sha>`.**
   The brief offered the manifest's recorded split as the fallback. No script reads it:
   it is in the manifest prose, not the fence. When the vendored tree matches no upstream
   commit (local edits under the prefix, state `edited`), nothing is re-anchored
   automatically. `--base <sha>` anchors by hand at a sha taken from that prose. It is
   refused unless the sha is in the fetched upstream history.
6. **`--check` reports five states; only `broken` and `none` exit 1.** `fragile` (the
   base is a mainline commit, its tree holding the prefix as a subdirectory) is printed
   on its own `chain` line, as the parent asked, but exits 0: the pull works, and
   failing every squash-merging consumer would teach rounds to ignore the check. `edited`
   exits 0 for the same reason. `--check` skips the branch and dirty-tree refusals so it
   runs from `main`, and it writes nothing but `FETCH_HEAD`.
7. **A conflict is guided, not resolved by the script.** Resolving `--theirs`
   automatically would be wrong whenever a repo has local edits under the prefix (C8 is
   exactly that case). So `update.sh` leaves the merge in progress and prints `conflict`
   (the files) and `resolve` lines: `git rm -r -q -- <prefix>`,
   `git read-tree --prefix=<prefix>/ -u MERGE_HEAD`, and commit *that* merge. The next
   pull's chain check repairs a hand resolution done any other way anyway. Round 2: round
   1 advised `git checkout --theirs -- <prefix>`, which the review noted fails as a whole
   on a modify/delete conflict (a file upstream deleted), after which a `git add` commits
   conflict markers. `read-tree` takes `MERGE_HEAD`'s tree, the upstream squash at the
   root, under the prefix wholesale, deletions included (C8 now has one).
8. **What the next propagation round must do.** The pull that brings this change in
   still runs each consumer's previously vendored `update.sh`, which has no chain check.
   In mediaCore, vinylCatalogue and musicMap, that one pull merges from the stale base
   again, and may conflict once more on files upstream changed in both ranges, with no
   local edits involved. The old `update.sh` prints no `resolve` line, so resolve it as
   `LIFECYCLE.md` → "Propagate" now says: `git rm -r -q -- agentTooling`,
   `git read-tree --prefix=agentTooling/ -u MERGE_HEAD`, `git commit` (the merge in
   progress, never a fresh commit after an abort), then
   `agentTooling/sync-plans.sh`. Then run the newly vendored
   `agentTooling/update.sh --check` and put its `chain` line in the round's report: it
   reads `intact` once the PR is merged with a merge commit, and `fragile` or `broken`
   if it is squash-merged. From then on no step is by hand: every later `update.sh`
   re-anchors a `broken` chain before it pulls, so pulls stay clean whatever merge
   button is pressed. humanNetworkMap needs nothing. The owner should merge propagation
   PRs with a merge commit (README.md → "Updating"), which keeps the chain `intact`
   rather than repaired.
9. **Round 2 also makes the anchor's guarantee explicit and tests a squash-merged
   anchor.** These are two of round 1's non-escalated notes. After `anchor`, `update.sh`
   re-runs `latest_squash`, and refuses to pull unless the lookup lands on the new squash
   commit: `git log` walks by date, so clock skew could otherwise leave an older
   trailer-bearing commit first. C10 squash-merges a PR that re-anchored, with GitHub's
   body (commits oldest first): `fragile`, and the next pull is clean. The order matters,
   and C10's first draft found it. `git subtree` takes the *last* `git-subtree-split:`
   line in a message, so a body listing commits newest first names the anchor's older
   sha. `update.sh` then reads the chain as `broken` and re-anchors, so the pull is still
   clean, but the text alone would have misled. Round 1's last note (a rejoin base whose
   `^2` is missing is worded `none`) is left as is: the exit status is right, and
   `git subtree` dies on that base too.
10. **Merged `origin/main` (PR #98, capture-record-wording-and-carried-rows) before
    round 2, with a merge commit.** It auto-merged; `self/gate.sh` and
    `self/tests/README.md` keep both sides' entries.
