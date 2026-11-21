# `orchestrator-move-length-cap` — brief handed to the next orchestrator

This wave closed with one agentTooling fix still to make. The owner accepted the finding for the
mediaCore catch-up pull (2026-11-20) and asked for the fix to be handed to the
`entity-linking-2026-11-20` orchestrator (session_0175k4pEEsgzZnoKG8NYDyL7) for dispatch. The text
below is the brief for its child session, on agentTooling with `outcome_branch:
claude/orchestrator-move-length-cap`.

---

feature: agentTooling/orchestrator-move-length-cap

agentTooling self feature `orchestrator-move-length-cap` — implementer brief

## Role

You are the session for ONE agentTooling self feature. An orchestrator session created you and
reads your report; send it with the claude-code-remote send_message tool, session_id "@parent".
If you are blocked, say exactly what you need and stop. Never merge your PR.

## The defect (found by mediaCore's pull audit, confirmed on main 25b332c9)

In `hooks/allow-repo-commands.sh`, `main()` (around line 5959) calls
`orchestrator_moves_own_record(command, …)` before `orchestrator_command_allowed`, and the
length cap `ORCHESTRATOR_MAX_LINE_CHARS` (20000, "past this the line is refused unread", R1) is
checked only inside `orchestrator_command_allowed`. An orchestrator's own record move
(`git mv agentTooling/self/orchestrations/<slug> plans/orchestrations/<slug>`, optionally after
`ORCHESTRATOR_MOVE_MKDIR_LEAD`), padded with whitespace past 20000 characters, is therefore
approved outright where it must be refused unread. It came in with #172
(orchestrator-record-move-guard). On origin/main before #172 the padded line was denied.

## Second defect (mediaCore pull audit round 2, B1; confirmed on main 25b332c9)

`orchestration-start.sh` (around lines 246–249) runs `analysis/roots.py start-refusal <slug>`
and goes on whenever it exits `START_OK_RC` (0), whatever it printed. An emptied or stubbed
`roots.py` exits 0 with no output, so a start that must be refused goes ahead and writes a
record. The comment above (lines 106–111) promises the check fails closed. Fix: `roots.py
start-refusal` prints one fixed token (a named constant, e.g. `ok`) on the go-ahead, and the
script proceeds only on exit 0 WITH exactly that output; anything else refuses. Apply the same
to `roots.py self-write` (`SELF_WRITE_OK_RC`, same shape). Add test rows for an empty and an
exit-0 stub `roots.py`, for both checks. Also put on `self/BACKLOG.md`: `run-review.sh`
(around lines 440–447) adds the audit's stem to the manifest's `plans` list without checking
whether it is already there (seen as a duplicate `02-audit-opus`).

## Do

1. Start: `./feature-start.sh --self orchestrator-move-length-cap --branch claude/orchestrator-move-length-cap`
   (in the background, output to a scratchpad file; wait for its exit notification).
2. Enforce the cap before any orchestrator judgment: put the length check at the top of
   `orchestrator_moves_own_record` (so every caller gets it) — and keep the one in
   `orchestrator_command_allowed`. Name no new literal; reuse `ORCHESTRATOR_MAX_LINE_CHARS`.
3. Tests in `self/tests/` (beside the existing record-move tests): the approved move padded to
   exactly 20000 characters is still approved; padded to 20001 it is denied with the
   orchestrator allowlist reason; the same for the `mkdir -p` lead form. Then fix the second
   defect above, with its tests.
4. Add to `self/BACKLOG.md` the audit's two non-blocking findings (mediaCore
   `plans/features/pull-agenttooling-pr173/audit-report.md`): (a) an edited `analysis/roots.py`
   defeats the new legacy-record classifier; (b) only the last fence of a record is counted.
5. Gate `./self/gate.sh`, then review; the change is in `hooks/`, so it gets the security
   audit. On `Verdict: clean`, `feature-close.sh --self orchestrator-move-length-cap`.
   After 3 review rounds or 2 escalated audit rounds, stop and report.

Commit subjects are prefixed `orchestrator-move-length-cap:`; every commit ends with the trailer
lines your session instructions give. No model identifiers in committed files. Commit the
owner's brief (this section) as the feature's OWNER_BRIEF, and give the PR a "Deviations from
the brief" section.

## Report, terse

PR URL, gate result, review and audit verdicts, cost, deviations. Last line: the PR link or the
exact blocker.

## After it merges

Each consuming repo gets the fix on its next routine propagation pull (merge commit, never
squash); no urgent pull round is needed: every consumer already carried the defect.

The exception is mediaCore. Its catch-up `pull-agenttooling-pr173` is handed over too:
- Session: session_0175k4pGmM41NexxK2eVs4vK.
- Branch: `claude/pull-agenttooling-pr173`, pushed, with two review rounds committed.
- State: round 2's review was clean, and the owner accepted the length-cap finding for it. The
  audit escalated on B1, so it stopped at the audit cap and has no PR.

Once this fix merges, have that session:
1. re-pull the new agentTooling main with `update.sh`;
2. commit the review's two uncommitted fixes;
3. re-gate;
4. run the review and audit again as round 3. This needs the owner's OK for a round past the
   cap, typed in that session.

It then closes, and the owner merges it with a merge commit.
