# 100 — review: permissions-policy-inherit

Written before the build, from the design agreed on 2026-09-16, never from the
implementer's report. "No findings" is a legitimate verdict (AGENT_PLANS.md → "Review
plans"). Fix local drift in this pass; anything structural is an escalation in the verdict,
not a rewrite.

## What the feature was supposed to do

Move the permission policy that had been living in per-machine `settings.local.json`
files (and nowhere at all in this checkout) into the two channels this repo already ships
to every consuming repo, and make the same policy bind here:

1. **Approvals in the hook.** `hooks/allow-repo-commands.sh` approves the harness's own
   read-only or re-derivable entry points when the script resolves inside the project
   root, matched by basename so the rule holds in a consuming repo (`plans/gate.sh`,
   `agentTooling/check-plans.sh`, `agentTooling/analysis/report.py`) and here
   (`self/gate.sh`, `./check-plans.sh`, `analysis/report.py`): `gate.sh` with an optional
   level label, `check-plans.sh`, `bash -n <in-tree files>`, `shellcheck <in-tree files>`,
   `python3 -m py_compile <in-tree files>`, `report.py`, `capture_planning.py` only in a
   `--list-*` form, `manifest.py` only with the `get` subcommand. The interpreter flag
   `-B` is accepted. Nothing that freezes cost or moves a git ref is approved:
   `feature-start.sh`, `feature-close.sh`, `sweep.sh`, `capture_planning.py --recapture`
   and `--all`, `manifest.py set-*`/`init` all fall through to the prompt.
2. **A second deny shape in the hook.** A git command that mutates refs or history is
   denied wherever it appears in the command line, with a reason naming
   `LIFECYCLE.md` rule 2 and `feature-start.sh`: `push` with `--force`, `-f` or
   `--force-with-lease`; `reset --hard`; `clean`; `stash`; `rebase`; `worktree` with any
   subcommand but `list`; `checkout -b`/`-B`; `switch -c`/`-C`; `branch` with a positional
   or `-d`/`-D`/`-m`/`-M`. Global git options before the subcommand (`-C <path>`,
   `--git-dir=…`, `-c k=v`) are skipped, so `git -C /x worktree add` is still denied. The
   same guards as the chained-`cd` deny apply: a heredoc, a `#`, or an unbalanced quote is
   never denied.
3. **Denies in `wire-settings.py`.** The prefix-rule spellings of the same list are
   appended to `permissions.deny` beside the Edit rules, merged and never removed, and
   `--check`/`--write` report them the same way. Read-only git stays untouched:
   `git branch --show-current`, `git worktree list`, `git checkout -- <file>` are neither
   denied by rule nor approved.
4. **`--self` mode for the wiring.** `wire-settings.py --self` writes the hook path
   `${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh` and the policy deny
   `Edit(/hooks/**)` in place of `Edit(**/agentTooling/hooks/**)`. This checkout gains a
   committed `.claude/settings.json` written by it, and `self/gate.sh` records a check that
   the file is in sync (`--self --check`), so the policy cannot drift from its source.
5. **Plan numbering past 99.** `feature-start.sh`'s `--self` branch derives the next plan
   number from files matching two digits only, so once the corpus crossed `99` it handed
   this feature `100` instead of `105`, and the next feature would collide on `100`. The
   fix matches any leading digit run and sorts numerically. (This feature keeps `100`;
   the fix is for the next one.)
6. **Docs.** `hooks/README.md` (approves, denies, editing the policy), root `README.md`
   (hooks and sync-plans rows), `LIFECYCLE.md` rule 2 (one sentence: the hook enforces
   it), `self/README.md`, `self/tests/README.md`, `self/PROJECT_FACTS.md` (this checkout
   now has `.claude/settings.json`), and the sibling row wherever a touched folder's
   README describes it.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect changes in
`hooks/`, `self/tests/`, `self/gate.sh`, `feature-start.sh`, `.claude/settings.json`,
and the READMEs above. Anything outside that set needs a reason in `NOTES.md`.

## Contracts to hold it to

Read each as an assertion; check the test file asserts it and the code satisfies it.

- **Every approval widening has a test and a bypass check.** For each new entry point in
  `self/tests/allow-repo-commands.sh`: an ALLOW case for the in-tree spelling, and a
  refusal for (a) the same basename outside the root, (b) a symlink inside pointing out,
  (c) the writing form where one exists — `capture_planning.py --recapture`,
  `capture_planning.py --all`, `manifest.py … set-window-to`, `manifest.py … init`. A
  `python3 -c`, a bare `python3 <other script>`, and `bash <script>` without `-n` still
  prompt.
- **Basename matching does not widen `python3`.** `python3 analysis/report.py` approves
  only because the *script* path resolves inside the root AND its basename is in the
  new allowlist. `python3 /tmp/report.py` and `python3 ../report.py` refuse.
- **The deny never fires on a guess.** A heredoc body containing `git push --force`, a
  quoted `'git rebase'` as an argument, `echo git clean`, and an unbalanced quote are all
  NOT_DENIED, exactly as for the `cd` deny. `git branch --show-current`, `git worktree
  list`, `git push` (no force flag), `git checkout -- file`, `git reset <file>` (no
  `--hard`) are NOT_DENIED.
- **The deny reaches every scope.** `ls && git worktree add x`, `x=$(git rebase main)`,
  `git -C /abs worktree add x`, `git --git-dir=/x/.git stash` are all DENY.
- **Prefix rules and hook deny agree.** Every `Bash(...)` rule `wire-settings.py` writes
  names a command the hook also denies, and the hook denies nothing the rule list does
  not at least name in its comment. The list is one constant in each file, and each
  names the other.
- **`wire-settings.py` still never adds an allow rule**, never removes an entry, and
  reports `INVALID` on the same malformed shapes as before. `--check` on a file with the
  hook and Edit rules but no Bash rules reports `UNWIRED` naming the count of missing
  rules; `--write` then appends only those. `self/tests/hook-wiring.sh` covers the
  `--self` mode (path and policy deny differ, everything else identical) and the Bash
  rule merge.
- **This checkout's settings file is exactly what `--self --write` produces**, and the
  gate check fails if it is not. The file carries no allow rules.
- **`feature-start.sh` numbering:** with `104-x.md` present the next stem is `105`; with
  only `08-x.md` present it is `09`; with none, `01`. Assert in
  `self/tests/feature-lifecycle.sh` or a sibling — the existing test scaffolds a
  throwaway checkout.
- **Named constants** for every new list and reason string; bash 3.2 for the shell;
  `set -uo pipefail` and no `set -e` in scripts; no `cd` chained with another command
  anywhere in the diff, including test fixtures.
- **README Rule 2** where it applies: the hook README's cross-layer section names
  `.claude/settings.json` in this checkout as written by `wire-settings.py --self`, and
  the gate check as its guard.

## Verdict

Write it as the PR body will read it: what the diff does, each contract above as
holds / fixed here / escalated, and the files touched by this pass.
