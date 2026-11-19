# 04 — review: shared-hook-rules (round 4, scoped to the merge of main)

Rounds 1–3 came back clean with clean security audits, and `feature-close.sh` opened PR #143.
`main` then moved: PR #142 (`vendored-edit-ask`) merged at 9b8059a, and #143 conflicted. This
round judges the merge commit `shared-hook-rules: merge origin/main (vendored-edit-ask)`
(0caab0f) and nothing else; the runner queues a fresh security audit beside it. "No findings"
is a legitimate verdict.

## What the feature was supposed to do

Unchanged: every rule the PreToolUse hook shares with `analysis/` and the shell has one
definition, in `hooks/shared_rules.py`, with no behaviour change (`NOTES.md` rulings 1–18;
`review/complete/01-review-opus.md`).

What the merge must do: carry `vendored-edit-ask` (read `self/features/vendored-edit-ask/
NOTES.md`) into this branch whole — its consumer ask `Edit(**/agentTooling/**)` in
`POLICY_ASK_RULES` and its `RETIRED_EDIT_ASK_RULES`, exactly as `origin/main` has them —
while keeping this feature's `shared_rules` bindings, so no record-root literal is restated in
`hooks/wire-settings.py`. The coordinator's resolution rules and the delegate's ruling 19
(`NOTES.md` → "Merge with vendored-edit-ask (PR #142)") say how.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

For this round, read the merge itself: `git show --cc 0caab0f` (the combined diff: the
conflict resolutions), then `git diff 0caab0f^1 0caab0f` (what main brought into this branch)
and `git diff origin/main 0caab0f -- hooks/wire-settings.py README.md hooks/README.md
self/tests/` (how this branch's tree now differs from main in the files both features
touched). Confirm no commit after 0caab0f other than this round's own.

## Contracts to hold it to

1. **vendored-edit-ask is intact.** `POLICY_ASK_RULES` and `RETIRED_EDIT_ASK_RULES` evaluate
   to exactly `origin/main`'s strings, byte for byte; `python3 -B hooks/wire-settings.py
   --self --repo <checkout> --check` is in-sync; every vendored-edit-ask test assertion in
   `self/tests/hook-wiring.sh` is present and unweakened.
2. **shared-hook-rules is intact.** Every rule string in `wire-settings.py` that names a record
   root is built from `shared_rules` constants (none restates `self/orchestrations` or
   `plans/orchestrations`); `self/tests/shared-rules.sh` passes, and its S2 change pins main's
   tuple without weakening any other check; `grep -rn 'MIRRORS\|MIRRORED' hooks/ analysis/
   *.sh` is empty.
3. **The resolved prose is coherent and true.** The root `README.md` `hooks/` row, the
   `hooks/README.md` `shared_rules.py` and `wire-settings.py` entries, `self/tests/README.md`
   and `self/BACKLOG.md` describe the merged tree — no claim from either side that the other
   made false (e.g. "wire-settings spells the records ask from both roots"), no duplicate
   entries, no conflict markers anywhere tracked.
4. **Ruling 19** in `NOTES.md` is accurate and does not contradict rulings 7 and 15 without
   saying which it supersedes.
5. The full gate on the merged tree is green (the coordinator ran it: "all checks passed").

## Verdict
