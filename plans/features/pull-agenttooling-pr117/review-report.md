Verdict: clean

# Review: pull-agenttooling-pr117

## What the batch was supposed to do

Bring mediaCore's vendored `agentTooling/` up to agentTooling main as of PR 117's merge
(split sha `0e28a4caa042cd0626e9352732e81088318054c7`) using `agentTooling/update.sh`
(`git subtree pull --squash`). Then commit what `sync-plans.sh` re-synced, and touch
nothing else: no hand edits under `agentTooling/` or `.claude/`, and no change to the
`plans/` files this repo owns.

## Does it do it

Yes. Each claim below was checked against the diff (`git diff origin/main...HEAD`),
not against the builder's account of it:

- **The upstream range and nothing else.** Squash commit `85ae946` records
  `git-subtree-split: 0e28a4caa042cd0626e9352732e81088318054c7`, and its log tops out at
  `Merge pull request #117 … harness-same-repo`. I compared the squash commit's tree with
  the `agentTooling/` tree in merge `b766dcd` and found no difference. No later commit
  touches `agentTooling/` (`git diff --stat b766dcd HEAD`), so nothing under it was edited
  by hand.
- **Sync output committed.** Commit `5cc9384` holds the whole sync output:
  - `plans/README.md` gains a new `ORCHESTRATOR_BRIEF.md` entry.
  - `plans/features/TEMPLATE.md` gains the `orchestration` field, both in the fence and
    in the prose.
  - `plans/ORCHESTRATOR_BRIEF.md` is new and matches `agentTooling/templates/plans/ORCHESTRATOR_BRIEF.md`
    exactly.
  - `.claude/settings.json` has exactly one change: the `Edit(**/agentTooling/hooks/**)`
    deny rule is removed. That rule is the one listed in `wire-settings.py`'s
    `RETIRED_EDIT_DENY_RULES`. Its replacement, an ask rule for the same path, is still
    in place.

  `agentTooling/sync-plans.sh --check` reports everything `in-sync`.
- **Repo-owned `plans/` files untouched.** The diff does not touch `PROJECT_FACTS.md`,
  `BACKLOG.md`, `gate.sh`, `pr.sh` or any other repo-owned file. The only other files it
  changes are this feature's own manifest and review brief.
- **Gate.** `plans/gate-report.txt` (level `final`) is green on every check: install,
  lint, fixture idempotent, wheel contains fixture, and tests (307 passed). No check was
  skipped.
- **Manifest.** The opening paragraph names agentTooling PR 117, the split sha, the
  `fragile` chain line and the clean pull. The "Deliberately excluded" list matches what
  the diff does.
- **Same-repo rule.** mediaCore has no harness fixtures, so the rule changes nothing
  here.
- **READMEs.** `plans/README.md` is generated, and the sync updated it to list the new
  `ORCHESTRATOR_BRIEF.md`. No other folder outside `agentTooling/` gained or lost files.
  `README.md`, `INTEGRATION.md`, `CLAUDE.md` and `PROJECT_FACTS.md` contain no reference
  to the old agentTooling version.
- **NOTES.md.** This feature has none, which is normal for a hand-built pull. There are
  no claims to check.

## Fixed in this pass

None.

## Escalated to the next round

None.
