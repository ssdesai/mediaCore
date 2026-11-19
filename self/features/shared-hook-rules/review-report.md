Verdict: clean

# Review: shared-hook-rules, round 4 (the merge of origin/main / vendored-edit-ask)

## What this round was supposed to do

Rounds 1–3 came back clean. `main` then merged PR #142 (`vendored-edit-ask`), which made
#143 conflict. This round reviews only the merge commit 0caab0f. It had to bring in
vendored-edit-ask unchanged and keep this feature's `shared_rules` bindings, so that
`hooks/wire-settings.py` writes out no record-root path literally.

## Does it?

Yes. I checked each of the plan's contracts:

1. **vendored-edit-ask is intact.** I loaded `wire-settings.py` from HEAD and from `origin/main`
   and compared the values. `POLICY_ASK_RULES`, `RETIRED_EDIT_ASK_RULES`,
   `SELF_POLICY_ASK_RULES` and `RETIRED_EDIT_DENY_RULES` are equal in both:
   `('Edit(**/agentTooling/**)', 'Edit(**/plans/orchestrations/**)')` and
   `('Edit(**/agentTooling/hooks/**)', 'Edit(**/agentTooling/self/orchestrations/**)')`.
   `self/tests/hook-wiring.sh` is byte-identical to main's, so none of its assertions were
   dropped or weakened. The gate's settings `--check` and hook-wiring both pass.
2. **shared-hook-rules is intact.** The only rule strings that name a record root are built
   from `shared_rules.ORCHESTRATIONS_CONSUMER_REL` and `ORCHESTRATIONS_SELF_REL`. The other
   places `orchestrations` appears in `wire-settings.py` are the docstring and comments. S2 in
   `self/tests/shared-rules.sh` now checks main's two tuples literally and also checks that each
   is built from the shared root. The other S2 checks and S1/S3–S6 are unchanged. Searching for
   `MIRRORS`/`MIRRORED` finds nothing, and `shared-rules` passes.
3. **The resolved prose is correct.** I read the root `README.md` `hooks/` row, the
   `hooks/README.md` `shared_rules.py` entry, the ask-rule section and the retired-rule list,
   the `self/tests/README.md` `shared-rules.sh` entry and the `self/BACKLOG.md` line. Each one
   describes the merged tree. Nothing says the ask is still spelled "from both roots", no entry
   appears twice, and no tracked file has conflict markers.
4. **Ruling 19** is accurate. It names rulings 7 and 15 and says how they now read: only the
   consumer root is in `POLICY_ASK_RULES`, and the retired legacy ask is built from the self root
   and pinned by S2.
5. **Gate**: `self/gate-report.txt` ends with `all checks passed` and reports no skipped checks.
   The merge commit is HEAD. The only commit after it will be this round's own.

## Fixed in this pass

- `self/tests/shared-rules.sh`: changed the S2 label "POLICY_ASK_RULES is what it always was" to
  "… is the exact strings vendored-edit-ask set". The old label was no longer true, because
  vendored-edit-ask changed that tuple. I re-ran the test and it passes.

## Not fixed (cosmetic, does not need another round)

- `hooks/README.md` around line 189: in the `shared_rules.py` entry, the merge left one line much
  longer than the wrapped lines around it (`…asks for less); \`allow-repo-commands.sh\`
  (guarded, …`). It should break before `` `allow-repo-commands.sh` ``. Edits under `hooks/`
  need approval under `--self` and this pass had none, so it is left for whoever next edits that
  file.

## Escalated to the next round

None.
