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
   (If you cannot read mediaCore, record them from the wording here.)
5. Gate `./self/gate.sh`, then review; the change is in `hooks/`, so it gets the security
   audit. On `Verdict: clean`, `feature-close.sh --self orchestrator-move-length-cap`.
   After 3 review rounds or 2 escalated audit rounds, stop and report.

Commit subjects are prefixed `orchestrator-move-length-cap:`; every commit ends with the trailer
lines your session instructions give. No model identifiers in committed files. Commit the
owner's brief (this section) as the feature's OWNER_BRIEF, and give the PR a "Deviations from
the brief" section ("None" if none) and an acceptance table (each briefed item → test or evidence).

## Report, terse

PR URL, gate result, review and audit verdicts, cost, deviations. Last line: the PR link or the
exact blocker.

## Owner's addition (2026-11-20)

Relayed by the orchestrator, ordered by the owner (verbatim: "you should triage it as a new
change with the existing stuff that's going").

### Third defect: the conformance check flips on unchanged evidence
The conformance check that `feature-close.sh` runs (brought by #383; it refuses a close when review and conformance disagree) gives different verdicts for the same brief item on the same evidence across runs. Evidence: humanNetworkMap feature `claim-run-entities` (PR ssdesai/humanNetworkMap#385, branch `claude/claim-run-entities`, records under `plans/features/claim-run-entities/` — attach humanNetworkMap read-only with add_repo if you need them):
- rounds 4 and 5 marked owner item 1 ("The problem") done; round 6 marked it PARTIAL, though nothing touching item 1 changed between them;
- round 5 marked owner item 3 PARTIAL while the review said done (that one was arguably a real gap, fixed by a docs edit).
Each flip costs an owner-approved extra round past the cap; #385 is now on round 7.

Do (numbered on from the brief's own items, so each owner item keeps a unique id):
6. Diagnose first (in NOTES): where the verdict comes from (model judgment, prompt inputs, what evidence it is shown — e.g. whether it sees OWNER_BRIEF's owner rulings and earlier rounds' verdicts), and why the same input yields different verdicts.
7. Make it stable: an item judged done on given evidence must not regress to partial unless the diff touching that item, or the brief/rulings for it, changed. Choose the mechanism (e.g. carry the previous round's per-item verdicts and evidence forward and require a stated changed-evidence reason to downgrade; or have the close refuse only on a disagreement with a reason the reviewer can act on). Keep fail-closed for genuinely new gaps.
8. Tests: a fixture where an unchanged item judged done in round N stays done in round N+1; one where a changed item can still be downgraded.
9. If the fix is larger than this feature should carry, stop and report a split proposal instead of building it.
Same rules otherwise (rounds cap, deviations section, never merge).
