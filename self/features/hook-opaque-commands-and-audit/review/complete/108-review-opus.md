# 108 — review: hook-opaque-commands-and-audit

Written before the build, from the design settled with the user on 2026-09-17 (recorded
in this feature's manifest and `NOTES.md`), never from the implementer's report. "No
findings" is a legitimate verdict (AGENT_PLANS.md → "Review plans"). Fix local drift in
this pass; anything structural is an escalation in the verdict. The policy denies Edit
under `hooks/` at the project root — in this worktree the rule is anchored at the primary
checkout and does not reach the worktree's copy (see `start-procedure-and-routing`
`NOTES.md` ruling 6), so a hook fix here is permitted; escalate anything you are not sure
of.

## What the feature was supposed to do

`hooks/allow-repo-commands.sh` approves what it can read and denies three shapes whose fix
is a substitution. Everything it *cannot* read — a heredoc, a `$(…)` in a path, code
handed to an interpreter as a string — falls through to the permission prompt, so the
human pays a prompt and the model learns nothing. This feature makes the hook **demand a
rewrite first and escalate to the human only after the model has tried**, and it audits
the hook's approval analysis for bypasses while it is open.

1. **The opaque-command deny.** A Bash command the hook's own analysis cannot read is
   denied with a reason naming the rewrite. "Cannot read" is one category, built from the
   analysis's existing structural refusals (a `$`, backtick, `<` or `>` outside single
   quotes; a line break; a `#`; an unbalanced quote; a token that will not tokenize) plus
   these shapes, each of which hides code from any reader of the command line:
   - a heredoc feeding anything but `cat` (`python3 - <<'EOF'`, `bash <<EOF`);
   - code as a string: `python3 -c`, `bash -c`, `sh -c`, `node -e`, `perl -e`, `eval`,
     including behind `xargs` and `find -exec`;
   - a pipe into an interpreter with no script file (`… | sh`, `… | python3`);
   - a program decided at run time (`$CMD …`, `$(which x) …`);
   - a `$(…)` inside a word that is a path (contains `/`);
   - a one-line `for`/`while`/`if` compound.
   The reason says the same thing for all of them: write the script to the scratchpad
   with the Write tool and run it by name; or use the Read/Grep tool; or inline the
   literal. **Exempt**: `git commit -m "$(cat <<'EOF' … EOF)"` and the general
   `$(cat <<…)` inside a quoted argument (a heredoc feeding `cat` is a literal string,
   the shape Claude Code itself uses for commit messages); `x=$(cd dir && pwd)` and a
   `$(…)` that is a whole argument rather than part of a path.
2. **Escalation after N rewrites.** The hook keeps a per-session counter (keyed by the
   payload's `session_id`; a subagent's payload is distinguished from its parent's if the
   payload carries a field that does so — establish which, record it). The first
   `OPAQUE_REWRITE_ATTEMPTS` (= 2) opaque commands in a row are denied with the rewrite
   reason; the next returns `permissionDecision: "ask"` with a reason saying the command
   is still unreadable after N rewrites and is the human's call. Any Bash command the
   analysis *can* read resets the counter, whether it approves or not. The state file
   lives under the user's temp dir (an explicit template under `$TMPDIR`, per
   `self/PROJECT_FACTS.md`), one file per session, and a missing or corrupt state file
   is treated as zero — never a crash, never a deny.
3. **Headless runners.** `plan-runner-lib.sh` exports `AGENTTOOLING_HEADLESS=1` and
   `AGENTTOOLING_SCRATCH=<mktemp -d under $TMPDIR>` into the `claude -p` it launches (one
   place, where `claude -p` is invoked). With `AGENTTOOLING_HEADLESS` set the escalation
   step prints **nothing** instead of `ask` — nobody can answer, and falling through lets
   the runner's own non-interactive policy decide. A script under `AGENTTOOLING_SCRATCH`
   run by name (`bash <scratch>/x.sh`, `python3 [-B] <scratch>/x.py`) is approved by the
   analysis like the harness's own entry points, resolved through symlinks; the same
   basename anywhere else is not. The executor prompt templates in `plan-runner-lib.sh`
   (or wherever the runners compose the brief) name the scratch directory in one line.
4. **The security audit.** Red-team the approval analysis as an attacker who can type any
   Bash command and wants a *write, exec or read outside the root* approved without a
   prompt. Cover at least: every `READ_ONLY_PROGRAMS` entry's flags for exec/write/
   follow (`--files-from`, `-exec`, `-execdir`, `-ok`, `--pre`, `-o`, `-w`, `--output`,
   `-f` as a file source), `sed` script grammar edge cases (`e` command, `w`, `W`, `r`,
   newline in script), `git` read-only subcommands with exec-through config
   (`-c core.pager=…`, `-c diff.external=…`, `--exec-path`, `-c core.sshCommand`,
   `git log --format` with `%x` escapes, `git grep --open-files-in-pager`),
   `python3 -m py_compile` with a path that is a symlink out, brace and glob tricks not in
   the existing table, `xargs`/`find` exec paths, process substitution `<(…)`, `\` line
   continuation, an env prefix that changes program behaviour (`PAGER=… git log`,
   `GIT_DIR=`, `PYTHONPATH=`, `LD_PRELOAD=`, `IFS=`), `--` handling, and NUL/unicode
   look-alikes. Every bypass found is closed in the hook and asserted in
   `self/tests/allow-repo-commands.sh`; every one considered and *not* a bypass is a row
   in `hooks/README.md` → "What the audit found and closed" or "Accepted limits" — the
   table is the record. Also audit `wire-settings.py`'s deny rules for a shape the hook
   denies that the prefix list misses (a doc note, not a change, if unfixable).
5. **The git-shape reason** in the hook names `feature-close.sh` as "the way out". Under
   the design that is retiring (`self/DESIGN-2026-09-16-…` §3.1, §3.2): teardown is the
   next `feature-start.sh`'s prune. Reword the reason to name `feature-start.sh` alone
   and update the matching test string.
6. **Docs.** `hooks/README.md` (a new "The opaque shape" section: what is denied, the
   exemptions, the counter, `ask`, the headless fall-through, the scratch entry point;
   the audit tables), `CONVENTIONS.md` § Shell commands (the prose that said heredocs and
   `$(…)` "stay prose" now says they are denied and where the rewrite goes),
   `RUNNER.md` (the two env vars the runners export, README Rule 2), `self/tests/README.md`.

Not in this feature: any change to `feature-*.sh`, `run-review.sh`, `analysis/`,
`pr.sh`, the lifecycle docs — `capture-on-branch` is in flight on those. Do not touch
`self/tests/feature-lifecycle.sh`.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect changes in
`hooks/allow-repo-commands.sh`, `hooks/README.md`, `hooks/wire-settings.py` (only if a
deny rule moved), `plan-runner-lib.sh` (the two exports and the brief line), `RUNNER.md`,
`CONVENTIONS.md`, `self/tests/allow-repo-commands.sh`, a new `self/tests/hook-escalation.sh`,
`self/tests/README.md`, and this feature's directory.

## Contracts to hold it to

Read each as an assertion; check a test asserts it and the code satisfies it.

- **Each opaque shape is DENY with the rewrite reason**, one case per shape in §1; each
  exemption is NOT_DENIED (the commit-message heredoc, `x=$(cd dir && pwd)`, a bare
  `$(…)` argument, a plain `cat <<EOF`).
- **The readable commands are unchanged.** Every existing DENY / NOT_DENIED / APPROVE /
  REFUSE case in `self/tests/allow-repo-commands.sh` still holds; a readable command
  the analysis refuses (e.g. `rm -rf x`) still prints nothing — it is *refused*, not
  *opaque*, and must not count toward the escalation.
- **Escalation sequence.** In `hook-escalation.sh`, with `TMPDIR` redirected: opaque,
  opaque → both `deny`; third → `ask` with the "after 2 rewrites" reason; a readable
  command between them resets to `deny`; two `session_id`s count independently; a
  corrupt state file counts as zero; state files are created under the redirected
  `TMPDIR` only.
- **Headless.** With `AGENTTOOLING_HEADLESS=1` the third opaque command prints nothing
  and the counter still advances; unset, it prints `ask`. With `AGENTTOOLING_SCRATCH`
  set to a directory under the redirected `TMPDIR`, `bash <scratch>/x.sh` is approved
  (file exists), `bash /elsewhere/x.sh` is not, a symlink from `<scratch>/x.sh` to
  outside the tree is not, and with the variable unset nothing under any scratch
  directory is approved.
- **The runner exports.** `plan-runner-lib.sh`'s `claude -p` invocation carries both
  variables; a stub `claude` in an existing runner test (`self/tests/` — pick the one
  that already inspects the executor's environment or prompt, or add the assertion to the
  closest) sees them, and the scratch directory is removed when the pass ends.
- **Audit record.** Every case from §4 appears either as an assertion in
  `allow-repo-commands.sh` (REFUSE/DENY) or as a row in one of the two `hooks/README.md`
  tables, with the reason it is safe. A bypass fixed with no test is a finding.
- **Named constants** for every new shape pattern, reason string, env var name, the
  attempt limit and the state-dir template; the hook stays stdlib-only Python 3; bash 3.2
  in the runner and tests; no chained `cd`; no variable-then-use on one line in any test
  fixture command *outside* the strings being tested.
- **`hooks/README.md` → "Editing the policy"** names the new constants and the two tests.

## Verdict

Write it as the PR body will read it: what the diff does, each contract above as
holds / fixed here / escalated, the bypasses found and closed, and the files touched by
this pass.
