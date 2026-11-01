Verdict: clean

# Review — claude-md-chain

## What the batch was supposed to do

The manifest (`self/features/claude-md-chain/README.md`) describes four changes:

- Trim `CONVENTIONS.md` to the rules that still do work. The shell section keeps its one rule and the full rewrite table, and the reasoning stays in `hooks/README.md`. The README section drops the ban on using Grep/Glob for discovery and the per-read stop conditions. The pointer to `plans/PROJECT_FACTS.md` before authoring a plan moves into `CONVENTIONS.md`.
- Correct the "conventions load twice" and "a `--self` executor never sees the root `CLAUDE.md`" claims in `CLAUDE.md` and `RUNNER.md`, using what was measured.
- Stop `AGENT_PLANS.md` from describing `/fast` as a cheaper model.
- Retire the `Edit(**/agentTooling/hooks/**)` deny rule in `wire-settings.py`. That rule sat beside the ask rule that replaced it, and the deny always won.

The excluded items are untouched: no consumer `CLAUDE.md` was edited, no README-size rule was added, the `CLAUDE.md` file was not relocated, and no consumer settings file was changed by hand.

## Whether it does it

It does. Each contract in the brief was checked against `git diff origin/main...HEAD`:

- **`CONVENTIONS.md`**
  - Unchanged: the File Access bullets, every rewrite-table row (no hunk touches the table), "Closing a feature", "Generated READMEs", README Rules 1 and 2 with their examples, and "Named constants" with its example block.
  - "Keeping READMEs up to date" is now one paragraph. It keeps every step: the touched folders, verifying each README, the generated-README route and the parent check.
  - Removed: the Grep/Glob ban and the three-file stop condition.
  - Added: `plans/PROJECT_FACTS.md` and `self/PROJECT_FACTS.md` are named as what to read before authoring a plan.
  - Dropped prose (the extra examples, the "one of four rewrites" summary, the exemption's heredoc-body caveat) is still covered by table rows and enforced by the hook.
- **`CLAUDE.md` and `RUNNER.md` → "Self-hosted mode"** now say what NOTES.md measured: an import that is already loaded is loaded once, `agentTooling/CLAUDE.md` loads lazily, and an executor sees the root `CLAUDE.md` like any ancestor's. A repo-wide grep finds no leftover "loads twice", "never sees" or "no test suite" phrasing.
- **`AGENT_PLANS.md` → "Routing for cost"** offers only Sonnet as the cheaper option and says outright that `/fast` is Opus at a higher rate.
- **`hooks/wire-settings.py`**
  - `RETIRED_EDIT_DENY_RULES = ("Edit(**/agentTooling/hooks/**)",)` is a named constant.
  - It is added to the gap tuple, `apply_gaps` removes it in place alongside the retired Bash denies, and `describe_changes` reports `N retired Edit deny rule(s)`.
  - The module docstring now says "three kinds" of removal.
- **The test** is the `retired-edit` case in `self/tests/hook-wiring.sh`. It asserts:
  - `--check` reports `UNWIRED` with `1 retired Edit deny rule(s) (` and no other gap;
  - `--write` leaves `deny == ALL_DENY` and `ask == ASK`;
  - the shared loop's "second write reports kept, file byte-identical" check also runs on it;
  - the shared "no retired rule is left" and "repo's own rules kept" checks now cover the retired Edit rule.
- **`--self` output:** the generated file is not in the diff, and the gate's settings check reports `in-sync`.
- **Gate:** `self/gate-report.txt` (02:03Z) ends with `all checks passed`, and `hook-wiring: all checks passed` is in it. The only commit after the gate run (02:12Z) changes `NOTES.md` alone.
- **READMEs**
  - Updated: the root `README.md` entries for `CONVENTIONS.md`, `sync-plans.sh` and `hooks/`.
  - Updated in `hooks/README.md`: "The deny rules" (the Edit subsection) and "What `wire-settings.py` will and won't touch" ("three kinds").
  - Updated: the `self/README.md` and `self/tests/README.md` entries for `hook-wiring.sh` ("thirty-one", plus the new case).
  - Updated: the install section's root-`CLAUDE.md` example now says plans, branches, the lifecycle and CLI references do not belong in that file.
- **NOTES.md** holds up. Every ruling it lists is in the diff, and "Left undone" (the consumers' root files and the README-entry redesign) is not half-done anywhere.

## Fixed in this pass

Nothing needed fixing.

## Escalated to the next round

None. No findings.
