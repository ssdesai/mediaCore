# 01 — review: policy-module

Written before the build, from the manifest (`self/features/policy-module/README.md`) and
the design (`self/DESIGN-2026-09-17-policy-module.md`), never from the implementer's
report. "No findings" is a legitimate verdict. Fix local drift in this pass; anything
structural is an escalation, and an escalated report is round 2's brief. Begin your
report with the `Verdict:` line the prompt asks for. This feature's whole scope is
`hooks/`, so you may edit there — through the Edit tool; if the rule refuses you, say so
in the report and escalate the fix instead of shelling a write around it.

## What the feature was supposed to do

The git policy written once, as data, and the six gaps and three stale names around it
closed. The base is `lifecycle-records-and-numbering`; the diff to read is
`git diff lifecycle-records-and-numbering...HEAD`.

1. **One table** (P1). `hooks/policy.py` holds `GIT_ALWAYS_MUTATING`, the flag sets,
   `GIT_WORKTREE_SUBCOMMANDS` with READ_ONLY/MUTATING marks, and `bash_deny_rules()`
   rendering the prefix rules in the design's fixed order. `allow-repo-commands.sh`
   imports the constants for `git_mutates`; `wire-settings.py` calls the renderer and
   has no literal tuple. A test asserts the rendering names every MUTATING worktree
   subcommand and every branch flag in the table.
2. **The drift check** (P2). `wire-settings.py --self --check` is byte-for-byte against
   a fresh `--self --write` from empty; consumers keep the merge. `.claude/settings.json`
   is regenerated and the gate passes on it.
3. **The ask rule** (P3). The `hooks/` Edit rule is in `permissions.ask`, at any depth,
   in both spellings; the `deny` for `hooks/` is gone; `wire-settings.py` merges `ask`
   the way it merges `deny`.
4. **Opaque = unreadable** (P4). A line that does not tokenize is the seventh opaque
   shape, denied naming the quote, counted toward the escalation.
5. **Scratch arguments** (P5). Arguments after a scratch script are approved when each
   is confined to the project root or the scratch root; a flag before the script prompts.
6. **Bare names and `--list`** (P6). `gate.sh`/`check-plans.sh` need a directory
   component; `git branch --list <pattern>` is a listing.
7. **Names, the reason, the record** (P7). No `sweep.sh` in `hooks/` or the test; the
   git reason names `feature-close.sh` as the way out before the merge; READMEs, notes,
   checkpoint, eight backlog entries removed.

Not in this feature: the vendored `agentTooling/.claude/settings.json`, opaque shapes
beyond the seven, other repos' settings files, the budget, `git stash list`, anything
outside `hooks/` and its tests and docs.

## The diff

Base is `lifecycle-records-and-numbering`. `git diff lifecycle-records-and-numbering...HEAD
--stat`, then the full diff. Expect: a new `hooks/policy.py`, `hooks/allow-repo-commands.sh`,
`hooks/wire-settings.py`, `hooks/README.md`, `.claude/settings.json`,
`self/tests/allow-repo-commands.sh`, `self/tests/hook-wiring.sh`,
`self/tests/hook-escalation.sh`, a new `self/tests/policy-table.sh` (or a phase in
`hook-wiring.sh` — the notes say which), `self/tests/README.md`, `self/gate.sh`, root
`README.md`'s `hooks/` row, `self/README.md`'s gate row and a row for the design doc,
`self/BACKLOG.md`, `LIFECYCLE.md` only if it quoted the reason, and this feature's
`NOTES.md`/`CHECKPOINT.md`/`timing.jsonl`. Anything else that moved needs a ruling in
`NOTES.md` or is a finding.

## Contracts to hold it to

Read each as an assertion; check a test asserts it and the code satisfies it.

- **One source.** `grep -n "GIT_ALWAYS_MUTATING\|GIT_WORKTREE\|BASH_DENY_RULES" hooks/*.py
  hooks/allow-repo-commands.sh` finds each git constant defined once, in `policy.py`,
  and `BASH_DENY_RULES` defined nowhere as a literal tuple. Both scripts insert their
  own directory on `sys.path` before the import (the hook runs from a `hooks/` that may
  be vendored under `agentTooling/`).
- **The twins cannot drift.** The table test iterates the table — not a retyped list —
  and fails if any MUTATING worktree subcommand or any branch mutating flag has no
  rule. Delete one entry from `bash_deny_rules()`'s order by hand in your head: would the
  test catch it? If it compares against a second hand-typed list, that is the old bug.
- **Byte-for-byte under `--self`.** With the committed `.claude/settings.json`,
  `python3 -B hooks/wire-settings.py --self --repo . --check` exits 0; append one allow
  rule to a copy in a temp dir and the check fails naming that entry. A consuming-repo
  layout with an extra hand entry still passes `--check` without `--self`. The
  `hook-wiring.sh` test covers both.
- **The ask rule is live.** `.claude/settings.json` has `permissions.ask` with
  `Edit(**/hooks/**)` and `Edit(/hooks/**)`, and no `Edit(/hooks/**)` under `deny`; the
  vendored spelling is `Edit(**/agentTooling/hooks/**)`. `hooks/README.md` states the
  headless refusal and the `bypassPermissions` limit.
- **Seventh shape.** `cat 'x` and `git rebase 'main` are denied with a reason naming the
  quote and advance the escalation counter (a `hook-escalation.sh` case or a note saying
  why not); every ALLOW / NOT_DENIED / GIT_NOT_DENIED / ASSIGN_NOT_DENIED case that was
  there before is still there and still passes; a heredoc line and a `#` line still
  prompt.
- **Scratch arguments.** `bash <scratch>/x.sh src/a.py` approved, `bash <scratch>/x.sh
  <scratch>/in.txt` approved, `bash <scratch>/x.sh /etc/passwd` prompts, `bash -x
  <scratch>/x.sh` prompts, `bash <scratch>/x.sh ../x` prompts. A symlink out of either
  root is not confined.
- **Bare names.** `check-plans.sh --self x` prompts; `./check-plans.sh --self x` and
  `agentTooling/check-plans.sh --self x` approve; same for `gate.sh`.
- **`--list`.** `git branch --list 'feat*'` and `git branch -l 'feat*'` not denied;
  `git branch new` still denied; `git branch --list` followed by `-d x` still denied.
- **The reason.** `GIT_DENY_REASON` names `LIFECYCLE`, rule 2, `feature-start.sh` and
  `feature-close.sh`, and says the close runs from the worktree before the merge. No
  `GIT_REASON_ABSENT`. No `sweep.sh` anywhere under `hooks/` or in the test file.
- **Docs.** `hooks/README.md`: a `policy.py` entry (Rule 1 names the table's constants,
  Rule 2 names the sibling-path import and the settings file as the rendering's
  consumer); § "The git shape" reversed; § "The deny rules" describes the ask; § "What
  `wire-settings.py` will and won't touch" says which mode is byte-for-byte; "Editing
  the policy" points at `policy.py` for the git constants. `self/README.md` gate row and
  design-doc row. Root `README.md` `hooks/` row. `self/tests/README.md` for every test
  touched.
- **Style.** Named constants; Python stdlib only; bash 3.2 in the tests; no chained
  `cd`; `.claude/settings.json` written by the script, not by hand.
- **Exclusions named.** Every deviation from the manifest or design has a ruling in
  `NOTES.md`; the eight backlog entries the manifest names are gone from
  `self/BACKLOG.md` and the two it keeps are still there.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the feature was supposed to do, whether it does it, what you fixed, what you
escalated (with the assertion that would catch it), and the files this pass touched.
