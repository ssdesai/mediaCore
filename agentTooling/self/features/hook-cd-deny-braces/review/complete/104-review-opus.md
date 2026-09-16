# 104 — review: hook-cd-deny-braces

feature: agentTooling/hook-cd-deny-braces — plan 4 of 4. `hooks/allow-repo-commands.sh`
gains a `deny` decision for any Bash command that chains `cd`/`pushd` with another
command, and approves simple brace lists in otherwise-approvable reads by expanding them
before its path checks.

## What the feature was supposed to do

`CONVENTIONS.md` § Shell commands forbids chaining `cd` with another command. Nothing
enforced it. The PreToolUse hook either approved such a chain or stayed silent, and a
silent miss cost the human an approval and taught the model nothing. The hook now:

1. **Denies** any Bash command in which a `cd` or `pushd` shares the command with any
   other command, with a `permissionDecisionReason` naming the rewrite (a standalone `cd`
   call, or absolute paths). It denies before, and independently of, the approval
   analysis and the root/cwd checks. It never denies a command that is not such a chain:
   `cd` as an argument, inside quotes, in a heredoc body, as a redirect target, on its
   own, or in a command that does not tokenize.
2. **Approves** reads that use simple, unquoted brace lists (`ls {src,tests}/*.py`) by
   expanding them the way bash does and checking every resulting word. It refuses
   everything else brace-shaped: nested, quoted or escaped braces, more than 256 words, a
   tilde produced by expansion. A command passes only when both its literal argv and its
   expanded argv pass.

This hook is a security boundary that ships to every consuming repo. Item 2 **widens**
what runs without a prompt. Item 1 adds the only refusal the hook has ever emitted.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. The verify report is in
this feature's `verify/complete/103-verify-sonnet.progress.md`. Read its two counts and
any fixes before judging.

## Contracts to hold it to

- **No approval bash would not grant.** The threat model in `hooks/README.md` is an agent
  turning an approved read into a read outside the root, a write, or an execution. For
  item 2, reason about where the hook's `shlex` view and bash's word expansion can
  diverge: quote removal before expansion, backslashes, a group inside `--flag=value`, the
  literal-versus-expanded argv pairing, and positional-sensitive checks (`sed`'s script
  positional, `git branch` flags, `cd`'s single argument, `RUNNER_PREFIXES` matched on the
  head). Every audited bypass in `hooks/README.md` § What the audit found must still
  refuse.
- **No false deny.** A deny blocks a legitimate command outright, with no approval path.
  Hold `chains_chdir` to "never deny on a guess". Check redirect handling, `$(…)` and
  quoted substitutions, and heredocs.
- **Deny independence.** The deny must not depend on `CLAUDE_PROJECT_DIR` or `cwd`. An
  exception anywhere in chain detection must yield no decision, never a deny and never an
  allow.
- **Named constants** (`CONVENTIONS.md` → Named constants), and no approval rule loosened
  beyond the two items above.
- **Docs match behaviour.** `hooks/README.md` (the bullet, § What it denies, § What it
  approves, the audit table, § Editing the policy), `README.md`'s `hooks/` row,
  `CONVENTIONS.md` § Shell commands, `self/tests/README.md`'s entry, and the
  `sync-plans.sh` comment. None may still say the hook never denies, or that it approves
  `cd X && cmd` chains.
- **The test is the permanent check.** Any gap you find is best reported as the command to
  add to `DENY`, `NOT_DENIED`, `BRACE_ALLOW` or `BRACE_PROMPT` in
  `self/tests/allow-repo-commands.sh`.

Fix what is local (a missed refusal, a doc line, a missing test case). Escalate what is
structural. "No findings" is a legitimate verdict. Do not re-run the gate or rebuild the
verify pass's probes.

## Verdict

Write for the human approving the PR: what the feature does, whether it does it, and two
lists — fixed here, escalated.
