Verdict: escalated

# Review — pull-agenttooling-pr169

## What the batch was supposed to do

Nothing I can review against. The spec should be the opening paragraph of the manifest,
`plans/features/pull-agenttooling-pr169/README.md`. It is still the template placeholder
(`<One paragraph: what this feature delivers and why the work exists. …>`). The
"Deliberately excluded" list and the title (`# <Feature title>`) are placeholders too.
The review plan says that with no spec the verdict is `escalated`. There is also no
`NOTES.md` for this feature, so I have no builder's claims to check either.

The commits show what the work was: a hand-built `git subtree pull` of `agentTooling/`
(`114e7ea3..a130257f`, upstream PR 169). After the pull, it commits the `sync-plans`
output and moves `plans/pr.sh` up to template-version 8.

## What the diff contains, as read

I read only the repo-owned files outside the vendored subtree. `agentTooling/` is
upstream code and is reviewed there.

- `.claude/settings.json`: a `PreToolUse` hook on `Agent` points at
  `allow-repo-commands.sh`, which enforces the brief-header rule
  (CONVENTIONS.md → "Delegate briefs"). The `ask` rule widens from
  `agentTooling/hooks/**` to `agentTooling/**`, and a new `plans/orchestrations/**`
  rule is added. These match the pulled CONVENTIONS.md and `plans/README.md`.
- `plans/pr.sh`: identical, byte for byte, to `agentTooling/templates/plans/pr.sh`
  (empty `git diff --no-index`). That means it took no repo-local changes, so none were
  lost. It passes an optional third word (the title) to `forge.sh pr-edit`, and the
  pulled `forge.sh` accepts that (`agentTooling/forge.sh:151-152`).
- `plans/README.md`, `plans/ORCHESTRATOR_BRIEF.md`, `plans/ORCHESTRATOR_SESSION_BRIEF.md`
  and `plans/features/TEMPLATE.md` are generated sync output. They now list the new
  `orchestrations/` folder and `ORCHESTRATOR_SESSION_BRIEF.md`.
- Nothing under `src/` or `tests/` changed, so the mediaCore contract in INTEGRATION.md
  is untouched.

The gate report (`plans/gate-report.txt`, 2026-11-19T18:35:54Z) is green: install, lint,
fixture idempotence, wheel contents and 307 tests passed. No checks were skipped.

Apart from the missing spec, reading the repo-owned diff found no defects.

## Fixed in this pass

None.

## Escalated to the next round

1. **Write the spec in the manifest.** In `plans/features/pull-agenttooling-pr169/README.md`,
   replace the title, the opening paragraph and the "Deliberately excluded" list with real
   text. Suggested content: "Pull agentTooling PR 169 (`114e7ea3..a130257f`) into the
   subtree, commit the regenerated `plans/` sync output, and merge `plans/pr.sh` to
   template-version 8. No changes to `src/` or `tests/`." Then fill in the Plans table,
   and delete the Levels and Contracts sections, as the template says to for a
   single-level batch. Re-run the review once that is done. I found nothing else to fix.

## Deviations from the brief

None
