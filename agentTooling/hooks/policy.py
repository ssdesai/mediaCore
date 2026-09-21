"""The git policy as data: one table the hook and the settings writer both read.

`allow-repo-commands.sh` enforces LIFECYCLE.md rule 2 by reading every command on the
line; `wire-settings.py` writes the visible half of the same policy into
`permissions.deny` as command PREFIX rules, which is what `/permissions` shows. Those
two lists used to be written twice — `GIT_*` constants in the hook, a hand-typed
`BASH_DENY_RULES` tuple in the writer — and they drifted: five shapes the hook denied had
no prefix rule at all (`git worktree move|lock|unlock|repair`, `git branch
--delete|--move`). They are one table now. The constants below are what the hook reads,
`bash_deny_rules()` renders the prefix twin from those same constants, and
`self/tests/policy-table.sh` asserts the rendering covers every mutating entry and that
the hook's own reader denies each rendered rule — so an entry added here reaches both
halves, and a drift fails the gate rather than a consuming repo.

Both scripts import this as a sibling, since neither is run from a fixed directory —
`allow-repo-commands.sh` is a hook command Claude Code invokes from wherever the session
sits, `wire-settings.py` is called with a `--repo` that is somebody else's checkout:

    sys.dont_write_bytecode = True
    sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
    import policy

Standard library only, like the two scripts it serves, and no I/O at all: a table and one
renderer over it.

**Order is part of the contract.** Every constant a rule is rendered from is an ordered
tuple rather than a frozenset, because `bash_deny_rules()`'s output is compared byte for
byte with the committed `.claude/settings.json` (`wire-settings.py --self --check`, which
`self/gate.sh` records) and a frozenset has no order to compare. Membership reads the
same either way.

What is deliberately NOT here: the hook's *approval* constants
(`GIT_READ_ONLY_SUBCOMMANDS`, `GIT_BRANCH_ALLOWED_FLAGS`, the flag lists), which answer a
different question — "is this command confined and read-only?" rather than "does it move
a ref?" — and have no twin in the settings file. They stay in the hook, beside the
analysis that uses them.
"""

# The program every rule here names
GIT_PROGRAM = "git"

# How a subcommand is marked in GIT_WORKTREE_SUBCOMMANDS below
READ_ONLY = "read-only"
MUTATING = "mutating"

# Denied whatever their arguments, read-only spellings included: `git stash list` is one
# keystroke from `git stash`, and the prompt is the right place to tell them apart.
GIT_ALWAYS_MUTATING = ("clean", "stash", "rebase")

# `git push`, denied only when it is forced
GIT_PUSH = "push"
GIT_PUSH_FORCE_FLAGS = ("--force", "-f")
GIT_PUSH_FORCE_LEASE_FLAG = "--force-with-lease"      # also `--force-with-lease=<ref>`

# `git reset`, denied only when it throws the working tree away
GIT_RESET = "reset"
GIT_RESET_MUTATING_FLAG = "--hard"

# Every subcommand `git worktree` takes, and whether it only reads. The hook denies any
# subcommand not marked READ_ONLY — an unknown one included, since a subcommand nothing
# here has heard of is not one anything here can vouch for — and the prefix rules
# enumerate the MUTATING ones, in this order.
GIT_WORKTREE = "worktree"
GIT_WORKTREE_SUBCOMMANDS = {
    "list": READ_ONLY,
    "add": MUTATING,
    "remove": MUTATING,
    "prune": MUTATING,
    "move": MUTATING,
    "lock": MUTATING,
    "unlock": MUTATING,
    "repair": MUTATING,
}

# The three ways to make a branch or rename one
GIT_CHECKOUT = "checkout"
GIT_CHECKOUT_BRANCH_FLAGS = ("-b", "-B")
GIT_SWITCH = "switch"
GIT_SWITCH_BRANCH_FLAGS = ("-c", "-C")
GIT_BRANCH = "branch"
GIT_BRANCH_MUTATING_FLAGS = ("-d", "-D", "--delete", "-m", "-M", "--move")
# After one of these a positional is a PATTERN to filter the listing by, not a name to
# create: `git branch --list 'feat*'` reads and moves nothing. No prefix rule is rendered
# for them — they are how the hook reads a positional, not a shape it denies.
GIT_BRANCH_LIST_FLAGS = ("--list", "-l")

# The prefix rule's spelling in `permissions.deny`. The `:*` is what makes it a prefix,
# and a rule this helper writes is never an allow rule.
BASH_RULE_TEMPLATE = "Bash(%s:*)"
RULE_WORD_SEPARATOR = " "


def _worktree_subcommands(kind):
    return tuple(name for name, marked in GIT_WORKTREE_SUBCOMMANDS.items()
                 if marked == kind)


def worktree_read_only():
    """The `git worktree` subcommands that only read — what the hook's approval side and
    its git deny both take as the safe list."""
    return _worktree_subcommands(READ_ONLY)


def worktree_mutating():
    """The ones that make, move or destroy a worktree, in the table's order."""
    return _worktree_subcommands(MUTATING)


def denied_git_commands():
    """Every mutating git shape a command prefix can express, as the words the prefix
    names, in the fixed order `hooks/README.md` documents: push force ×3, reset --hard,
    the always-mutating verbs, worktree, checkout, switch, branch.

    What is missing from this list is missing because no prefix can say it, not because
    the hook lets it through: `git -C /repo worktree add x` and `x=$(git rebase main)`
    match no prefix rule at all, and the hook — which reads every command on the line —
    is the whole of the enforcement. These rules are the visible half.
    """
    commands = []
    for flag in GIT_PUSH_FORCE_FLAGS + (GIT_PUSH_FORCE_LEASE_FLAG,):
        commands.append((GIT_PUSH, flag))
    commands.append((GIT_RESET, GIT_RESET_MUTATING_FLAG))
    commands.extend((verb,) for verb in GIT_ALWAYS_MUTATING)
    commands.extend((GIT_WORKTREE, sub) for sub in worktree_mutating())
    commands.extend((GIT_CHECKOUT, flag) for flag in GIT_CHECKOUT_BRANCH_FLAGS)
    commands.extend((GIT_SWITCH, flag) for flag in GIT_SWITCH_BRANCH_FLAGS)
    commands.extend((GIT_BRANCH, flag) for flag in GIT_BRANCH_MUTATING_FLAGS)
    return tuple(RULE_WORD_SEPARATOR.join((GIT_PROGRAM,) + words) for words in commands)


def bash_deny_rules():
    """`denied_git_commands()` as `permissions.deny` prefix rules. `wire-settings.py`
    writes exactly this tuple, in this order, and `--self --check` compares the result
    byte for byte with the committed file."""
    return tuple(BASH_RULE_TEMPLATE % command for command in denied_git_commands())
