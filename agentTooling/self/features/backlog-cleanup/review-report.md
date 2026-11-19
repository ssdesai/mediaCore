Verdict: clean

# Review — backlog-cleanup

## What the batch was supposed to do

Bring `self/BACKLOG.md` up to date with the 2026-11-16/17 work, using the owner-approved list in `self/features/backlog-cleanup/README.md`:
- drop the closed entries (the `claude-sonnet-5-5` rates repair, on the owner's ruling, and the "directory names" note);
- trim the audit round-cap entry and the untokenizable-line entry down to what is still open;
- merge the three orchestrator-role entries into one entry that holds four gaps;
- file eight new entries for friction the 2026-11-17 wave hit.

No code changes.

## Does it do it

Yes.

**Scope.** Outside `self/features/backlog-cleanup/`, the diff (`git diff origin/main...HEAD`) touches `self/BACKLOG.md` and nothing else.

**Every cited fact checked against the code on this tree:**
- `orchestration-start.sh`:
  - Its options are `--session`, `--coordinator` and `--from`. There is no `--branch`.
  - `held_feature` uses `git ls-files` and also reads the consuming repo's `plans/features/` (through `$TOPLEVEL`).
  - The whole guard sits under `[[ -n "$TOPLEVEL" ]]`, so it is skipped without a message when no repository is found.
  - It refuses a stranded record with `LEGACY_RECORD_REFUSAL`, which names a `git mv` (`hooks/shared_rules.py`).
- The orchestrator allowlist in `hooks/allow-repo-commands.sh`:
  - `ORCHESTRATOR_GIT_READ` / `ORCHESTRATOR_GIT_EXACT` hold no `mv`, `rm`, `switch`, `checkout -b` or `clone`.
  - `ORCHESTRATOR_READERS` has no `mv`.
  - Its `git add` accepts only regular files that are not symlinks.
- `hooks/orchestrator_role.py` → `record_roots` / `record_bases`: matches what the entry says.
- The hook runs only for Bash and Agent calls: `MATCHED_TOOL = "Bash"`, `AGENT_TOOL = "Agent"`, and the only `.claude/settings.json` matchers are `Bash` and `Agent`.
- `self/tests/orchestrator-role.sh` V1–V3 test only `self/features/`.
- `analysis/report.py`:
  - `compute_orchestration_report` reads `("cost", "total")` from each entry's `report.json`.
  - `UNPRICED_NEEDS_CHECKOUT` and `--checkout` exist.
- `forge.sh pr-edit` sends only `body`.
- `harness/publish.sh` opens its PR with the title `<name>: results, run <N>`.
- `harness/new-experiment.sh:93` holds the camelCase check. `harness/README.md` states camelCase for program names and branch stems, but not for the experiment name.
- `harness_worktree_path` is `<repo>-<branch>`.
- `harness/run.sh` `do_rework` passes `--model "$HARNESS_MODEL"`, and so does the rework in `program-stages.sh`. Review uses `HARNESS_REVIEW_MODEL`.
- `harness/templates/review-preamble.md` contains `@@TREE@@` and `@@BRANCH@@`.
- `--list-sessions --unclaimed` exists in `capture_planning.py`.
- The test lists and constants named in the untokenizable-line entry exist where it says:
  - `BASH_PARSED_PROMPT`, `UNLEXED_GIT_DENY` and `BASH_REFUSED_GIT_DENY` are in `self/tests/allow-repo-commands.sh`.
  - `BASH_SYNTAX_ENV`, `bash_refuses`, `does_not_tokenize` and `never_judged` are in the hook.
  - `BASH_PARSED_PROMPT` contains the old (a) example, `git push -f origin y⏎echo $'\''`, as a prompt.

**Dropped entries:**
- Old (a) of the untokenizable-line entry is covered by the entry after it, "The deny side does not follow a substitution's scope", which names the ANSI-C and quoted-substitution spellings.
- The three orchestrator-role entries are all inside the merged four-gap entry, with their assertions kept word for word.
- The `delegate-cost-claims` note is kept.
- The sonnet-5-5 rates entry was dropped on the owner's ruling, as the spec says.

**Shape.** All eight new entries have a bold one-sentence title, what is true now and where, a fix, an `Assertion:` and a `Raised by`.

**NOTES.md.** Rulings 1–8 match the diff and the code.

**Gate.** `self/gate-report.txt` ends `all checks passed`. Two lines in it are not green; neither touches BACKLOG prose:
- the "pricing rate history is current" check exited 1;
- one harness smoke check was skipped because the history is shallow.

## Fixed in this pass

Nothing.

## Escalated

Nothing.

**Observation, not a finding.** The spec says the "directory names" entry was closed by the recent work. It was not: `Path(cwd).name` is still in `analysis/capture_planning.py:2056`. But that entry was a note that needed no action ("Assertion: none needed unless one of them starts being compared"), and `cwd_name` is still only displayed, never compared. Dropping it loses no open defect. NOTES.md just has no ruling for it.
