# hooks

Claude Code hook scripts, vendored with the rest of `agentTooling/`. A hook does nothing
until a settings file names it; `sync-plans.sh` does that wiring, so a repo gets it at
install and after every `subtree pull`. Both scripts are Python 3, standard library only.

- `allow-repo-commands.sh` — `PreToolUse` hook for the `Bash` tool. Reads the hook payload
  `{ tool_name, cwd, tool_input{command} }` on stdin and prints
  `{ hookSpecificOutput: { hookEventName, permissionDecision, permissionDecisionReason } }`
  with `permissionDecision: "allow"` when the whole command is confined to the project
  root and built only from allowlisted read/test programs and the harness's own read-only
  entry points. Prints nothing otherwise, so the normal permission flow runs. It emits
  `permissionDecision: "deny"` for exactly three shapes: a command chaining `cd` or `pushd`
  with any other command, with a reason naming the rewrite; a git command that moves a
  ref or rewrites history, with a reason naming `LIFECYCLE.md` rule 2 and the two scripts
  that are the way in and out; and an assignment at command position whose own `$NAME` is
  used later on the same line, with a reason saying to inline the literal.
  Every approval rule is a refusal and the default is to
  refuse: a token it does not understand makes the whole command fall through to the prompt.
- `wire-settings.py` — `wire-settings.py [--self] --repo <dir> (--check | --write)`.
  Maintains the `PreToolUse` entry for `allow-repo-commands.sh` and the `Edit` and `Bash`
  deny rules in `<dir>/.claude/settings.json`. Prints one `status<TAB>message` line for the
  caller to format and exits 0 when nothing needs attention, 1 otherwise. Statuses:
  `in-sync`, `missing`, `UNWIRED`, `INVALID` for `--check`; `created`, `wired`, `kept`,
  `INVALID` for `--write`. `--self` writes agentTooling's own checkout instead of a
  consuming repo's — the hook path without the `agentTooling/` segment and the policy deny
  `Edit(/hooks/**)` — and changes nothing else. Called by `sync-plans.sh` (without
  `--self`) and by `self/gate.sh` (with it, in `--check`); tested by
  `self/tests/hook-wiring.sh`.

## Why `allow-repo-commands.sh` exists

`permissions.blockReadsOutsideWorkingDirectories` refuses any command whose paths resolve
at run time. That is every `cd X && cmd` chain — including `cd X && ls`, and including
commands an allow rule already covers, since the block is checked before rule matching.
`CONVENTIONS.md` § Shell commands tells agents not to write that shape, but nothing else
enforces the rule, and every miss costs the human a prompt while teaching the model
nothing. So the hook answers a `cd X && cmd` chain with a deny whose reason is the fix,
not with an approval, and approves the rewritten, unchained commands without turning the
fence off.

## What it denies

A `cd` or `pushd` at command position alongside any other command, where commands are
separated by `&&`, `||`, `;`, `|`, `&`, a line break, or a `(` subshell. The reason tells
the model to run `cd <absolute path>` as its own call, or to name every path absolutely.

A `$(…)` command substitution is its own scope, quoted or not: nothing inside it counts
as a command of the outer line, and the word after its `)` is read where the `$(` left
off. A `cd` in there moves no path the outer command resolves — `x=$(cd dir && pwd)` is
the usual way to make a path absolute — so `x=$(cd dir && pwd)` and
`x="$(cd dir && pwd)"` are both left alone, while `x=$(pwd) && cd dir` is still a chain.

The check runs before, and independently of, the approval analysis, and it needs neither
`CLAUDE_PROJECT_DIR` nor `cwd`: the shape is wrong wherever it runs. It deliberately does
not deny a standalone `cd`; `cd` as an argument (`echo cd`, `find . -name cd`) or inside
quotes; a redirect target; a heredoc body — any command containing `<<` is never denied;
any command containing `#`, since a mid-word `#` bash reads literally could otherwise
hide a heredoc; or a command that does not tokenize (an unbalanced quote). Those fall through to the
approval analysis as before.

In a consuming repo the deny also reaches the runners' Bash-enabled executors (verify,
review). That is intended: they are held to the same convention.

### The git shape

A git command that moves a ref, rewrites history or throws work away, **wherever it sits
on the line** — after a `&&`, `;`, `|` or `&`, inside a `(…)` subshell or a `$(…)`
substitution, behind `-C <path>`, `--git-dir=…` or `-c k=v`. The reason names
`LIFECYCLE.md` → "The three rules", rule 2, and the two scripts that are the sanctioned
way in and out: `feature-start.sh` makes the branch and the worktree, `feature-close.sh`
removes them, and both are run by the human from the primary checkout.

Denied: `push` with `--force`, `-f` or `--force-with-lease[=…]`; `reset --hard`; `clean`;
`stash`; `rebase`; `worktree` with any subcommand but `list`; `checkout -b`/`-B`;
`switch -c`/`-C`; `branch` with a positional argument or `-d`/`-D`/`--delete`/`-m`/`-M`/
`--move`. `clean`, `stash` and `rebase` are denied whatever follows, read-only spellings
included — `git stash list` is one keystroke from `git stash`, and the prompt is the right
place to tell them apart.

Not denied: `git branch --show-current`, `git branch --merged main` (the value of a
listing flag is not a positional), `git worktree list`, a plain `git push`,
`git checkout -- <file>`, `git reset <file>`. Nor is anything the analysis cannot read,
for the same reason the `cd` deny leaves those alone: a heredoc, a `#`, a line that does
not tokenize, a `git …` that is an argument rather than a command (`echo 'git rebase'`),
or a word carrying a brace — no brace expansion happens here, so `git branch {-a,new}`
prompts, and it is the approval analysis, which does expand, that refuses it.

The check runs after the `cd` deny and before the approval analysis, and like the `cd`
deny it needs neither `CLAUDE_PROJECT_DIR` nor `cwd`.

### The run-time-value shape

An **assignment at command position** whose own `$NAME` or `${NAME}` appears later on the
same line: `X=/p; cat $X/f`, `export X=/p && ls $X`. This is the generalisation of the
chained `cd` — what blocks the reads fence is a path decided at run time, not several
commands on a line — narrowed to the one case where the literal is provably still in hand
two words earlier, so the correction is a substitution rather than a rewrite. The reason
says to inline it: every path a literal, one command per call.

A command whose words are *all* assignments is an assignment command; one with anything
else after them is an **environment prefix** (`X=1 make`), which decides nothing the shell
re-reads on the same line, and is not denied. Nor is an assignment nobody dereferences
(`X=/p`), a `$NAME` with no assignment on the line (`cat $HOME/f`), a `$` the shell will
not act on (`echo '$X'`, a backslash-escaped one), or a `$(…)` substitution, which is not
a variable use. The three guards the other denies keep hold here too, through the same
`command_words`: a heredoc, a `#`, or a line that will not tokenize is never judged.

The rest of the rule — no `$(…)` in a path, no heredoc into an interpreter — stays prose
in `CONVENTIONS.md` § Shell commands rather than becoming a deny, because there the fix is
a rewrite (a `grep -o` with context, or a script written to the scratchpad and run), and a
deny must not demand one.

**There is no `BASH_DENY_RULES` twin for this one**, unlike the git deny. A
`permissions.deny` entry is a command *prefix*, and this is a relation between two tokens
anywhere on the line; no prefix rule can express it, so the hook is the whole of the
enforcement. `allow-repo-commands.sh` says so beside the constants.

## What it approves

A command is approved only when **every** subcommand (split on `&&`, `||`, `;`, `|`, `&`)
passes, against a cwd that starts at the payload's `cwd` and moves with each `cd` (a
chained `cd` only reaches this analysis when § What it denies declined to judge it):

- `cd` — one argument, absolute, resolving inside the root through symlinks.
- Every argument that is a path must resolve inside the root: absolute ones through
  symlinks; relative ones against the effective cwd, expanded as globs first, so
  `dir/*` is judged by what it will actually name. `--flag=value` and `key=value`
  carry their path in the value. A value that names nothing on disk is not a path.
- The program: a read-only program (`READ_ONLY_PROGRAMS`) with none of its writing,
  executing or symlink-following flags (`FORBIDDEN_FLAGS`, whole token or the part
  before `=`; `FORBIDDEN_SHORT_LETTERS`, any letter of a single-dash token, which also
  catches `-ni` and `-i.bak`); `sed` with only `-n`/`-E`/`-r` and a script matching
  *optional address or range, then `p`*, because `w` inside a script writes a file;
  `git` with a read-only subcommand and no `--output`, where `branch` takes only listing
  flags and `worktree` only `list`; a runner prefix (`RUNNER_PREFIXES`) — pytest,
  ruff, mypy, `npx playwright test`, and `npm run` for the named scripts only, since
  `npm run` executes whatever `package.json` says; or one of the harness's own entry
  points below.

### The harness's own entry points

The commands an executor runs to read the state of its own work. Each is matched by
**basename**, and only when the script path exists and resolves inside the root, so one
rule covers both spellings of the same script — `plans/gate.sh`,
`agentTooling/check-plans.sh` and `agentTooling/analysis/report.py` in a consuming repo,
`self/gate.sh`, `./check-plans.sh` and `analysis/report.py` in agentTooling's own
checkout. A basename on its own vouches for nothing: `python3 /tmp/report.py` and
`python3 ../report.py` refuse, and so does one reached through a symlink that leaves the
tree.

| Approved | Held to |
|---|---|
| `gate.sh` | no arguments, or one level label |
| `check-plans.sh` | any arguments (they are `--self` and a slug) |
| `bash -n <files>` | only `-n`, at least one file |
| `shellcheck <files>` | no flags, at least one file |
| `python3 [-B] -m py_compile <files>` | at least one file |
| `python3 [-B] <…>/report.py` | any arguments |
| `python3 [-B] <…>/capture_planning.py` | some argument starts with `--list-`, and none is `--recapture`, `--all` or `--carry-lost` |
| `python3 [-B] <…>/manifest.py` | the subcommand — the second positional — is `get` |

Nothing else. `feature-start.sh`, `feature-close.sh`, `sweep.sh`, `stamp-timing.sh`,
`capture_planning.py` in a capturing form, `manifest.py init` and `set-*`, `python3 -c`,
`bash <script>` without `-n` and every other script still prompt: each either freezes a
cost record, rewrites a manifest, moves a ref, or runs whatever it is handed.
`manifest.py get init` is a feature named `get` being initialized, which is why the
subcommand is read positionally rather than searched for.

This does **not** widen `python3`. The interpreter is approved only in front of
`-m py_compile` or one of those scripts, and every file argument is checked against the
root like any other path.

Refused outright, before any of that: `..` anywhere; a line break or NUL; a token
beginning with `~`; and, outside single quotes or a backslash, any of `< > $ \`` —
redirection, substitution. The harmless `2>&1`, `>/dev/null`, `2>/dev/null` and
`&>/dev/null` are stripped first. Unbalanced quotes refuse. A leftover punctuation token
that is not a recognised separator (`|&`, `;;`, `(`, `>&`) refuses.

Brace lists (`ls {src,tests}`, `cat src/{a,b}.py`) are expanded, not refused, when they
are simple. Every raw word of the command — split as bash splits it, quotes and
backslashes kept — that contains a brace must either be wholly single-quoted (bash reads
the brace literally) or carry no quote or backslash at all and consist only of simple
groups: `{` + comma-separated alternatives, at least one comma, no brace, whitespace,
quote, `$` or backtick inside, + `}`. The groups are removed in one pass and any brace
left over refuses, which is what refuses nesting (`{a,{b,c}}`), a comma-less `{a}`, and
`{}`. `..` is already refused, which covers sequence expressions (`{a..c}`). Each
subcommand is then checked twice with the same cwd: as its **literal** tokens, which keeps
a single-quoted `'{-a,-v}'` from approving `git branch`, and as its **expanded** words
(left to right, cartesian, as bash does), which checks every path and flag bash will
really see — so `cat {src/a.py,/etc/passwd}` and `sort -{r,o}x` refuse, and `cd {a,b}`
refuses for having two arguments. A token expanding to more than `MAX_BRACE_WORDS` (256)
words refuses, and an expanded word beginning with `~` refuses, since bash expands the
tilde after the braces.

## What the audit found and closed

Each of these approved something in the first version. All are now refused and asserted
in `self/tests/allow-repo-commands.sh`:

| Bypass | Was |
|---|---|
| `cat $HOME/.ssh/id_rsa` | `$` never rejected; a relative-looking token skipped the path check |
| `sort --output=~/.zshrc f`, `git log --output=…`, `pytest --junit-xml=/tmp/x` | `--flag=value` never split |
| `sed -i.bak`, `sed -ni`, `sort -o/tmp/x` | short flags matched as whole tokens only |
| `sed 's/a/b/w ~/.zshrc' f` | sed's `w` command writes from inside the script |
| `git branch -D main`, `git branch new` | `branch` allowlisted wholesale |
| `rg --pre 'sh -c …'`, `sort --compress-program=…` | exec-through flags not forbidden |
| `cat {/etc/passwd,}` | brace expansion produced a path the checker never saw; now expanded and each word checked |
| `ls \|& sh` | `\|&` is not a separator, so `sh` hid inside the `ls` group |
| `ls x#; rm -rf src` | shlex starts a comment at any `#`, bash only at a word's start, so the `rm` was never lexed; shlex comments are now off |
| `cat link-out/.zshrc`, `head dir/*` | relative paths and globs never resolved through symlinks |
| `grep -R`, `find -L`, `rg -L` | symlink-following recursion reads outside the tree |
| `tree -o f`, `uniq in out`, `npm run <any>`, `npx playwright install` | allowlist too wide |
| `ls > /dev/nullx` | redirect stripped by substring, not whole word |
| `ls <NUL>` | bash truncates at NUL; the analysis read past it |

## Accepted limits

- **Repo code runs.** pytest, ruff, playwright and the `npm run` scripts execute what the
  repo contains. That is what "run the tests" means; a change to that code is a write,
  which this hook never approves.
- **A planted file needs a prior write.** An unquoted glob that expands to `-delete`, a
  look-alike `python` symlink inside the tree, a `.git/config` that points `diff.external`
  at a command — each requires a file to exist first, and creating it prompts.
- **Conservative false negatives.** A grep pattern that looks like an absolute path
  outside the tree (`grep '/usr/lib' src`) prompts. So does `~` anywhere a token starts,
  `..` anywhere at all, and any `$` outside single quotes even when escaped inside double
  quotes. The cost of each is one prompt.
- **`||` short-circuit.** The effective cwd after `cd A || cd B` is taken as `B`. Every
  `cd` target is inside the root regardless, so the approximation only affects which
  inside directory relative arguments are resolved against.

## The deny rules

`wire-settings.py` also maintains two sets of rules in `permissions.deny`, which binds in
every permission mode and cannot be overridden by a mode or an allow rule.

### `Edit`

`--permission-mode acceptEdits` — which the batch runners use — accepts every Edit-tool
write under the working directory, unattended. So:

```
Edit(/.git/**)      Edit(**/.git/**)     Edit(**/.git)
Edit(/.claude/**)   Edit(**/.claude/**)
Edit(**/.venv/**)   Edit(**/venv/**)     Edit(**/node_modules/**)
Edit(**/agentTooling/hooks/**)      # Edit(/hooks/**) under --self
```

`.git/hooks/*` is executable code; `.claude/` is the permission system itself; the
dependency trees are code that runs on the next test; and `agentTooling/hooks/` is this
policy, which an unattended executor must not be able to widen. That last rule also
means changing the policy through the Edit tool is refused, in every session — edit it
in an editor, or run a script that writes it. Rare, and deliberate by design. It is the
one rule whose spelling depends on the mode: in agentTooling's own checkout this
directory is at the root, so `--self` writes `Edit(/hooks/**)` instead. The `**/`
forms match at any depth,
so a worktree's copies are covered; the two root-anchored forms are insurance for the
two that matter most. Deny rules reach the Edit and Write tools and `> file` redirects,
not a subprocess that opens a file itself — which is also why `sync-plans.sh` can still
write `.claude/settings.json` through this helper. OS-level enforcement is sandboxing.

### `Bash`

`LIFECYCLE.md` rule 2 — agents never create or destroy branches and worktrees, and never
rewrite history — written where `/permissions` will show it:

```
Bash(git push --force:*)   Bash(git push -f:*)   Bash(git push --force-with-lease:*)
Bash(git reset --hard:*)   Bash(git clean:*)     Bash(git stash:*)   Bash(git rebase:*)
Bash(git worktree add:*)   Bash(git worktree remove:*)   Bash(git worktree prune:*)
Bash(git checkout -b:*)    Bash(git checkout -B:*)
Bash(git switch -c:*)      Bash(git switch -C:*)
Bash(git branch -d:*)      Bash(git branch -D:*)
Bash(git branch -m:*)      Bash(git branch -M:*)
```

These are **prefix** rules: each matches only a command that begins with the text it
names, so `git -C /repo worktree add x`, `x=$(git rebase main)` and `ls && git stash`
match none of them. The enforcement is the hook's git deny above, which reads every
command on the line; these rules are the visible half of the same policy, and the two
lists — `BASH_DENY_RULES` here, the `GIT_*` mutation constants in the hook — are changed
together. A rule here is never an allow rule; nothing this helper writes ever is.

## What `wire-settings.py` will and won't touch

`.claude/settings.json` is repo-owned and may hold anything, so everything is **merged,
not copied**. The hook entry is appended when no hook command anywhere in the file
mentions `allow-repo-commands.sh`; each deny rule is appended when its exact string is
absent. Otherwise the file is left byte-for-byte alone. It never removes, reorders or
rewrites another entry, and it never adds an allow rule.

The hook marker is the script's basename, so a repo that hand-edits the entry — a
different path, a narrower `matcher`, an added `if:` — keeps its version and never gets a
duplicate. Deleting an entry or a deny rule is durable in one direction only: the next
write run re-adds it. To opt out of the hook for good, keep an entry that points it
somewhere harmless rather than deleting it; to opt out of a deny rule, remove it from
`EDIT_DENY_RULES` or `BASH_DENY_RULES` here, which changes it for every consuming repo.

`--self` changes two values and nothing else: the hook command loses the `agentTooling/`
segment and the policy deny rule becomes `Edit(/hooks/**)`. The merge, the statuses and
the refusals are identical, and the two modes are not interchangeable — `--self --check`
over a vendored repo's file reports `UNWIRED`, because the policy rule it wants is not
the one that is there.

A file that does not parse, or whose `hooks`, `hooks.PreToolUse`, `permissions` or
`permissions.deny` values are the wrong type, is reported `INVALID` and left untouched by
both modes.

## Cross-layer dependencies

- **`CLAUDE_PROJECT_DIR`** — `allow-repo-commands.sh` reads this for the project root and
  approves nothing when it is unset. Claude Code sets it for hook processes. In a `git
  worktree` it is the worktree root, so a worktree session approves paths inside its own
  tree only — never the main checkout.
- **`cwd` in the hook payload** — must be present and inside the root, or a relative path
  in the command could resolve anywhere. The hook approves nothing without it.
- **`python3` on `PATH`** — `sync-plans.sh` skips the wiring with a `SKIPPED` line when it
  is absent. The hook itself is `#!/usr/bin/env python3`.
- **`.claude/settings.json` must be committed** to reach worktrees. A `git worktree` gets no
  `.claude/` of its own, and `.claude/settings.local.json` is ignored globally by Claude
  Code's default `~/.config/git/ignore` entry. The shared file is the only copy a worktree
  or a fresh clone can inherit. `sync-plans.sh` says so when it writes one.
- **This checkout's own `.claude/settings.json` is written, not authored.**
  `python3 -B hooks/wire-settings.py --self --repo <root> --write` produced the committed
  file at the root of agentTooling, and `self/gate.sh` records
  `wire-settings.py --self --repo <root> --check` as a blocking check, so a hand edit that
  drifts from these constants fails the gate. Do not edit that file directly — the
  `Edit(/.claude/**)` rule in it refuses anyway; change the constants here and re-run the
  write. The file ships with the subtree like everything else in this directory, and a
  consuming repo's own wiring is the one at *its* root, written by `sync-plans.sh` without
  `--self`.
- **The hook is trusted code that lives in the repo.** `update.sh` pulls it from the
  agentTooling upstream and re-runs the wiring, so that upstream is the trust root for
  the policy. The `Edit(**/agentTooling/hooks/**)` deny rule keeps an executor from
  changing it through the Edit tool; a subprocess write is the remaining path, and only
  the sandbox binds that.
- **Hooks are read at session start.** A change to the wiring takes effect in the next
  session; `/hooks` shows what the current one loaded.

## Wiring

`sync-plans.sh` does this. By hand, the equivalent is:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/agentTooling/hooks/allow-repo-commands.sh" }
        ]
      }
    ]
  }
}
```

In agentTooling's own checkout the command is
`${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh`, which is what
`wire-settings.py --self --write` writes.

## Editing the policy

The allowlists are named constants at the top of `allow-repo-commands.sh`:
`READ_ONLY_PROGRAMS`, `FORBIDDEN_FLAGS`, `FORBIDDEN_SHORT_LETTERS`, the `SED_*` grammar,
`GIT_READ_ONLY_SUBCOMMANDS` / `GIT_BRANCH_ALLOWED_FLAGS` / `GIT_WORKTREE_READ_ONLY`,
`RUNNER_PREFIXES`, `RUNNER_BASENAMES`, `RUNNER_ALIASES` and `MAX_BRACE_WORDS`, the
`ENTRY_*`, `CAPTURE_*`, `MANIFEST_*`, `SYNTAX_*` and `PYTHON_*` constants for the
harness's own entry points, plus `CHDIR_PROGRAMS`, the `GIT_*` mutation constants and
`ASSIGNMENT_RE` / `ASSIGNMENT_BUILTINS` / `VAR_USE_RE` for the
three denies. Every change to the approval constants is a widening of
what runs without a prompt: add the command to `self/tests/allow-repo-commands.sh` with
the bypass you checked it does not open, and run `bash self/tests/allow-repo-commands.sh`.
A change to `CHDIR_PROGRAMS` adds a `DENY` case and a `NOT_DENIED` case there.

**Two constants move together.** `GIT_ALWAYS_MUTATING` and the `GIT_*` flag sets beside
it in `allow-repo-commands.sh` are what the hook enforces; `BASH_DENY_RULES` in
`wire-settings.py` is the same list as `permissions.deny` prefix rules. A subcommand
added to one needs its rule in the other, plus a `DENY` case and a `NOT_DENIED` case in
`self/tests/allow-repo-commands.sh` and the rule string in `self/tests/hook-wiring.sh`.
Each file's comment names the other.
