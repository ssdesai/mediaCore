Verdict: escalated

# Review — pull-agenttooling-pr173 (round 1)

## What the batch was supposed to do

There is no spec to review against. The opening paragraph of the manifest
(`plans/features/pull-agenttooling-pr173/README.md`) still holds the template's
`<One paragraph: what this feature delivers and why the work exists. …>` text. The
"Deliberately excluded" list and the Plans table are still the template too. The review
brief says that alone makes the verdict `escalated`. There is also no `NOTES.md`, so this
review has no builder's claims to check.

From the commits, the feature is a `git subtree pull` of agentTooling
(`38d1e381 Squashed 'agentTooling/' changes from a130257f..25b332c9`, merged in
`dfa2bf32`) on top of the `feature-start` commit. Every change outside `agentTooling/` is
this feature's own manifest and its plan queue. Nothing under `src/`, `tests/`,
`fixtures/` or the repo-owned `plans/` files changed, so the `mediaCore` contract package
is untouched. The gate (`plans/gate-report.txt`, 2026-11-20T15:35:27Z) is green:
307 passed, and ruff, the fixture-idempotence check and the wheel check all pass.

## Does it do it

I can't judge this against a spec. Read as a plain vendored pull, it brings in upstream
agentTooling as one squashed subtree commit, which is the expected shape. One problem in
the pulled code is real, though. The security audit for this feature
(`plans/features/pull-agenttooling-pr173/audit-report.md`, `Verdict: escalated`) found
it, and I confirmed it by reading the code.

## Fixed in this pass

None. Everything under `agentTooling/` is vendored, and a local edit there would be
overwritten by the next `subtree pull` (`agentTooling/CLAUDE.md`). The fix has to be made
upstream in agentTooling and pulled in again.

## Escalated to the next round

1. **The spec is missing.** Fill in the manifest's opening paragraph: pull agentTooling
   up to PR #173 (`a130257f..25b332c9`), and why. Also fill in or delete its "Deliberately
   excluded" list and its Plans table. The plans list in the machine-readable fence,
   `["01-review-opus", "01-audit-opus"]`, already matches the review queue.
2. **The orchestrator's record move skips the line-length bound.** This must be fixed
   upstream in agentTooling, then pulled again.
   - **Where:** `agentTooling/hooks/allow-repo-commands.sh:5959`. `main()` calls
     `orchestrator_moves_own_record(command, …)` before `orchestrator_command_allowed`,
     and `allow`s with `ORCHESTRATOR_MOVE_REASON` when it returns true.
   - **The missing check:** the only `len(command) > ORCHESTRATOR_MAX_LINE_CHARS` check
     (`:5806`) is inside `orchestrator_command_allowed`. `orchestrator_moves_own_record`
     (`:5679`) runs `ORCHESTRATOR_HARMLESS_REDIRECT_RE.sub` and `orchestrator_words` on a
     line of any length.
   - **Effect:** a `git mv agentTooling/self/orchestrations/<slug> plans/orchestrations/<slug>`
     line padded past 20000 characters is now allowed. Before this pull it was denied
     unread (audit cases M7, M7b, M8, M8b, B20001). Under the owner's no-deny-to-allow
     ruling, that counts as a regression.
   - **Fix:** put the same length check at the top of `orchestrator_moves_own_record`, or
     in `main()` before either judge runs.
   - **Missing tests:** in `agentTooling/self/tests/hook-orchestrator-role.sh`, one case at
     exactly 20000 characters (allow) and one at 20001 (deny).
3. **Pre-existing gaps the audit filed as non-blocking**, for the upstream backlog rather
   than this round:
   - The move's classifier `analysis/roots.py` is trusted as a working-tree file (M12).
   - Only the last role fence of a record is classified (M5c).

## Deviations from the brief

- The brief's spec (the manifest's opening paragraph and its "Deliberately excluded"
  list) is the unfilled template, so I reviewed the diff against the commit history and
  the security audit instead of a spec.
- `NOTES.md` does not exist, so I could not check the builder's claims.
