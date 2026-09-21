# Design 2026-09-17 — one policy module for the hook and the settings writer

Feature slug: `policy-module`. Base: `lifecycle-records-and-numbering`. Scope: `hooks/`,
`.claude/settings.json` (regenerated), `self/tests/allow-repo-commands.sh`,
`self/tests/hook-wiring.sh`, `self/tests/hook-escalation.sh`, `hooks/README.md`, root
`README.md` row for `hooks/`, `self/README.md` (the gate's description of the drift
check), `self/BACKLOG.md` (entries removed), `LIFECYCLE.md` only if it quotes the git
reason. Decided by the coordinator before the build; the build's rulings go in the
feature's `NOTES.md`, and a ruling that changes a decision here says so there.

## §1 The defect

The git deny lives twice — `GIT_*` constants in `allow-repo-commands.sh` and a hand-typed
`BASH_DENY_RULES` tuple in `wire-settings.py` — and they have drifted (five shapes the hook
denies are not in the settings: `worktree move|lock|unlock|repair`, `branch
--delete|--move`). The drift check sees only missing additions, so a hand-edited settings
file passes the gate. The docstring names a constant that does not exist. Beside that,
four smaller policy gaps and three stale names.

## §2 One table (D1)

New `hooks/policy.py`, stdlib only, imported by both scripts via
`sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))`. It holds the git policy
as data:

- `GIT_ALWAYS_MUTATING` = clean, stash, rebase (whole verb).
- `GIT_PUSH_FORCE_FLAGS`, `GIT_RESET_MUTATING_FLAG`, `GIT_CHECKOUT_BRANCH_FLAGS`,
  `GIT_SWITCH_BRANCH_FLAGS`, `GIT_BRANCH_MUTATING_FLAGS` (`--delete` and `--move` are
  already there).
- `GIT_WORKTREE_SUBCOMMANDS = {"list": READ_ONLY, "add": MUTATING, "remove": …,
  "prune": …, "move": …, "lock": …, "unlock": …, "repair": …}`; the hook denies any
  subcommand not marked READ_ONLY (unknown = mutating, as today); the prefix rules
  enumerate the MUTATING ones.
- `bash_deny_rules()` renders the prefix-rule twin from the table, in a fixed order:
  push force ×3, reset --hard, clean, stash, rebase, worktree ×7, checkout -b/-B,
  switch -c/-C, branch -d/-D/--delete/-m/-M/--move. `wire-settings.py` uses it;
  `BASH_DENY_RULES` as a literal tuple is gone. The hook imports the same constants for
  `git_mutates`.
- The hook's `GIT_BRANCH_ALLOWED_FLAGS` etc. stay in the hook (approval side), but
  `--list`/`-l` is added to the deny side's reading: after `--list`/`-l` a positional is
  a glob, not a name (D8).

The hook file is still one script named `.sh` with a Python shebang; adding a sibling
module is fine in both layouts (vendored `agentTooling/hooks/` and self `hooks/`).
`sync-plans.sh` copies nothing file by file — the subtree carries the directory — so no
installer changes.

## §3 The drift check (D2)

`wire-settings.py --self --check` compares `.claude/settings.json` BYTE FOR BYTE with what
`--self --write` would produce from an empty file: agentTooling's own settings are wholly
generated, so any hand edit (an added allow rule, a repointed hook command) fails the gate
with a diff-shaped message naming the first differing entry. Consuming repos keep the
merge semantics (`--check` reports missing entries only), because their file is
repo-owned. `hooks/README.md` and `self/README.md` say exactly this. Module docstring:
name the real constants (`GIT_ALWAYS_MUTATING` and the flag sets, now in `policy.py`).

## §4 Opaque = unreadable (D3)

`is_opaque` grows a seventh shape: a line that does not tokenize — an unbalanced quote or
a token shlex refuses — is denied with a reason naming the quote (an `OPAQUE_DENY_REASON`
variant or a clause appended), and counts toward the escalation like the other six. The
heredoc guard and the `#` guard stay as they are (those still prompt). Every case in the
test's ALLOW, NOT_DENIED, GIT_NOT_DENIED, ASSIGN_NOT_DENIED lists is unchanged. Tri-state
in `main()`: approve / refuse-readable (prints nothing) / unreadable (deny). Assertions:
`cat 'x` and `git rebase 'main` denied naming the quote; the guards' cases still prompt.

## §5 Scratch arguments (D4)

`scratch_entry_allowed(prog, args)`: after the script, each further argument must be
confined — `token_confined(token, cwd, root)` against the project root OR
`lexically_inside`/`inside` the scratch root — else prompt. A flag BEFORE the script
(`bash -x <scratch>/x.sh`) still prompts (`SCRATCH_SCRIPT_ARG_COUNT` becomes "at least
one", with the first being the script). Assertions in `hook-escalation.sh` (the scratch
entry point lives there): a repo-confined arg approved, a scratch-confined arg approved,
`/etc/passwd` prompts, `bash -x` prompts.

## §6 Names and the reason (D5)

- `sweep.sh` dropped from the hook's comment/table and the two test lists; `grep -rn
  "sweep\.sh" hooks/ self/tests/allow-repo-commands.sh` finds nothing.
- `GIT_DENY_REASON` names both ends: `feature-start.sh` is the way in (branch + worktree,
  run by the human from the primary; its next run prunes merged ones) and
  `feature-close.sh` is the way out — run from the feature's worktree, on its branch,
  BEFORE the merge; merging the PR is what nothing runs after. The test's
  `GIT_REASON_WORDS` gains `feature-close.sh`; `GIT_REASON_ABSENT` and the group "the git
  deny no longer names feature-close.sh" are deleted; `hooks/README.md` § "The git shape"
  paragraph reversed; nothing in hooks/ says the close runs after the merge.

## §7 The policy's own Edit rule (D6) — DECIDED: an `ask` rule

Confirmed from the Claude Code permissions docs (code.claude.com/docs/en/permissions.md,
permission-modes.md): `permissions.ask` exists beside allow/deny; an ask rule is evaluated
before allow rules and forces a prompt even under `acceptEdits`; in headless `claude -p`
a matching ask is DENIED (no terminal); `**` globs work in ask and deny rules at any
depth and a leading `/` anchors to the project root; an `Edit(...)` rule covers the Write
tool too. Known limit to state in the README: under `bypassPermissions` an ask does not
fire (only deny binds there); the runners launch with `acceptEdits`, never bypass.

The `hooks/` rule becomes an `ask` rule spelled at any depth —
`Edit(**/agentTooling/hooks/**)` vendored, `Edit(**/hooks/**)` self (plus the root form
`/hooks/**` as the insurance the other pairs have) — so an attended session prompts the
human (which is what the comment already claims) and a headless executor, which cannot
answer, is refused; a worktree copy is covered at any depth from a primary-rooted
session. Fallback if `ask` is not honoured under acceptEdits or by `claude -p`: keep
`deny`, add the `**/hooks/**` spelling for self. Either way `wire-settings.py` writes
it, `--self --write` regenerates `.claude/settings.json`, and `hook-wiring.sh`'s lists
move with it. `wire-settings.py` maintains `permissions.ask` with the same merge rules
as `permissions.deny` (appended when absent, `INVALID` on the wrong type); the statuses
gain nothing new. Assertion: `wire-settings.py --self --check` passes on the committed
file; the rule list contains the any-depth spelling.

## §8 Bare entry-point names (D7)

`entry_script`: approve `gate.sh`/`check-plans.sh` only when the token carries a directory
component (`./x`, `self/gate.sh`, an absolute path); a bare `check-plans.sh` prompts, since
bash resolves it along `$PATH`. Test's expectation for the bare form flips to prompt.

## §9 `git branch --list` (D8)

`git_mutates`: after `--list` or `-l`, a positional is a pattern. `git branch --list
'feat*'` not denied; added to the test's read-only git list.

## §10 Deliberately excluded

- The vendored `agentTooling/.claude/settings.json`: nothing reads it today; git subtree
  cannot exclude a path; left as the backlog entry says, with the assertion still there.
- The per-feature budget and `git stash list`: user's decision.
- `hooks/` in a consuming repo's `.worktrees/`: covered by the any-depth spelling.
- The opaque deny's scope beyond the seven shapes (a structural refusal such as `cat x >
  out.txt`): its backlog entry stands; "unreadable" is about what the line hides, and a
  redirect hides nothing.
- Regenerating consuming repos' `.claude/settings.json`: each repo's next `sync-plans.sh`
  merges the new rules in; nothing here reaches into another repo.

## §11 Tests (the acceptance list; written first, red)

`self/tests/allow-repo-commands.sh`: D3 two denials + guards; D5 reason words + no
sweep.sh; D7 bare form prompts, `./` form approved; D8 `--list` not denied; the five
worktree/branch DENY cases beside their NOT_DENIED twins. `self/tests/hook-wiring.sh`:
BASH_DENY list rendered from `policy.bash_deny_rules()` (import it, do not retype), the
self file's byte-equality check, the ask/deny spelling. `self/tests/hook-escalation.sh`:
D4. A new tiny `self/tests/policy-table.sh` (or a phase in hook-wiring) asserting
`bash_deny_rules()` covers every MUTATING worktree subcommand and every branch flag in
the table — the twins cannot drift again. `self/gate.sh` enumerates it.

## §12 Build

One opus implementer (hooks/ is one module; nothing to parallelise), direct method,
tests first, from the worktree. The implementer edits the WORKTREE's hooks/ — which the
primary's current `Edit(/hooks/**)` does not cover (the very hole D6 closes); after this
feature merges, hooks/ edits go through the ask rule.
