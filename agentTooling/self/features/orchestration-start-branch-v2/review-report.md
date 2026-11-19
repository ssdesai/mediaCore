Verdict: clean

# Review (round 4): orchestration-start-branch-v2

Scope, per the owner's ruling of 2026-11-19, covers two things:

- the merge of `origin/main` (#168, `hook-silent-allow-sweep`, `2108a449`) in `b31712b`;
- round 4's fix of round 3's audit escalation in `63643dd`.

Base: `origin/main` (`2108a44`).

## What the batch was supposed to do

- **The fix:** `orchestration-start.sh --branch` takes only `claude/<slug>`, with the slug matching the shared
  `SLUG_PATTERN`. Anything else is refused before any write, and the refusal names `--branch claude/<slug>`.
  Round 3's explicit `refs/heads/<b>:refs/heads/<b>` push stays.
- **The merge:** a plain merge that keeps #168's hook changes and this feature's orchestrator record move.

## Does it?

Yes.

**The fix closes the escalation.**
- Round 3's `BRANCH_NAME_PATTERN`, `BRANCH_NAME_FORBIDDEN_LEADS` and `BRANCH_NAME_FORBIDDEN_PART` are gone.
- `orchestration-start.sh:339-342` now requires both of these, then still runs `git check-ref-format --branch`:
  - the `claude/` prefix (`CLOUD_BRANCH_PREFIX`);
  - a remainder matching `SLUG_PATTERN`. The pattern comes from `plan-runner-roots.sh` (line 103's import list)
    and is anchored, so no `/`, `+`, `:`, `..` or uppercase can pass.
- No `claude/<slug>` name can start with a remote's name or spell another ref, so the `origin/main`,
  `origin/HEAD` and `origin/claude/x` shadowing in round 3's audit (p18, p41, p42) can no longer happen.
- B7 asserts each of those names and the round-2 spellings: exit 1, the flag named, no record, and origin's and the
  checkout's refs compared whole. All rows pass in `self/gate-report.txt`.
- Round 4's own audit (`audit-report.md`) is `Verdict: clean`.

**The merge keeps both sides.**
- `git diff 2108a44 HEAD -- hooks/` holds only this feature's additions: `orchestrator_record_move`,
  `orchestrator_moves_own_record`, the `ORCHESTRATOR_MOVE_*` constants, the `record` parameter threaded through,
  and the `hooks/README.md` row. #168's changes are all present.
- `hook-orchestrator-role` (H28) and `allow-repo-commands` both pass in the gate.
- The `self/BACKLOG.md` conflict resolution keeps two things:
  - main's closure of the `--config` entry;
  - this branch's rewrite of the branchless-session entry.

**Docs agree with the code.** These all describe `--branch` as `claude/<slug>` only:

- the header of `orchestration-start.sh`;
- `ORCHESTRATION.md` → "Cloud sessions";
- `ORCHESTRATOR_SESSION_BRIEF.md`;
- `self/tests/README.md`;
- the B7 header comment;
- `NOTES.md` → "Round 4".

**Gate:** green. No section exits non-zero and none is SKIPPED.

## Fixed in this pass

- `self/BACKLOG.md`: the entry "`orchestration-start.sh --branch` has six refusals no test exercises" listed
  "`--branch main` or an invalid name" as untested, but B7 has asserted both since round 4. The entry now lists the
  five refusals that are still untested.
- `self/BACKLOG.md`: filed a new non-blocking entry. The session brief and `ORCHESTRATION.md` tell a session to
  always pass `--branch`, but an assigned branch that is not `claude/<slug>` is now refused.
  - **Workaround today:** a session already on such a branch runs the start without `--branch`. The script
    supports this, and its "on another branch" refusal says so.
  - **Gap:** neither document says it.

## Escalated to the next round

None.

## Deviations from the brief

None
