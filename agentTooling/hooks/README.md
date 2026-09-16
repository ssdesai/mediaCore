# hooks

Claude Code hook scripts, vendored with the rest of `agentTooling/`. A hook does nothing
until a settings file names it; `sync-plans.sh` does that wiring, so a repo gets it at
install and after every `subtree pull`. Both scripts are Python 3, standard library only.

- `allow-repo-commands.sh` — `PreToolUse` hook for the `Bash` tool. Reads the hook payload
  `{ tool_name, cwd, tool_input{command} }` on stdin and prints
  `{ hookSpecificOutput: { hookEventName, permissionDecision, permissionDecisionReason } }`
  with `permissionDecision: "allow"` when the whole command is confined to the project
  root and built only from allowlisted read/test programs. Prints nothing otherwise, so
  the normal permission flow runs. It never emits `"deny"` — it removes prompts, it does
  not add refusals. Every rule is a refusal and the default is to refuse: a token it does
  not understand makes the whole command fall through to the prompt.
- `wire-settings.py` — `wire-settings.py --repo <dir> (--check | --write)`. Maintains the
  `PreToolUse` entry for `allow-repo-commands.sh` and the `Edit` deny rules in
  `<dir>/.claude/settings.json`. Prints one `status<TAB>message` line for the caller to
  format and exits 0 when nothing needs attention, 1 otherwise. Statuses: `in-sync`,
  `missing`, `UNWIRED`, `INVALID` for `--check`; `created`, `wired`, `kept`, `INVALID` for
  `--write`. Called by `sync-plans.sh`; tested by `self/tests/hook-wiring.sh`.

## Why `allow-repo-commands.sh` exists

`permissions.blockReadsOutsideWorkingDirectories` refuses any command whose paths resolve
at run time. That is every `cd X && cmd` chain — including `cd X && ls`, and including
commands an allow rule already covers, since the block is checked before rule matching.
`CONVENTIONS.md` § Shell commands tells agents not to write that shape; this hook covers
the runs that still do, without turning the fence off.

## What it approves

A command is approved only when **every** subcommand (split on `&&`, `||`, `;`, `|`, `&`)
passes, against a cwd that starts at the payload's `cwd` and moves with each `cd`:

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
  flags and `worktree` only `list`; or a runner prefix (`RUNNER_PREFIXES`) — pytest,
  ruff, mypy, `npx playwright test`, and `npm run` for the named scripts only, since
  `npm run` executes whatever `package.json` says.

Refused outright, before any of that: `..` anywhere; a line break or NUL; a token
beginning with `~`; and, outside single quotes or a backslash, any of `< > $ \` { }` —
redirection, substitution, brace expansion. The harmless `2>&1`, `>/dev/null`,
`2>/dev/null` and `&>/dev/null` are stripped first. Unbalanced quotes refuse. A leftover
punctuation token that is not a recognised separator (`|&`, `;;`, `(`, `>&`) refuses.

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
| `cat {/etc/passwd,}` | brace expansion produced a path the checker never saw |
| `ls \|& sh` | `\|&` is not a separator, so `sh` hid inside the `ls` group |
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

## The `Edit` deny rules

`--permission-mode acceptEdits` — which the batch runners use — accepts every Edit-tool
write under the working directory, unattended. `wire-settings.py` therefore also adds
these to `permissions.deny`, which binds in every permission mode and cannot be
overridden by a mode or an allow rule:

```
Edit(/.git/**)      Edit(**/.git/**)     Edit(**/.git)
Edit(/.claude/**)   Edit(**/.claude/**)
Edit(**/.venv/**)   Edit(**/venv/**)     Edit(**/node_modules/**)
Edit(**/agentTooling/hooks/**)
```

`.git/hooks/*` is executable code; `.claude/` is the permission system itself; the
dependency trees are code that runs on the next test; and `agentTooling/hooks/` is this
policy, which an unattended executor must not be able to widen. That last rule also
means changing the policy through the Edit tool is refused, in every session — edit it
in an editor, or run a script that writes it. Rare, and deliberate by design. The `**/`
forms match at any depth,
so a worktree's copies are covered; the two root-anchored forms are insurance for the
two that matter most. Deny rules reach the Edit and Write tools and `> file` redirects,
not a subprocess that opens a file itself — which is also why `sync-plans.sh` can still
write `.claude/settings.json` through this helper. OS-level enforcement is sandboxing.

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
`EDIT_DENY_RULES` here, which changes it for every consuming repo.

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

## Editing the policy

The allowlists are named constants at the top of `allow-repo-commands.sh`:
`READ_ONLY_PROGRAMS`, `FORBIDDEN_FLAGS`, `FORBIDDEN_SHORT_LETTERS`, the `SED_*` grammar,
`GIT_READ_ONLY_SUBCOMMANDS` / `GIT_BRANCH_ALLOWED_FLAGS` / `GIT_WORKTREE_READ_ONLY`,
`RUNNER_PREFIXES`, `RUNNER_BASENAMES` and `RUNNER_ALIASES`. Every change is a widening of
what runs without a prompt: add the command to `self/tests/allow-repo-commands.sh` with
the bypass you checked it does not open, and run `bash self/tests/allow-repo-commands.sh`.
