Verdict: clean

# Review — pull-agenttooling-pr104

## What the batch was supposed to do

The manifest (`plans/features/pull-agenttooling-pr104/README.md`) describes four changes:

- Pull agentTooling PR 104 (`claude-md-chain`, split `58da731`) with `update.sh`.
- Let the sync remove the retired `Edit(**/agentTooling/hooks/**)` deny rule from
  `.claude/settings.json` and keep the ask rule for the same path.
- In root `CLAUDE.md`, add `original_year` to the Rule 1 `Release` field list.
- In root `CLAUDE.md`, delete the "Branch naming" and "Delegated plan execution" sections.

The manifest excludes one thing: re-auditing `plans/PROJECT_FACTS.md` and the README
field lists.

## Does it do it

Yes.

- **The pull:** the vendored `agentTooling/` tree matches the squash commit `1dc9b44`
  exactly (`git diff 1dc9b44: HEAD:agentTooling` is empty). There are no local edits on
  top of upstream. The upstream change to `wire-settings.py` (`RETIRED_EDIT_DENY_RULES`)
  comes with its own `hook-wiring.sh` case (`retired-edit`), and its README entries
  (`hooks/README.md`, `agentTooling/README.md`, `self/tests/README.md`) were updated
  with it.
- **Settings:** `.claude/settings.json` loses the deny line and nothing else. The ask rule
  `Edit(**/agentTooling/hooks/**)` is still in `permissions.ask`.
- **Root `CLAUDE.md` field list:** it now matches `src/mediacore/release.py` field for
  field and in order. `original_year` sits between `released` and `country`.
- **Deleted sections:** both are gone. The new `CONVENTIONS.md` preamble carries the
  pointer to `PROJECT_FACTS.md`.
- **Gate:** `plans/gate-report.txt` shows every check green: install, lint, fixture
  idempotence, wheel, and tests (307 passed). No check was skipped.
- **NOTES.md:** this is a hand build and there is no `NOTES.md`, so there were no
  builder's claims to check.

## Fixed in this pass

Deleting the "Branch naming" section left two documents still stating the old rule:

- **`plans/PROJECT_FACTS.md`** (Conventions and gotchas) still said "Branches are bare
  camelCase, no prefix (see `CLAUDE.md`)". That pointed at the deleted section, and the
  rule contradicts the kebab-case slug that `LIFECYCLE.md` requires and `feature-start.sh`
  enforces. Every plan author reads this file. I rewrote the line to say:
  - the branch is the feature's kebab-case slug, cut by `feature-start.sh`;
  - in a cloud container, it is the session's assigned `claude/…` branch.

  The exclusion covers re-auditing this file. This was a reference the batch itself left
  pointing at nothing, so I fixed it.
- **`INTEGRATION.md` §12** said each work package (WP) runs "on a bare camelCase branch".
  It now says "on the branch `agentTooling/feature-start.sh` cuts for it".

## Escalated to the next round

None.
