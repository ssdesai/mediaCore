Verdict: clean

# Review — orchestrator-record-move-guard

## What the batch was supposed to do

Close the propagation audit's B1 on #169: the hook approved `git mv agentTooling/self/orchestrations/<slug> plans/orchestrations/<slug>` (alone or after `mkdir -p plans/orchestrations && `) for any slug the role lookup returned. That slug can come from the ledger `.git/agenttooling-orchestrators` alone, without reading any record. So the hook approved moving another session's record (O39), agentTooling's shipped record (O18) and an empty folder (O40). The approval must now also require, checked when the hook judges the command:

1. the folder's `README.md` is a regular file and not a symlink;
2. that README names this session as an orchestrator (`orchestrator_role.names_role`), using the payload's `session_id`;
3. `analysis/roots.py stranded <slug>` exits 0. The hook runs this as a subprocess and does not import `analysis/`.

Two side fixes were also in scope: `AGENTTOOLING_PROFILE` added to the `unset` in `self/tests/orchestrator-role.sh`, and the README updates.

## Does it do it

Yes.

- **The new check.** `orchestrator_stranded_own_record` (`hooks/allow-repo-commands.sh`) runs last in `orchestrator_record_move`, after every #169 condition. It returns False when:
  - the session id is missing or not a string;
  - the README is a symlink, is missing, or does not name this session;
  - the classifier is missing or symlinked, or `sys.executable` is empty;
  - the classifier subprocess raises, times out (`ORCHESTRATOR_MOVE_CLASSIFIER_TIMEOUT_SECONDS`) or exits non-zero.
- **How the classifier is run.** Its path comes from the hook's own real path (`tooling`). It runs as `-B -E -s`, with stdin closed and `cwd` set to the consuming repo. `roots.legacy_record_claim` finds the legacy root from its own `AGENT_TOOLING_DIR`, so it reads the same vendored copy the hook checked. No `analysis/` import was added, and every new value is a named constant.
- **Session id.** It is threaded from `main()` (`payload.get(SESSION_FIELD)`) through `orchestrator_command_allowed`, `orchestrator_moves_own_record`, `orchestrator_git_allowed` and `orchestrator_record_move`.
- **Change in `main()`.** It now judges the move first and uses the allowlist only as the fallback. The result is the same as before: a move approved outright was always also on the allowlist.
- **Tests (H28).** All existing rows are kept. New rows:
  - O18: the session's own record with no consumer feature;
  - an ambiguous record that lists a consumer feature and an agentTooling feature;
  - O39 and O40 for a session that only the ledger names, under both profiles.

  Each new row isolates one condition:
  - O39 has a stranded README that names another session, so `names_role` is what refuses it;
  - O40 has no README;
  - O18 and the ambiguous row are refused by the classifier.

  The own-stranded-record case is still approved under both profiles, and the printed remedy still moves the record. That rerun goes through the real classifier, because the fixture's vendored copy now includes `analysis/`.
- **Gate.** `self/gate-report.txt` is green and every H28 row is `ok`.
- **`orchestrator-role.sh`.** It unsets `AGENTTOOLING_PROFILE` (line 99). That arrived through the merge of `origin/main`, so it does not appear in `origin/main...HEAD`.
- **READMEs.** `hooks/README.md`'s orchestrator git-writes row names all three conditions and the new denials. The `self/tests/README.md` H28 entry and the test header comment name the new rows.

## Fixed in this pass

None. I tried to correct one comment (the nit below), but the edit to `hooks/allow-repo-commands.sh` was refused.

## Escalated to the next round

None.

## Non-blocking notes

- **Comment overstates.** The comment in `main()` above `moves = orchestrator_moves_own_record(...)` says the move is "judged once here". That holds only when the move is approved. When the classifier refuses (O18, ambiguous), `orchestrator_command_allowed` judges the line again: once through `orchestrator_moves_own_record`, and for a bare `git mv` a third time through `orchestrator_git_allowed`. So the classifier can run up to 3 times. The worst case is 3 × 15 s, which is still under the default 60 s command-hook timeout. Suggested wording: "judged first so an approved move runs its classifier once; a denied move's line is judged again by the allowlist".
- **Fail-closed branches have no test.** No H28 row checks the classifier's own failure paths: a symlinked `analysis/roots.py` or a deleted one in the vendored copy, with an otherwise approvable own stranded record, should be the allowlist denial. The code handles both. A deleted classifier is caught twice: by the `isfile` check, and by Python's non-zero exit when it cannot open a script. Two cheap rows would pin this behaviour.

## Deviations from the brief

None
