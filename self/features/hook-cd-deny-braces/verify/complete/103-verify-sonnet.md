# 103 — verify: hook-cd-deny-braces

feature: agentTooling/hook-cd-deny-braces — plan 3 of 4. `hooks/allow-repo-commands.sh`
gains a `deny` decision for any Bash command that chains `cd`/`pushd` with another
command, and approves simple brace lists in otherwise-approvable reads by expanding them
before its path checks.

Read `self/gate-report.txt` first. Do not re-run the gate's checks. If
`allow-repo-commands` is red there, triage and fix that first, then re-run only
`bash self/tests/allow-repo-commands.sh`.

Then read `self/tests/allow-repo-commands.sh`, which is the contract, and check only what
it leaves uncovered. There are two questions a list of cases cannot settle.

## 1. Does the hook's brace expansion ever approve what bash would not?

The hook approves a command only when both a literal argv and a brace-expanded argv pass.
Probe the gap adversarially against the real shell. In a `mktemp -d` project root (mirror
the test's fixture: a symlink out of the tree, a `src/` and a `README.md`), for each
candidate command whose hook decision is `allow`, get bash's real argv by running the
command with its program swapped for `printf '%s\n'` under `bash -c` in that root. Every
word bash produced must itself be confined and unflagged, judged by feeding
`cat <word>` (or the original program with that word) back through the hook. Candidates
should aim at mismatches between `shlex` and bash: quotes and backslashes next to or
inside groups, empty alternatives (`{,x}`), adjacent groups, a group in a `--flag=value`
value, a group in `git`/`sed` arguments, globs after a group, and `~` inside an
alternative. Nothing reads outside the fixture: use `printf`, never `cat`, for bash's side.

A mismatch that approves is a defect. Fix it locally if the fix is a refusal, and add the
command to `BRACE_PROMPT` in the test. If the fix is structural, write it up instead.

## 2. Does the deny fire on commands that are not chained cds?

Collect real Bash commands from this machine's recent transcripts: the `input.command` of
`tool_use` blocks named `Bash` in the newest 40 `*.jsonl` files under
`~/.claude/projects/-Users-sahildesai-dev-agentTooling*/` and
`~/.claude/projects/*vinylCatalogue*/`. Read them with `jq` or a Python one-off to stdout,
and run each through the hook with `CLAUDE_PROJECT_DIR` and `cwd` set to this worktree.
Report two lists, counts plus up to ten examples each:

- **False denies**: a `deny` on a command in which no `cd`/`pushd` is a command sharing the
  line with another. Each one is a defect. Fix it and add it to `NOT_DENIED`.
- **Denies that were real chains**: the population this feature exists for. Only the count
  and a few examples.

Do not paste transcript contents beyond the command strings you cite.

## Also check, and do not re-derive what the test already asserts

- `hooks/README.md`, `README.md`'s `hooks/` row, `CONVENTIONS.md` § Shell commands and
  `self/tests/README.md` describe the hook as it now behaves: a deny exists, braces are
  expanded, and no line still says the hook never denies or approves `cd X && cmd`.
- The `sync-plans.sh` comment on the hook.

## Verdict

Fixes made here, each with the test case added; defects found but not fixed; and the two
counts from section 2.
