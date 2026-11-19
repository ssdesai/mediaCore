# Orchestrator state: tooling-wave-2026-11-17

This is a restart point for the orchestrator session (session_0175k4pGixSMGqsa6ckP1aeW) in case its container is lost. Snapshot taken 2026-11-18 01:10 UTC. The live record of features, sessions and PRs is the JSON fence in `README.md`. This file adds what the fence cannot carry: the owner's rulings, the landing order, the queue and the procedures.

## Owner's standing rulings
- **Branches.** Each new feature gets a new branch in a new child session. Never take over or force-push a squash-merged branch. `start-squash-merged-branch` is parked for this reason (#162 documents the rule). Its branch `claude/start-squash-merged-branch` (cad4408) is kept unmerged. Never merge it; the owner may delete it.
- **Merging.** Merge only on the owner's yes, given per batch. Use squash with `expectedHeadSha`. Children never merge.
- **Notices.** The owner relays HNM results to a local data worker. For each HNM PR that becomes ready, tell the owner what it unblocks for the data work and send a PushNotification.
- **`orchestration-start-branch`, round 4.** Round 4 closes only A6 and A7:
  - A6: refuse when `refs/remotes/origin/<name>` exists.
  - A7: `branch_owner` reports "could not read" and the caller refuses.

  A finding blocks only if it is a regression from round 4 or a failure to close A6 or A7. Everything else is filed in `self/BACKLOG.md`, non-blocking. If round 4 still escalates, stop and recommend parking it.
- **Audit rounds.** After 2 escalated audit rounds, stop and ask the owner to rule.
- **Usage limit.** Report a usage-limit stop once; don't spam resumes. About 5 concurrent Opus sessions is the practical ceiling.

## How children run
1. Create the child with `create_session(source_url=https://github.com/ssdesai/<repo>, outcome_branch=claude/<slug>, model=Opus, tags=["orchestration:tooling-wave-2026-11-17"])`. The prompt carries the full brief and the Rules block (see the `claim-commit-statement` and `article-lead-picture` prompts, rebuilt from the briefs here).
2. The child runs `./agentTooling/feature-start.sh <slug> --method direct --branch claude/<slug> --orchestration tooling-wave-2026-11-17`, with `--self` in agentTooling. Then it builds, runs the gate and `run-review.sh`, and on a clean verdict runs `feature-close.sh`, which opens the PR. It then messages `@parent`.
3. Record each new child with `python3 analysis/manifest.py --self --orchestration tooling-wave-2026-11-17 add-feature|set-feature repo=… slug=… session=… branch=… pr=…`, run from /home/user/agentTooling. Commit with the session trailers and push to `claude/funny-ramanujan-vy21yy`.
4. Monitor with `list_sessions(children:true)`, `list_events(kinds:["result"])` and `send_message`. Check in with `send_later` every 15 minutes while HNM children run. Archive a child once its PR is final.

## HNM migration and test-spec collisions
Each claim feature adds a migration, and their test-spec ids collide. Before merging an HNM PR, check that its base includes the current main. The child whose PR merges second must:
1. Merge `origin/main` with a normal merge. Never rebase or force-push.
2. Renumber its migration and its test-spec ids.
3. Keep every sibling field in `ClaimCandidateOut`, `NewEdgeOut`, `ClaimRunStartIn` and the contract fixtures.
4. Re-run the gate and a review scoped to the merge.

Main is at migration 0064:
- #358 claim-owner-options, 0063, squash 1bdd66ab
- #359 claim-completeness-pass, 0064, squash bcfd63f1

The owner has given standing approval to merge as features finish: "merge whatever's done" (01:08 UTC), confirmed at 04:10 UTC as "You're free to merge things that seem clean as they finish". No need to ask first. That covers PRs that are clean, are on current main, and passed the gate.

All four HNM children hit the 5-hour usage limit between 01:15 and 01:47 UTC. The limit reset at 04:00, and each child was resumed at 04:09 and told to re-check its state and re-run any gate or review that was cut off. Four concurrent Opus sessions is still enough to hit the limit.

## Landing order and queue (as of 01:10 UTC; children resumed 04:09)
| Feature | State | Next |
|---|---|---|
| claim-candidate-hygiene | MERGED #360 (squash 950692e8, 04:43 UTC). No migration. Test-spec ids S1.24.20–23, S2.69 and S3.109. `claim_chunks.HONORIFICS` is now the only honorific list | Done, session archived |
| claim-verify-names | MERGED #364 (squash e9e4ae01, 05:39 UTC), migration 0066; session archived. Non-blocking follow-ups: a test for a commit made during a running Re-verify; progress can briefly read over 100% | Done |
| claim-commit-statement | MERGED #361 (squash dc0e3204, 05:05 UTC), migration 0065; session archived. The data worker can commit again | Done |
| article-lead-picture | MERGED #362 (squash ea0b35d0, 04:52 UTC); session archived | Open owner question: `_classified` ticks every rendition of `og:image` on the page, so a hidden zoom copy would also be saved. The suggested rule is to tick only `lead_picture_url`. |
| claim-gaps-name-noise | MERGED #363 (squash c4fb4623, 04:55 UTC); session archived. Earlier notes: round 3 authorised by the orchestrator at 04:37 UTC, scoped to one missing router test (S3.106 roster person vs institution). Rounds 1–2 escalated; round 2 on that test only. The gate is green at 9f0d5afe. No migration. `UncoveredNameOut` gains `running_head`. Session session_0175k4pEmZeo4yeKLuZ3UAo6 | Merge on clean. If round 3 escalates on anything else, stop for an owner ruling |
| orchestration-start-branch (agentTooling) | Round 4: its review was clean, but the audit escalated N1–N3, where the A6 check reads origin's cached refs (single-branch clone, failed fetch, remapped refspec) | PARKED by the owner's ruling (01:15 UTC). The child files N1–N3 and the ls-remote fix in `self/BACKLOG.md` on its branch, records the park in NOTES and pushes. No PR. The branch is kept unmerged, like start-squash-merged-branch; archive the session after its final sha. |
| claim-multi-span | MERGED #365 (squash 81349e34, 06:15 UTC), migration 0067; session archived | Done |

## Wave complete (2026-11-18 06:16 UTC)
- Every queued feature is merged or parked. humanNetworkMap main is at 81349e34, migration 0067.
- `session_window.to` was set to 06:15:47Z. `orchestration-capture.sh` priced the orchestrator overhead at $28.86 (`planning.json`). `report.py` (run with `--checkout humanNetworkMap=<export of HNM main>`) wrote `report.md` and `report.json`:
  - Group total $266.70, of which $237.84 is priced features and the rest is overhead (10.8%).
  - The two parked features are unpriced, because a parked feature has no close capture.
- The record branch merged agentTooling `origin/main` so the self features' `report.json` paths resolve.
- Open owner questions:
  - article-lead-picture: ANSWERED 13:40 UTC, "I basically want the best quality image". Dispatched `article-best-rendition` (HNM; session_0175k4pFtVe565zDgRWSpiAZ; branch claude/article-best-rendition). Each group of renditions becomes one candidate, saved at its largest intrinsic size, and the lead rule no longer ticks hidden copies. Merge on clean, then re-run the end-of-wave steps.
  - A records-only PR for this wave?
- Non-blocking follow-ups noted by reviewers:
  - claim-verify-names: a test for a commit during Re-verify, and progress over 100%.
  - claim-multi-span: the client's span cap is a hand copy of `CLAIM_SPANS_MAX`.
  - Rates history is stale (`refresh_rates.py`, agentTooling).
  - `self/orchestrations/README.md` does not index its record folders. This predates the wave.

Advice given to the data worker: until claim-commit-statement merges, a commit stores only the excerpt, not the statement. Keep reviewing, but hold off on committing.

## Follow-up round (2026-11-18 12:26 UTC, owner: "fix the small followups")
- `claim-review-followups` (HNM; session_0175k4pJJem5z8NNvTzZskYp): MERGED #366 (squash 92eed566, 13:05 UTC), no migration, session archived. It covers:
  - Re-verify progress reading over 100%;
  - a test for a commit made during a running Re-verify;
  - the client span cap taken from the server's `CLAIM_SPANS_MAX`.
- `rates-refresh-2026-11` (agentTooling self; session_0175k4pFWusCtHE7Sg9AVnfR): MERGED #163 (squash 3482620a, 13:17 UTC), session archived. Prices checked against the Anthropic pricing page. It adds claude-fable-5-2 and claude-mythos-5-2 to the rate history and brings `checked` to today.
- No fix is needed for the README-index gap: `self/readme-index-ignore` already covers the record folders, and the gate's index check passes.
- Round closed 13:17 UTC: window to 13:16:53Z, recaptured, re-reported. Group total $282.76 = priced features $251.24 + overhead $31.52 (11.1%); the 2 parked features stay unpriced. No check-in pending.

## Handoff (2026-11-18 13:45 UTC)
- The owner moved new data-worker follow-ups to a new orchestrator, session_0175k4pHHKcN1FEmhRem4qsE. It has 6 HNM claim features and keeps its own record.
- It was told to start now:
  - migration 0068 is its own;
  - test-spec ids start at S3.115+ and C3.126+;
  - avoid page_media.py, article_render.py and the article_import fixtures.
- This orchestrator only finishes `article-best-rendition` (check-in trig_016EuT1m2xeRC2zkN92za3Yo, 14:22 UTC). On merge:
  1. Message the new orchestrator with the main sha and the ids used.
  2. Close this record: window, capture, report.
  3. Retire.

## Wave closed (2026-11-18 14:11 UTC)
- `article-best-rendition`: MERGED #367 (squash 89b0b17e). No migration; session archived, check-in deleted.
- The new orchestrator was told the main sha and the ids used.
- Window to 14:11:20Z, recaptured and re-reported:
  - Group total $293.37: 20 priced features $260.18 plus overhead $33.19 (11.3%).
  - The 2 parked features stay unpriced.
- This orchestrator is retired. No child, check-in or trigger remains.
- One open owner question: a records-only PR for this record?

## End of wave
1. `manifest.py --self --orchestration tooling-wave-2026-11-17 set-window-to now`
2. `orchestration-capture.sh --self tooling-wave-2026-11-17`
3. `python3 analysis/report.py --self --orchestration tooling-wave-2026-11-17`
4. Open a records-only PR only if appropriate or the owner asks.
