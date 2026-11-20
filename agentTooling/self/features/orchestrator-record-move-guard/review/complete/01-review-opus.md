# 01 — review: orchestrator-record-move-guard

## What the feature was supposed to do

`orchestration-start-branch-v2` (#169) added one write the hook approves outright for an
orchestrator session: `git mv agentTooling/self/orchestrations/<slug> plans/orchestrations/<slug>`,
alone or after exactly `mkdir -p plans/orchestrations && ` (`orchestrator_record_move`,
`orchestrator_moves_own_record`, `ORCHESTRATOR_MOVE_*` in `hooks/allow-repo-commands.sh`). It
was meant only for the session's OWN stranded record. A security audit of a consuming repo's
pull of #169 (finding B1) showed that it trusts the slug the role lookup returns, which can come
from the ledger `.git/agenttooling-orchestrators`. It never reads the record, so it approved
the move of:
- (O39) another session's legacy record;
- (O18) agentTooling's own shipped record;
- (O40) an empty directory.

The base (before #169) denies all three.

The fix: the hook approves the move only when all of these hold at judgment time:
1. `agentTooling/self/orchestrations/<slug>/README.md` exists and is a regular file, not a
   symlink. Every #169 symlink check stays.
2. `orchestrator_role.names_role(<that README>, <session id>)` is true: the record itself names
   THIS session as an orchestrator. The session id is threaded through
   `orchestrator_command_allowed`, `orchestrator_moves_own_record`, `orchestrator_git_allowed`
   and `orchestrator_record_move`.
3. The record is the consuming repo's stranded one, not agentTooling's shipped one:
   `analysis/roots.py`'s `is_stranded_record`. The hook may not import `analysis/`, so it asks
   through `roots.py stranded <slug>`, the CLI `orchestration-start.sh` already uses, bounded by
   a timeout. Any failure there means no approval.

Anything else falls through to the base behaviour: for an orchestrator, the allowlist denial.

Out of scope:
- any change to the stranded classification itself (the sibling `pull-round-cleanups` owns
  `analysis/roots.py`'s classifier);
- `self/orchestrations/`;
- `self/BACKLOG.md` beyond this feature's own non-blocking findings.

Also on this branch, an orchestrator addendum made with the owner's go: the first commit adds
`AGENTTOOLING_PROFILE` to the `unset` in `self/tests/orchestrator-role.sh`. A cloud
feature-start exports it, so that test's sandbox ran as cloud and failed 21 checks in a
container's gate. That red gate on `origin/main` is why this feature was started with
`--no-gate`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `hooks/allow-repo-commands.sh`:
  - `orchestrator_record_move` returns True only when every #169 condition holds AND
    conditions 1–3 above hold;
  - the classifier call uses this hook's own tooling `analysis/roots.py` (resolved from the
    hook's real path), refuses a symlinked or missing classifier, has a timeout, and reads a
    non-zero exit, a timeout or any exception as "not approved";
  - no `analysis/` import is added to the hook;
  - new magic values are named constants.
- The session id reaches the move check from `main()` (the payload's `session_id`). A missing
  or non-string id means no approval.
- `self/tests/hook-orchestrator-role.sh` H28 keeps every existing row and adds:
  - O39: a session that only the ledger names, whose slug's README names another session →
    not approved;
  - O18: the session's own legacy record with no consuming-repo feature (agentTooling's shipped
    shape) → not approved;
  - O40: a ledger slug whose legacy directory is empty → not approved;
  - the own stranded record → still approved, under both profiles, and the printed remedy still
    really moves it.

  The fixture must carry the classifier (`analysis/`) so the approved case exercises it.
- `self/tests/orchestrator-role.sh` unsets `AGENTTOOLING_PROFILE` along with the other three.
- `hooks/README.md`: the orchestrator allowlist's row for the move names the three new
  conditions. Every README for a touched folder still describes it. The test header comment
  for H28 names the new rows.
- `./self/gate.sh` is green.

"No findings" is a legitimate verdict.

## Verdict
