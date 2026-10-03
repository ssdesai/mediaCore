#!/usr/bin/env bash
set -uo pipefail

# Self-test for hooks/policy.py, the one table the hook and the settings writer both read
# (hooks/README.md → "Editing the policy"). Run by self/gate.sh, or by hand:
# bash self/tests/policy-table.sh
#
# The git policy used to be written twice — the `GIT_*` mutation constants in
# hooks/allow-repo-commands.sh and a hand-typed `BASH_DENY_RULES` tuple in
# hooks/wire-settings.py — and the two drifted: five shapes the hook denied
# (`git worktree move|lock|unlock|repair`, `git branch --delete|--move`) had no prefix
# rule at all. This file is the assertion that they cannot drift again. It imports the
# table, renders the prefix rules from it, and loads the hook itself (by path — it is
# Python with a .sh name) to judge each rendered rule with the hook's own reader.
#
# Asserts:
#   1. every MUTATING entry in the table renders exactly one prefix rule, in the fixed
#      order hooks/README.md documents, and every READ_ONLY entry renders none — no rule
#      matches `git stash list`/`show`, and the retired `Bash(git stash:*)` is listed for
#      removal rather than rendered;
#   2. every rule is a `Bash(git …:*)` PREFIX rule, or the EXACT `Bash(git stash)` for
#      the bare verb, and none is an allow rule;
#   3. the hook's own `git_mutates` denies the command each rendered rule names — the
#      twin check, which is what a drift in either direction fails;
#   4. and it does NOT deny the table's read-only spellings (`git worktree list`,
#      `git branch --list <pattern>`, a plain `git push`, `git reset <file>`);
#   5. neither script carries its own copy of the table any more: `wire-settings.py`
#      calls the renderer and `allow-repo-commands.sh` imports the constants.
#
# No model, no network, no filesystem of its own — it reads the checked-in tree, like
# self/tests/template-versions.sh.

AT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "policy-table"
python3 - "$AT/hooks" <<'PY'
import importlib.machinery
import importlib.util
import os
import sys

HOOKS = sys.argv[1]
sys.dont_write_bytecode = True
sys.path.insert(0, HOOKS)

fails = 0


def check(label, condition, detail=""):
    global fails
    if condition:
        print("  ok    %s" % label)
    else:
        print("  FAIL  %s%s" % (label, (" — " + str(detail)) if detail else ""))
        fails += 1


try:
    import policy
except ImportError as exc:
    print("  FAIL  hooks/policy.py imports — %s" % exc)
    sys.exit(1)


def load_hook():
    """The hook as a module. It is Python with a .sh name, so the loader is explicit."""
    path = os.path.join(HOOKS, "allow-repo-commands.sh")
    spec = importlib.util.spec_from_loader(
        "allow_repo_commands", importlib.machinery.SourceFileLoader(
            "allow_repo_commands", path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


try:
    hook = load_hook()
except Exception as exc:                      # noqa: BLE001 - reported, not raised
    print("  FAIL  hooks/allow-repo-commands.sh imports — %s" % exc)
    sys.exit(1)

RULES = policy.bash_deny_rules()

# ── 1: the rendering covers the table, in the documented order ────────────────
MUTATING_WORKTREE = policy.worktree_mutating()
READ_ONLY_WORKTREE = policy.worktree_read_only()
MUTATING_STASH = policy.stash_mutating()
READ_ONLY_STASH = policy.stash_read_only()
EXPECTED = (
    ["push --force", "push -f", "push --force-with-lease", "reset --hard"]
    + list(policy.GIT_ALWAYS_MUTATING)
    + ["stash %s" % s for s in MUTATING_STASH]
    + ["worktree %s" % s for s in MUTATING_WORKTREE]
    + ["checkout %s" % f for f in policy.GIT_CHECKOUT_BRANCH_FLAGS]
    + ["switch %s" % f for f in policy.GIT_SWITCH_BRANCH_FLAGS]
    + ["branch %s" % f for f in policy.GIT_BRANCH_MUTATING_FLAGS]
)
# The bare verbs a prefix cannot name without also naming their read-only subcommands:
# `Bash(git stash:*)` denied `git stash list` too, so bare `git stash` is an EXACT rule,
# rendered after every prefix rule.
EXPECTED_EXACT = ["stash"]
check("1a. one prefix rule per mutating entry, in the table's order, then the exact ones",
      list(RULES) == (["Bash(git %s:*)" % c for c in EXPECTED]
                      + ["Bash(git %s)" % c for c in EXPECTED_EXACT]),
      "got %s" % list(RULES))
check("1f. every MUTATING stash subcommand has a rule (%d)" % len(MUTATING_STASH),
      all("Bash(git stash %s:*)" % s in RULES for s in MUTATING_STASH), MUTATING_STASH)
# A prefix rule matches every command that begins with its text, so a rule that begins
# a read-only spelling denies it whatever the hook says — deny rules beat the hook's allow.
READ_ONLY_STASH_COMMANDS = ["git stash %s" % s for s in READ_ONLY_STASH]


def rule_matches(rule, command):
    if rule.endswith(":*)"):
        return command.startswith(rule[len("Bash("):-len(":*)")])
    return command == rule[len("Bash("):-len(")")]


check("1g. no rule matches a READ_ONLY stash spelling (%s)" % READ_ONLY_STASH_COMMANDS,
      not any(rule_matches(r, c) for r in RULES for c in READ_ONLY_STASH_COMMANDS),
      [r for r in RULES for c in READ_ONLY_STASH_COMMANDS if rule_matches(r, c)])
check("1h. `Bash(git stash:*)` is retired: not rendered, and listed for removal",
      "Bash(git stash:*)" not in RULES
      and "Bash(git stash:*)" in policy.retired_bash_deny_rules()
      and not set(policy.retired_bash_deny_rules()) & set(RULES))
check("1b. every MUTATING worktree subcommand has a rule (%d)" % len(MUTATING_WORKTREE),
      all(any("worktree %s" % s in r for r in RULES) for s in MUTATING_WORKTREE),
      MUTATING_WORKTREE)
check("1c. no READ_ONLY worktree subcommand has one",
      not any("worktree %s" % s in r for s in READ_ONLY_WORKTREE for r in RULES),
      READ_ONLY_WORKTREE)
check("1d. every branch mutating flag has a rule (%d)"
      % len(policy.GIT_BRANCH_MUTATING_FLAGS),
      all(any(r == "Bash(git branch %s:*)" % f for r in RULES)
          for f in policy.GIT_BRANCH_MUTATING_FLAGS))
check("1e. no rule is rendered twice", len(set(RULES)) == len(RULES))

# ── 2: they are prefix rules, and never allow rules ──────────────────────────
check("2a. every rule is a Bash(git …:*) prefix rule, or an exact one for a bare verb",
      all(r.startswith("Bash(git ") and (r.endswith(":*)")
                                         or r in ["Bash(git %s)" % c
                                                  for c in EXPECTED_EXACT])
          for r in RULES))
check("2b. nothing here renders an allow rule",
      not any("allow" in r.lower() for r in RULES))

# ── 3: the twin — the hook denies what each rule names ───────────────────────
for rule in RULES:
    suffix = ":*)" if rule.endswith(":*)") else ")"
    command = rule[len("Bash("):-len(suffix)]
    args = hook.git_subcommand_args(command.split())
    check("3. the hook denies %r" % command,
          args is not None and hook.git_mutates(args))

# ── 4: and does not deny the table's read-only spellings ─────────────────────
READ_ONLY_COMMANDS = (
    ["git worktree %s" % s for s in READ_ONLY_WORKTREE]
    + READ_ONLY_STASH_COMMANDS
    + ["git branch %s feat*" % f for f in policy.GIT_BRANCH_LIST_FLAGS]
    + ["git push", "git push origin main", "git reset README.md",
       "git branch --show-current", "git branch --merged main"]
)
for command in READ_ONLY_COMMANDS:
    args = hook.git_subcommand_args(command.split())
    check("4. the hook does not deny %r" % command,
          args is not None and not hook.git_mutates(args))

# ── 5: neither script keeps its own copy ─────────────────────────────────────
with open(os.path.join(HOOKS, "wire-settings.py")) as handle:
    wire_source = handle.read()
check("5a. wire-settings.py renders the rules from the table",
      "policy.bash_deny_rules()" in wire_source)
check("5b. wire-settings.py has no BASH_DENY_RULES tuple of its own",
      "BASH_DENY_RULES = (" not in wire_source)
with open(os.path.join(HOOKS, "allow-repo-commands.sh")) as handle:
    hook_source = handle.read()
check("5c. allow-repo-commands.sh imports the table",
      "import policy" in hook_source)
check("5d. allow-repo-commands.sh spells no git constant of its own",
      "GIT_ALWAYS_MUTATING = frozenset" not in hook_source
      and "GIT_BRANCH_MUTATING_FLAGS = frozenset" not in hook_source)
check("5e. the hook's constants are the table's",
      hook.GIT_ALWAYS_MUTATING is policy.GIT_ALWAYS_MUTATING
      and hook.GIT_BRANCH_MUTATING_FLAGS is policy.GIT_BRANCH_MUTATING_FLAGS)

sys.exit(1 if fails else 0)
PY
rc=$?
if (( rc == 0 )); then echo "policy-table: all checks passed"; else echo "policy-table: FAILED"; fi
exit "$rc"
