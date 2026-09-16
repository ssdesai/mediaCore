#!/usr/bin/env python3
"""PreToolUse hook: approve read-only and test Bash commands confined to this repo, and
deny a chained cd, a git command that moves a ref, or a path decided at run time.

Claude Code runs this before the Bash permission check. It prints an "allow" decision
only when the whole command is provably confined to the project root and built from a
fixed allowlist of read/test programs and the harness's own read-only entry points. It
prints a "deny" decision for exactly three shapes: a `cd` or `pushd` sharing the command
with anything else; a git command that moves a ref, rewrites history or throws work
away (LIFECYCLE.md → "The three rules", rule 2); and an assignment at command position
whose own `$NAME` is used later on the same line, whose reason says to inline the
literal. Each is always a mistake with a
mechanical answer, and a deny puts that answer in front of the model instead of spending
an approval from the human. Everything else it prints nothing for, and the normal
permission flow runs.

Its reason for existing is `permissions.blockReadsOutsideWorkingDirectories`: that
fence stops any command whose paths resolve at run time, which is every
`cd X && cmd` chain, even for `ls` inside the repo. CONVENTIONS.md § Shell commands
tells agents not to write that shape; this hook answers the ones that still do.

Every approval rule below is a refusal, and the default is to refuse: a token the
analysis does not understand makes the whole command fall through to the normal prompt.
The threat model is an agent that has read access to the repo and is trying to turn an
auto-approved read into a read outside it, a write, or an execution — see
README.md § What it approves for the cases that were found and closed.
"""

import glob
import json
import os
import re
import shlex
import sys

# Hook protocol
HOOK_EVENT = "PreToolUse"
MATCHED_TOOL = "Bash"
DECISION_ALLOW = "allow"
DECISION_REASON = "allow-repo-commands: read/test command confined to the project root"
DECISION_DENY = "deny"
DENY_REASON = (
    "allow-repo-commands: don't chain cd with other commands (CONVENTIONS.md § Shell "
    "commands). A path after a chained cd resolves only at run time, so the call stops "
    "for approval. Run `cd <absolute path>` as its own Bash call and the command as the "
    "next one, or name every path absolutely and drop the cd.")
ASSIGN_DENY_REASON = (
    "allow-repo-commands: don't assign a path and then use it — a value decided at run "
    "time is exactly what the reads fence cannot check (CONVENTIONS.md § Shell commands). "
    "You already have the literal: inline it in each command, one command per call, "
    "instead of NAME=value and $NAME.")
GIT_DENY_REASON = (
    "allow-repo-commands: this git command moves a ref, rewrites history or throws work "
    "away, and agents never do that (LIFECYCLE.md § The three rules, rule 2). "
    "feature-start.sh is the only way in — it makes the branch and the worktree — and "
    "feature-close.sh the only way out; both are run by the human from the primary "
    "checkout. Commit on the branch you are on and say what you need instead.")

# Project root resolution
PROJECT_DIR_ENV = "CLAUDE_PROJECT_DIR"

# Chain detection. A directory change sharing a command with anything else is denied.
# Unlike the approval analysis, a line break separates commands here, as it does in bash.
CHDIR_PROGRAMS = frozenset(["cd", "pushd"])
CHAIN_PUNCTUATION = "();<>|&\n"
CHAIN_WHITESPACE = " \t\r"
SUBSHELL_OPEN, SUBSHELL_CLOSE = "(", ")"
# A `(` directly after a word ending in this opens a command substitution
SUBSTITUTION_PREFIX = "$"
REDIRECT_CHARS = frozenset("<>")
HEREDOC_OPERATOR = "<<"

# Comments. shlex starts a comment at a `#` anywhere, bash only at the start of a word, so
# `ls x#; rm -rf src` would lex as `ls x`. Both analyses turn shlex comments off: the
# approval analysis then checks every word bash runs (a real comment's words included),
# and chain detection does not judge a command with a `#` in it at all.
SHLEX_NO_COMMENTERS = ""
COMMENT_CHAR = "#"

# Shell structure. shlex splits runs of PUNCTUATION into their own tokens; any such
# token that is not a recognised separator (`|&`, `;;`, `(`, `>&`, ...) is refused.
SUBCOMMAND_SEPARATORS = frozenset(["&&", "||", ";", "|", "&"])
PUNCTUATION = frozenset("();<>|&")
# Redirect forms that name no real file, matched as whole words (a separator may follow)
HARMLESS_REDIRECT_RE = re.compile(
    r"(?<!\S)(?:2>&1|[12]?>>?\s*/dev/null|&>\s*/dev/null)(?![^\s;|&])")
# Characters the shell acts on outside single quotes: redirection, variable and
# command substitution. Inside single quotes they are literal.
SHELL_ACTIVE_CHARS = frozenset("<>$`")
QUOTE_SINGLE, QUOTE_DOUBLE, ESCAPE = "'", '"', "\\"
# Text the analysis cannot see through even when quoted: parent traversal, line breaks,
# and a NUL, which bash truncates at while this analysis would read past it
UNANALYSABLE = ("..", "\n", "\r", "\x00")
# A token beginning with this expands to a home directory
TILDE = "~"
FLAG_PREFIX = "-"
FLAG_VALUE_SEP = "="

# Brace expansion. Only a simple group — `{` + comma-separated alternatives, at least one
# comma, no brace, whitespace, quote, `$`, backtick or backslash inside, + `}` — is
# expanded; any other brace in a word refuses. A raw word ends at unquoted whitespace or
# one of RAW_WORD_BREAKS.
BRACE_CHARS = frozenset("{}")
BRACE_ALTERNATIVE_SEP = ","
BRACE_GROUP_RE = re.compile(r"\{[^{}\s'\"$`\\,]*(?:,[^{}\s'\"$`\\,]*)+\}")
QUOTING_CHARS = frozenset([QUOTE_SINGLE, QUOTE_DOUBLE, ESCAPE])
RAW_WORD_BREAKS = frozenset(";|&()<>")
MAX_BRACE_WORDS = 256

# Programs whose every allowed invocation only reads. `tree` (-o writes) and `uniq`
# (a second positional is an output file) are deliberately absent.
READ_ONLY_PROGRAMS = frozenset([
    "basename", "cat", "cut", "dirname", "du", "echo", "file", "find", "grep",
    "head", "ls", "printf", "pwd", "realpath", "rg", "sed", "sort", "stat",
    "tail", "tr", "wc", "which",
])
# Whole-token flags (or the part before "=") that make a reader write, execute a
# command, or follow symlinks out of the tree
FORBIDDEN_FLAGS = {
    "file": frozenset(["--compile"]),
    "find": frozenset(["-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint",
                       "-fprintf", "-fls", "-L", "-follow"]),
    "git": frozenset(["--output"]),
    "grep": frozenset(["--dereference-recursive"]),
    "rg": frozenset(["--pre", "--pre-glob", "--follow"]),
    "sort": frozenset(["--output", "--temporary-directory", "--compress-program"]),
}
# Letters that are refused anywhere in a single-dash token, which also catches the
# combined (-ni) and attached-value (-i.bak, -o/tmp/x) spellings
FORBIDDEN_SHORT_LETTERS = {
    "file": "C",
    "grep": "RS",
    "rg": "L",
    "sort": "oT",
}

# sed can write (`w`) and, on GNU, execute (`e`) from inside its script, so it is
# held to a grammar instead of a flag list: optional address or range, then `p`.
SED_ALLOWED_FLAGS = frozenset(["-n", "-E", "-r", "-nE", "-En", "-nr", "-rn"])
SED_ADDRESS = r"(?:\d+|\$|/[^/]*/)"
SED_PRINT_SCRIPT_RE = re.compile(r"^(?:%s(?:,%s)?)?p$" % (SED_ADDRESS, SED_ADDRESS))

# git subcommands that only read; `branch` and `worktree` are narrowed further
GIT_READ_ONLY_SUBCOMMANDS = frozenset([
    "blame", "branch", "describe", "diff", "log", "ls-files", "rev-parse",
    "shortlog", "show", "status", "worktree",
])
GIT_WORKTREE_READ_ONLY = frozenset(["list"])
# `git branch` mutates whenever it is given a positional, so only these flags pass
GIT_BRANCH_ALLOWED_FLAGS = frozenset([
    "-a", "--all", "-r", "--remotes", "-v", "-vv", "--verbose", "--list",
    "--show-current", "--merged", "--no-merged", "--color", "--no-color",
])
GIT_BRANCH_ALLOWED_FLAG_PREFIXES = ("--format=", "--sort=")

# ── The git deny ──────────────────────────────────────────────────────────────
# Every git shape that moves a ref, rewrites history or throws work away. This is the
# enforcement of LIFECYCLE.md rule 2; `BASH_DENY_RULES` in wire-settings.py is the same
# list written as `permissions.deny` prefix rules, which is the visible half of the
# policy. The two move together — a subcommand added here gets its rule there, and the
# comment there says so.
GIT_PROGRAM = "git"
# Global options between `git` and the subcommand. These take their value as the NEXT
# token, so `git -C /repo worktree add` would otherwise read `/repo` as the subcommand.
GIT_GLOBAL_VALUE_FLAGS = frozenset([
    "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env",
])
# Denied whatever their arguments, read-only spellings included: `git stash list` is one
# keystroke from `git stash`, and the prompt is the right place to tell them apart.
GIT_ALWAYS_MUTATING = frozenset(["clean", "stash", "rebase"])
GIT_PUSH = "push"
GIT_PUSH_FORCE_FLAGS = frozenset(["--force", "-f"])
GIT_PUSH_FORCE_LEASE_FLAG = "--force-with-lease"      # also `--force-with-lease=<ref>`
GIT_RESET = "reset"
GIT_RESET_MUTATING_FLAG = "--hard"
GIT_WORKTREE = "worktree"
GIT_WORKTREE_SAFE = GIT_WORKTREE_READ_ONLY            # `list` only, as the approval has it
GIT_CHECKOUT = "checkout"
GIT_CHECKOUT_BRANCH_FLAGS = frozenset(["-b", "-B"])
GIT_SWITCH = "switch"
GIT_SWITCH_BRANCH_FLAGS = frozenset(["-c", "-C"])
GIT_BRANCH = "branch"
GIT_BRANCH_MUTATING_FLAGS = frozenset(["-d", "-D", "--delete", "-m", "-M", "--move"])
# Listing flags that take a value. Their value is a positional token, and `git branch`
# is judged by whether it has one — without this, `git branch --merged main` would deny.
GIT_BRANCH_VALUE_FLAGS = frozenset([
    "--contains", "--no-contains", "--merged", "--no-merged", "--points-at",
    "--sort", "--format", "--color",
])

# ── The run-time-value deny ───────────────────────────────────────────────────
# The generalisation of the chained `cd`: what blocks the reads fence is a path decided at
# run time, not several commands on a line. An assignment at COMMAND POSITION whose own
# `$NAME` appears later on the line is that shape at its plainest — and the one shape
# where the literal is provably still in hand, two words earlier, so the correction is a
# substitution rather than a rewrite. Everything else the rule asks for (`$(…)` in a path,
# a heredoc into an interpreter) stays prose in CONVENTIONS.md, because the fix there is a
# rewrite and a deny must not demand one.
#
# There is deliberately NO `BASH_DENY_RULES` twin in wire-settings.py, unlike the git
# deny: a `permissions.deny` entry is a command PREFIX, and this is a relation between two
# tokens anywhere on the line, which no prefix can express. Hook-only, by design.
#
# `NAME=` at the start of a word, the shell's own assignment shape.
ASSIGNMENT_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=")
# Builtins that take assignments as their arguments, so `export X=/p` is still an
# assignment at command position rather than a command being given a value.
ASSIGNMENT_BUILTINS = frozenset(["export"])
# `$NAME` and `${NAME}`. Not `$(…)`, which starts with `(` and matches nothing here.
VAR_USE_RE = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?")

# Multi-token program prefixes for the project's test and lint runners. `npm run`
# is held to named scripts because it executes whatever package.json says.
RUNNER_PREFIXES = (
    ("python", "-m", "pytest"),
    ("python", "-m", "ruff"),
    ("python", "-m", "mypy"),
    ("pytest",),
    ("ruff",),
    ("mypy",),
    ("npx", "playwright", "test"),
    ("npm", "run", "typecheck"),
    ("npm", "run", "build"),
    ("npm", "run", "test"),
    ("npm", "run", "lint"),
    ("npm", "test"),
)
# Runners that keep their meaning when spelled as a path, e.g. `.venv/bin/ruff`, and
# the spellings that are the same runner
RUNNER_BASENAMES = frozenset(["python", "python3", "pytest", "ruff", "mypy"])
RUNNER_ALIASES = {"python3": "python"}

# ── The harness's own entry points ────────────────────────────────────────────
# Matched by BASENAME, and only when the script path resolves inside the root, so one
# rule covers both spellings of the same script: `plans/gate.sh`,
# `agentTooling/check-plans.sh` and `agentTooling/analysis/report.py` in a consuming
# repo, `self/gate.sh`, `./check-plans.sh` and `analysis/report.py` in agentTooling's own
# checkout. A basename alone is never enough — `python3 /tmp/report.py` names the same
# file name and a different program. Each of these reads, or re-derives what it prints;
# anything that freezes a cost record, writes a manifest or moves a ref is absent on
# purpose and keeps prompting (feature-start.sh, feature-close.sh, sweep.sh,
# stamp-timing.sh, capture_planning.py --recapture/--all, manifest.py init and set-*).
ENTRY_GATE = "gate.sh"                      # gate.sh [<level label>]
ENTRY_GATE_MAX_ARGS = 1
ENTRY_CHECK_PLANS = "check-plans.sh"        # check-plans.sh [--self] <slug>
ENTRY_REPORT = "report.py"                  # report.py [--self] <slug> | --all
ENTRY_CAPTURE_PLANNING = "capture_planning.py"
ENTRY_MANIFEST = "manifest.py"
# capture_planning.py only in a listing form: --recapture, --all and --carry-lost (which
# implies --recapture) rewrite a frozen planning.json and cost real money to redo.
CAPTURE_LIST_PREFIX = "--list-"
CAPTURE_WRITING_FLAGS = frozenset(["--recapture", "--all", "--carry-lost"])
# manifest.py reads with `get`; `init` and every `set-*` rewrite the fence. The
# subcommand is the second positional (`manifest.py [--self] <slug> <subcommand>`), so
# it is read positionally — `manifest.py get init` is a feature named `get` being
# initialized, not a read.
MANIFEST_READ_SUBCOMMAND = "get"
MANIFEST_SUBCOMMAND_INDEX = 1
# Syntax checkers: `bash -n` parses without executing, and shellcheck only reads. Both
# take files and no other flag; every file is checked against the root like any path.
SYNTAX_BASH = "bash"
SYNTAX_BASH_PARSE_FLAG = "-n"
SYNTAX_SHELLCHECK = "shellcheck"
# `python3 [-B] -m py_compile <files>` — the gate's own python syntax check. -B keeps the
# interpreter from leaving a __pycache__ behind and is accepted wherever python is.
PYTHON_PROGRAM = "python"                   # program_name() aliases python3 to this
PYTHON_INTERPRETER_FLAGS = frozenset(["-B"])
PYTHON_PY_COMPILE = ("-m", "py_compile")


def project_root():
    root = os.environ.get(PROJECT_DIR_ENV)
    return os.path.realpath(root) if root else None


def inside(path, root):
    """Resolved through symlinks: a link inside the tree pointing out is outside."""
    resolved = os.path.realpath(path)
    return resolved == root or resolved.startswith(root + os.sep)


def lexically_inside(path, root):
    """Without following symlinks — for the program token only, where `.venv/bin/python`
    is a symlink to an interpreter outside the tree and that is the point of it."""
    normalized = os.path.normpath(path)
    return normalized == root or normalized.startswith(root + os.sep)


def program_name(token):
    base = os.path.basename(token)
    return RUNNER_ALIASES.get(base, base) if base in RUNNER_BASENAMES else token


def chains_chdir(command):
    """True when a cd or pushd shares the command with any other command. What it cannot
    tokenize, anything carrying a heredoc (whose body lines would read as commands), and
    anything with a `#` (which may hide a heredoc behind what bash reads as a comment) is
    never judged a chain: a deny must not fire on a guess."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=CHAIN_PUNCTUATION)
    lexer.whitespace = CHAIN_WHITESPACE
    lexer.whitespace_split = True
    lexer.commenters = SHLEX_NO_COMMENTERS
    try:
        tokens = list(lexer)
    except ValueError:
        return False
    if any(t.startswith(HEREDOC_OPERATOR) or COMMENT_CHAR in t for t in tokens):
        return False
    # A `$(…)` substitution is its own scope: a cd inside it moves no path the outer
    # command resolves (`x=$(cd dir && pwd)` is how a path is made absolute), so nothing
    # in it is a head, and the word after it is back where the `$(` left off. A plain
    # `(…)` subshell is not: its cd moves the commands beside it.
    heads, at_head, redirect_target, prev_word = [], True, False, ""
    open_parens = []  # (is_substitution, at_head when it opened), innermost last
    for t in tokens:
        if all(ch in CHAIN_PUNCTUATION for ch in t):
            if any(ch in REDIRECT_CHARS for ch in t):
                redirect_target = True
                continue
            for i, ch in enumerate(t):
                if ch == SUBSHELL_OPEN:
                    is_substitution = i == 0 and prev_word.endswith(SUBSTITUTION_PREFIX)
                    open_parens.append((is_substitution, at_head))
                    at_head = True
                elif ch == SUBSHELL_CLOSE and open_parens:
                    is_substitution, at_open = open_parens.pop()
                    at_head = at_open if is_substitution else False
                else:
                    at_head = True
            prev_word = ""
            continue
        prev_word = t
        if redirect_target:
            redirect_target = False
        elif at_head:
            if not any(is_substitution for is_substitution, _ in open_parens):
                heads.append(t)
            at_head = False
    return len(heads) > 1 and any(h in CHDIR_PROGRAMS for h in heads)


def command_words(command):
    """Every command on the line as its own word list — across separators, subshells and
    `$(…)` substitutions alike, since a deny is owed wherever the command runs. None when
    the line cannot be judged: text that does not tokenize, a heredoc (whose body lines
    would read as commands), or a `#` that may hide one. Those guards are `chains_chdir`'s,
    for the same reason: a deny must not fire on a guess."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=CHAIN_PUNCTUATION)
    lexer.whitespace = CHAIN_WHITESPACE
    lexer.whitespace_split = True
    lexer.commenters = SHLEX_NO_COMMENTERS
    try:
        tokens = list(lexer)
    except ValueError:
        return None
    if any(t.startswith(HEREDOC_OPERATOR) or COMMENT_CHAR in t for t in tokens):
        return None

    commands, current, at_head, redirect_target, prev_word = [], [], True, False, ""
    open_parens = []  # (is_substitution, at_head when it opened), innermost last

    def flush():
        if current:
            commands.append(list(current))
            del current[:]

    for t in tokens:
        if all(ch in CHAIN_PUNCTUATION for ch in t):
            if any(ch in REDIRECT_CHARS for ch in t):
                redirect_target = True
                continue
            for i, ch in enumerate(t):
                flush()
                if ch == SUBSHELL_OPEN:
                    is_substitution = i == 0 and prev_word.endswith(SUBSTITUTION_PREFIX)
                    open_parens.append((is_substitution, at_head))
                    at_head = True
                elif ch == SUBSHELL_CLOSE and open_parens:
                    is_substitution, at_open = open_parens.pop()
                    at_head = at_open if is_substitution else False
                else:
                    at_head = True
            prev_word = ""
            continue
        prev_word = t
        if redirect_target:
            redirect_target = False
        elif at_head:
            flush()
            current.append(t)
            at_head = False
        else:
            current.append(t)
    flush()
    return commands


def git_subcommand_args(words):
    """The tokens after `git` and its global options, or None when this is not git."""
    if not words or os.path.basename(words[0]) != GIT_PROGRAM:
        return None
    args = words[1:]
    while args and args[0].startswith(FLAG_PREFIX):
        takes_value = args[0].split(FLAG_VALUE_SEP, 1)[0] in GIT_GLOBAL_VALUE_FLAGS
        attached = FLAG_VALUE_SEP in args[0]
        args = args[2:] if (takes_value and not attached) else args[1:]
    return args


def git_mutates(args):
    """True when these subcommand tokens move a ref, rewrite history or throw work away."""
    if not args:
        return False
    subcommand, rest = args[0], args[1:]
    if subcommand in GIT_ALWAYS_MUTATING:
        return True
    if subcommand == GIT_PUSH:
        return any(a in GIT_PUSH_FORCE_FLAGS
                   or a.split(FLAG_VALUE_SEP, 1)[0] == GIT_PUSH_FORCE_LEASE_FLAG
                   for a in rest)
    if subcommand == GIT_RESET:
        return GIT_RESET_MUTATING_FLAG in rest
    if subcommand == GIT_WORKTREE:
        positional = [a for a in rest if not a.startswith(FLAG_PREFIX)]
        return bool(positional) and positional[0] not in GIT_WORKTREE_SAFE
    if subcommand == GIT_CHECKOUT:
        return any(a in GIT_CHECKOUT_BRANCH_FLAGS for a in rest)
    if subcommand == GIT_SWITCH:
        return any(a in GIT_SWITCH_BRANCH_FLAGS for a in rest)
    if subcommand == GIT_BRANCH:
        if any(a in GIT_BRANCH_MUTATING_FLAGS for a in rest):
            return True
        # A positional creates, renames or filters; the value of a listing flag is a
        # positional too, so it is consumed with its flag rather than counted.
        skip_next = False
        for token in rest:
            if skip_next:
                skip_next = False
                continue
            if token.startswith(FLAG_PREFIX):
                skip_next = (token.split(FLAG_VALUE_SEP, 1)[0] in GIT_BRANCH_VALUE_FLAGS
                             and FLAG_VALUE_SEP not in token)
                continue
            return True
    return False


def mutates_git_refs(command):
    """True when any command on the line is a ref-moving git command. Independent of the
    root and the cwd: the shape is wrong wherever it runs."""
    commands = command_words(command)
    if commands is None:
        return False
    for words in commands:
        # A brace is one more thing this analysis does not read: it performs no
        # expansion, so what git would really be handed is a guess. `git branch {-a,new}`
        # therefore prompts, exactly as it did before this deny existed, rather than
        # being denied on a reading that might be wrong. The approval analysis, which
        # does expand braces, still refuses it (self/tests/allow-repo-commands.sh).
        if any(ch in BRACE_CHARS for word in words for ch in word):
            continue
        args = git_subcommand_args(words)
        if args is not None and git_mutates(args):
            return True
    return False


def assigned_names(command):
    """`{NAME: offset}` for every variable assigned at command position on this line.

    A command whose words are *all* assignments is an assignment command (`X=/p`,
    `export X=/p A=1`); one with anything else after them is a command with an
    environment prefix (`X=1 make`), which decides nothing the shell then re-reads on
    the same line and is never denied. The offset is where the assignment is spelled, so
    a use can be required to come after it.

    Empty when the line cannot be judged: `command_words` returns None for a heredoc, a
    `#`, or text that does not tokenize — the same guards the other two denies keep,
    because a deny must not fire on a guess.
    """
    commands = command_words(command)
    if commands is None:
        return {}
    names = {}
    for words in commands:
        rest = list(words)
        while rest and rest[0] in ASSIGNMENT_BUILTINS:
            rest = rest[1:]
        matches = [ASSIGNMENT_RE.match(word) for word in rest]
        if not matches or not all(matches):
            continue
        for match in matches:
            names.setdefault(match.group(1), command.find(match.group(1) + FLAG_VALUE_SEP))
    return names


def active_var_uses(text):
    """`[(NAME, offset)]` for every `$NAME` the shell will expand — anywhere but inside
    single quotes or behind a backslash, the same reading `shell_active_outside_quotes`
    gives a `$`. `echo '$X'` is a literal string and is not a use."""
    uses = []
    in_single = in_double = escaped = False
    index = 0
    while index < len(text):
        char = text[index]
        if escaped:
            escaped = False
        elif char == ESCAPE and not in_single:
            escaped = True
        elif char == QUOTE_SINGLE and not in_double:
            in_single = not in_single
        elif char == QUOTE_DOUBLE and not in_single:
            in_double = not in_double
        elif char == SUBSTITUTION_PREFIX and not in_single:
            match = VAR_USE_RE.match(text, index)
            if match:
                uses.append((match.group(1), index))
                index = match.end()
                continue
        index += 1
    return uses


def uses_own_assignment(command):
    """True when a name assigned at command position is dereferenced later on the line."""
    names = assigned_names(command)
    if not names:
        return False
    for name, offset in active_var_uses(command):
        if name in names and offset > names[name]:
            return True
    return False


def entry_script(token, cwd, root, basename):
    """True when the token names `basename` and the file it spells is inside the root —
    resolved through symlinks, like every other path, and required to exist, so a
    basename on its own vouches for nothing."""
    if os.path.basename(token) != basename:
        return False
    path = token if token.startswith(os.sep) else os.path.join(cwd, token)
    return os.path.lexists(path) and inside(path, root)


def files_only(args):
    """True when every argument is a positional — a file, not a flag — and there is one."""
    return bool(args) and not any(a.startswith(FLAG_PREFIX) for a in args)


def syntax_check_allowed(prog, args):
    """`bash -n f…` parses without executing and `shellcheck f…` only reads. Any other
    flag, and `bash` without `-n`, runs what it is given and is not this."""
    if prog == SYNTAX_BASH:
        return args[:1] == [SYNTAX_BASH_PARSE_FLAG] and files_only(args[1:])
    if prog == SYNTAX_SHELLCHECK:
        return files_only(args)
    return False


def python_entry_allowed(args, cwd, root):
    """`python3 [-B] …`: the py_compile module over files, or one of the harness's
    read-only scripts, named by basename and resolved inside the root."""
    while args and args[0] in PYTHON_INTERPRETER_FLAGS:
        args = args[1:]
    if not args:
        return False
    if tuple(args[:len(PYTHON_PY_COMPILE)]) == PYTHON_PY_COMPILE:
        return files_only(args[len(PYTHON_PY_COMPILE):])
    script, script_args = args[0], args[1:]
    if entry_script(script, cwd, root, ENTRY_REPORT):
        return True
    if entry_script(script, cwd, root, ENTRY_CAPTURE_PLANNING):
        return (any(a.startswith(CAPTURE_LIST_PREFIX) for a in script_args)
                and not any(a in CAPTURE_WRITING_FLAGS for a in script_args))
    if entry_script(script, cwd, root, ENTRY_MANIFEST):
        positional = [a for a in script_args if not a.startswith(FLAG_PREFIX)]
        return (len(positional) > MANIFEST_SUBCOMMAND_INDEX
                and positional[MANIFEST_SUBCOMMAND_INDEX] == MANIFEST_READ_SUBCOMMAND)
    return False


def harness_entry_allowed(program_token, prog, args, cwd, root):
    """The harness's own entry points, above. Every argument has already been checked
    against the root by the caller; what is judged here is the script and the form."""
    if entry_script(program_token, cwd, root, ENTRY_GATE):
        return len(args) <= ENTRY_GATE_MAX_ARGS
    if entry_script(program_token, cwd, root, ENTRY_CHECK_PLANS):
        return True
    if syntax_check_allowed(prog, args):
        return True
    if prog == PYTHON_PROGRAM:
        return python_entry_allowed(args, cwd, root)
    return False


def shell_active_outside_quotes(text):
    """True when a SHELL_ACTIVE_CHARS character sits where the shell will act on it:
    anywhere but inside single quotes or behind a backslash. Unbalanced quotes count
    as active, since the shell's reading of them cannot be predicted here."""
    in_single = in_double = escaped = False
    for ch in text:
        if escaped:
            escaped = False
        elif ch == ESCAPE and not in_single:
            escaped = True
        elif ch == QUOTE_SINGLE and not in_double:
            in_single = not in_single
        elif ch == QUOTE_DOUBLE and not in_single:
            in_double = not in_double
        elif ch in SHELL_ACTIVE_CHARS and not in_single:
            return True
    return in_single or in_double


def raw_words(text):
    """The command's words as bash splits them, quote and backslash characters kept —
    shlex drops the quotes, and whether a brace was quoted is the question asked here."""
    words, current = [], []
    in_single = in_double = escaped = False
    for ch in text:
        if escaped:
            escaped = False
        elif ch == ESCAPE and not in_single:
            escaped = True
        elif ch == QUOTE_SINGLE and not in_double:
            in_single = not in_single
        elif ch == QUOTE_DOUBLE and not in_single:
            in_double = not in_double
        elif not (in_single or in_double) and (ch.isspace() or ch in RAW_WORD_BREAKS):
            if current:
                words.append("".join(current))
                current = []
            continue
        current.append(ch)
    if current:
        words.append("".join(current))
    return words


def single_quoted_word(word):
    body = word[1:-1]
    return (len(word) > 1 and word.startswith(QUOTE_SINGLE) and word.endswith(QUOTE_SINGLE)
            and QUOTE_SINGLE not in body and QUOTE_DOUBLE not in body)


def braces_simple(text):
    """True when every brace in the command is one bash reads literally (a wholly
    single-quoted word) or part of a simple group this analysis expands exactly as bash
    does. Quoting or escaping mixed into a braced word changes bash's reading, so it
    refuses; a single substitution pass leaves the outer braces of a nested group behind,
    so nesting refuses too."""
    for word in raw_words(text):
        if not any(ch in BRACE_CHARS for ch in word) or single_quoted_word(word):
            continue
        if any(ch in QUOTING_CHARS for ch in word):
            return False
        if any(ch in BRACE_CHARS for ch in BRACE_GROUP_RE.sub("", word)):
            return False
    return True


def expand_braces(token):
    """Every word bash makes of the token: groups expanded left to right and cartesian,
    empty words dropped as bash drops them. None past MAX_BRACE_WORDS."""
    words, pos = [""], 0
    for match in BRACE_GROUP_RE.finditer(token):
        prefix = token[pos:match.start()]
        alternatives = match.group()[1:-1].split(BRACE_ALTERNATIVE_SEP)
        words = [w + prefix + alt for w in words for alt in alternatives]
        if len(words) > MAX_BRACE_WORDS:
            return None
        pos = match.end()
    return [w + token[pos:] for w in words if w + token[pos:]]


def expanded_argv(parts):
    """The subcommand as bash will run it, each token replaced in place by its brace
    expansion. None when a token expands past the cap."""
    argv = []
    for token in parts:
        words = expand_braces(token)
        if words is None:
            return None
        argv.extend(words)
    return argv


def split_subcommands(tokens):
    groups, current = [], []
    for token in tokens:
        if token in SUBCOMMAND_SEPARATORS:
            groups.append(current)
            current = []
        else:
            current.append(token)
    groups.append(current)
    return [g for g in groups if g]


def value_confined(value, cwd, root):
    """A path-like value must resolve inside the root. Relative values are resolved
    against the effective cwd and expanded as globs first, so `dir/*` is judged by
    what it will actually name. A value that names nothing on disk is not a path."""
    if not value or value.startswith(FLAG_PREFIX):
        return True
    if value.startswith(os.sep):
        return inside(value, root)
    candidate = os.path.join(cwd, value)
    for match in glob.glob(candidate) or [candidate]:
        if os.path.lexists(match) and not inside(match, root):
            return False
    return True


def token_confined(token, cwd, root):
    """Bare flags carry no path; `--flag=value` and `key=value` carry one in the value."""
    if FLAG_VALUE_SEP in token:
        return value_confined(token.split(FLAG_VALUE_SEP, 1)[1], cwd, root)
    return value_confined(token, cwd, root)


def flag_forbidden(prog, token):
    if not token.startswith(FLAG_PREFIX):
        return False
    name = token.split(FLAG_VALUE_SEP, 1)[0]
    if name in FORBIDDEN_FLAGS.get(prog, frozenset()):
        return True
    letters = FORBIDDEN_SHORT_LETTERS.get(prog)
    if letters and not token.startswith(FLAG_PREFIX * 2):
        return any(ch in letters for ch in token[1:])
    return False


def sed_allowed(args):
    """(allowed, file arguments). The script positional is judged by the grammar and
    is not a path even when a regex address makes it start with `/`."""
    flags = [a for a in args if a.startswith(FLAG_PREFIX)]
    positionals = [a for a in args if not a.startswith(FLAG_PREFIX)]
    if any(f not in SED_ALLOWED_FLAGS for f in flags) or not positionals:
        return False, []
    return bool(SED_PRINT_SCRIPT_RE.match(positionals[0])), positionals[1:]


def git_allowed(args):
    if not args or args[0] not in GIT_READ_ONLY_SUBCOMMANDS:
        return False
    if any(flag_forbidden("git", a) for a in args[1:]):
        return False
    if args[0] == "worktree":
        return len(args) >= 2 and args[1] in GIT_WORKTREE_READ_ONLY
    if args[0] == "branch":
        return all(
            a in GIT_BRANCH_ALLOWED_FLAGS or a.startswith(GIT_BRANCH_ALLOWED_FLAG_PREFIXES)
            for a in args[1:]
        )
    return True


def runner_allowed(head):
    for prefix in RUNNER_PREFIXES:
        if len(head) >= len(prefix) and tuple(head[:len(prefix)]) == prefix:
            return True
    return False


def subcommand_allowed(parts, cwd, root):
    """(allowed, cwd after this subcommand)."""
    if not parts or any(all(ch in PUNCTUATION for ch in p) for p in parts):
        return False, cwd

    program_token = parts[0]
    prog = program_name(program_token)
    args = parts[1:]

    if prog == "cd":
        # A bare `cd` goes home; a relative target resolves somewhere we cannot see.
        if len(args) != 1 or not args[0].startswith(os.sep) or not inside(args[0], root):
            return False, cwd
        return True, os.path.realpath(args[0])

    if program_token.startswith(os.sep) and not (
        lexically_inside(program_token, root) or inside(program_token, root)
    ):
        return False, cwd

    if prog == "sed":
        allowed, files = sed_allowed(args)
        return allowed and all(token_confined(a, cwd, root) for a in files), cwd

    if not all(token_confined(a, cwd, root) for a in args):
        return False, cwd

    if harness_entry_allowed(program_token, prog, args, cwd, root):
        return True, cwd

    if prog == "git":
        return git_allowed(args), cwd
    if prog in READ_ONLY_PROGRAMS:
        return not any(flag_forbidden(prog, a) for a in args), cwd
    return runner_allowed([prog] + args), cwd


def expansion_allowed(parts, cwd, root):
    """(allowed, cwd after this subcommand). Both the literal tokens and their brace
    expansion must pass: the literal pass keeps a quoted `'{-a,-v}'` from approving
    what its expansion would, and the expanded pass checks every word bash will see,
    including a `~` that only appears after expansion."""
    expanded = expanded_argv(parts)
    if not expanded or any(w.startswith(TILDE) for w in expanded):
        return False, cwd
    literal_ok, _ = subcommand_allowed(parts, cwd, root)
    expanded_ok, next_cwd = subcommand_allowed(expanded, cwd, root)
    return literal_ok and expanded_ok, next_cwd


def command_allowed(command, cwd, root):
    if any(bad in command for bad in UNANALYSABLE):
        return False
    stripped = HARMLESS_REDIRECT_RE.sub("", command)
    if shell_active_outside_quotes(stripped) or not braces_simple(stripped):
        return False

    lexer = shlex.shlex(stripped, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = SHLEX_NO_COMMENTERS
    try:
        tokens = list(lexer)
    except ValueError:
        return False
    if any(t.startswith(TILDE) for t in tokens):
        return False

    groups = split_subcommands(tokens)
    if not groups:
        return False
    for parts in groups:
        allowed, cwd = expansion_allowed(parts, cwd, root)
        if not allowed:
            return False
    return True


def emit(decision, reason):
    json.dump({"hookSpecificOutput": {
        "hookEventName": HOOK_EVENT,
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}, sys.stdout)


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return
    if payload.get("tool_name") != MATCHED_TOOL:
        return

    command = (payload.get("tool_input") or {}).get("command")
    if not isinstance(command, str) or not command.strip():
        return

    # Neither deny needs a root or a cwd: both shapes are wrong wherever they run. The
    # chained cd goes first — it is the one whose reason fits every command on the line.
    try:
        chained = chains_chdir(command)
    except Exception:  # an analysis failure is never a deny
        chained = False
    if chained:
        emit(DECISION_DENY, DENY_REASON)
        return

    try:
        mutating = mutates_git_refs(command)
    except Exception:  # an analysis failure is never a deny
        mutating = False
    if mutating:
        emit(DECISION_DENY, GIT_DENY_REASON)
        return

    try:
        run_time_value = uses_own_assignment(command)
    except Exception:  # an analysis failure is never a deny
        run_time_value = False
    if run_time_value:
        emit(DECISION_DENY, ASSIGN_DENY_REASON)
        return

    root = project_root()
    cwd = payload.get("cwd")
    # Without a known starting directory inside the root, a relative path in the
    # command could resolve anywhere.
    if not root or not isinstance(cwd, str) or not inside(cwd, root):
        return

    try:
        allowed = command_allowed(command, os.path.realpath(cwd), root)
    except Exception:  # any analysis failure is a refusal, never an approval
        allowed = False
    if allowed:
        emit(DECISION_ALLOW, DECISION_REASON)


if __name__ == "__main__":
    main()
