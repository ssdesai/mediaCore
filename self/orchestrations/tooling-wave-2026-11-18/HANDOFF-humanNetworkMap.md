# Handoff: humanNetworkMap features to a new orchestrator (2026-11-20)

Written by the orchestrator of `tooling-wave-2026-11-18` (session_0175k4pGGZCBv63KaXaGDio4)
for the next orchestrator, which the owner starts for new humanNetworkMap features. This session
keeps finishing the agentTooling round and its propagation pulls (listed under "Still open here")
and then closes. Everything else humanNetworkMap is yours.

## The owner's standing rules (carry them)

- You are an orchestrator: you triage, dispatch one child cloud session per feature, monitor,
  and merge. You build nothing. Children never merge.
- **Concurrency:** about 5 Opus sessions at once, across all orchestrators. This one has 1
  building now. Report a usage-limit stop to the owner once.
- **Merges in humanNetworkMap:** every merge waits for the owner's yes until humanNetworkMap has
  pulled agentTooling's conformance checks (#167). That is #383, still open. After that, a clean
  PR whose "Deviations from the brief" section is "None" may merge without asking; a non-empty
  deviations section always waits for the owner.
- **How to merge:**
  - Before any merge, verify the PR head contains current `main`:
    `git merge-base --is-ancestor origin/main origin/<branch>`.
  - Feature PRs: squash, passing `expectedHeadSha`.
  - Propagation pulls (`pull-agenttooling-pr<N>`): a merge commit, never squash.
  - When two PRs overlap, the later one merges `origin/main` normally (no rebase, no
    force-push), renumbers its migration and test ids onto what it finds, re-gates, and runs a
    review round scoped to the merge.
- **Rounds:** a finding blocks only if it leaves a briefed item open or is a regression the
  feature introduces. Everything else goes in `plans/BACKLOG.md`. Stop and ask the owner after 3
  review rounds, or 2 escalated audit rounds.
- **Conformance, done by hand** (humanNetworkMap's vendored harness predates #167). Each
  feature commits:
  - the owner's brief, verbatim, as `plans/features/<slug>/OWNER_BRIEF.md`;
  - an acceptance table;
  - a "Deviations from the brief" section in its PR.
- **Briefs:**
  - Each brief opens with `feature: humanNetworkMap/<slug>`.
  - No model identifiers in commits.
  - Branches are `claude/<slug>`, created by `feature-start.sh --branch claude/<slug>`.
  - Create child sessions with `outcome_branch` and the tag `orchestration:<your wave slug>`.
- **Restart point:** keep an `ORCHESTRATOR-STATE.md` (owner's rulings, a log, the queue) in
  your wave record. Push it after every ruling.

## Lessons from this round

- **Approvals must be typed in the child's own session.** A child's auto-mode permission check
  refuses actions the owner approved only through you: `add_repo`, `--no-gate`, a round past
  the cap. Ask the owner to type the OK in that session, and give them its link and a one-line
  text to paste.
- **Check a PR still contains `main` before merging.** A propagation pull can branch from an old
  `main`; #383 had to re-sync 176 files.
- **The cloud start gate is fixed.** agentTooling #171 fixed the leak that refused every cloud
  agentTooling start (`AGENTTOOLING_PROFILE`). humanNetworkMap starts were not affected.
- **Postgres in the container.** It can stop between turns. Children run
  `pg_ctlcluster 16 main start` before server tests.
- **Overlapping work merges in order.** Features touching ClaimReview and the extraction prompt
  conflicted. Merge them one at a time in the owner's order, each syncing the last.

## humanNetworkMap state at handoff

- **`main`:** `862c454c` (#381). Latest migration `0072_claim_names_only.py`, so the next is
  0073.
- **Test-spec ids:** the highest allocated are S1.63, S2.144, S3.199, C3.185, C4.123, so start
  from S1.64, S2.145, S3.200, C3.186, C4.124. Verify by grepping `plans/` on current `main`
  before allocating, and allocate disjoint ranges per feature in a briefs file.
- **Merged in this round:** #377 claim-duplicate-subset-drop, #378 claim-owner-options-restore,
  #379 claim-verify-parallel, #380 claim-review-pair-decision, #382 claim-topics (0071),
  #381 claim-extract-names-only (0072).
- **On hold:** `claim-new-entity-once`. Its branch `claude/claim-new-entity-once` stops at
  09df24db, not mergeable, replaced by the entity-linking design. Reusable pieces are listed in
  `ORCHESTRATOR-STATE.md` (17:00 entry).
- **Waiting on the owner's measurement:** entity-linking features 2–6 (`claim-run-entities`,
  `claim-entity-search`, `claim-entity-decide`, `claim-review-entities`,
  `claim-entity-metrics`). The owner's design brief and decisions D1–D11 are in
  `plans/claim-entity-linking/DESIGN.md`. The measurement is a names-only run compared with the
  reviewed run (`/api/projects/<id>/claim-runs/<a>/compare/<b>`), recorded in that file's
  Part 6.
- **Backlog items offered, not ordered:**
  - #377's negation case: a negated claim makes the affirmation look contained, so it is
    dropped.
  - claim-topics' "re-sort" of an old run.
  - Whether an accepted claim's information item keeps its topic (raised, not decided).
- Records of this round's humanNetworkMap features: `claim-audit-fixes-briefs.md` and
  `claim-review-blockers-briefs.md` in this folder.

## Still open here (this orchestrator finishes these, then closes)

- **humanNetworkMap #383** (`pull-agenttooling-pr169`, session_0175k4pFZCnXGreUKiS3pQ2K):
  - It only changes `agentTooling/` and one server test. The owner has approved the merge.
  - It waits for agentTooling `own-push-transport-keys`, then re-pulls. That round is past its
    audit cap, so it needs the owner's OK typed in its session.
  - This orchestrator merges it with a merge commit. Your features just merge `main` after it.
- agentTooling `own-push-transport-keys` (session_0175k4pFLZmAPkZjbm2zNrtr); the musicMap and
  vinylCatalogue pulls; a mediaCore catch-up pull. None touch humanNetworkMap.
- **Coordination:** if you need humanNetworkMap `main` frozen, or #383 merged before one of your
  merges, message session_0175k4pGGZCBv63KaXaGDio4.
