#!/usr/bin/env python3
"""PreToolUse hook: approve read-only and test Bash commands confined to this repo.

Claude Code runs this before the Bash permission check. It prints an "allow"
decision only when the whole command is provably confined to the project root and
built from a fixed allowlist of read/test programs; otherwise it prints nothing and
the normal permission flow runs. It never prints "deny" — this hook removes
prompts, it does not add refusals.

Its reason for existing is `permissions.blockReadsOutsideWorkingDirectories`: that
fence stops any command whose paths resolve at run time, which is every
`cd X && cmd` chain, even for `ls` inside the repo. CONVENTIONS.md § Shell commands
tells agents not to write that shape; this hook covers the ones that still do.

Every rule below is a refusal, and the default is to refuse: a token the analysis
does not understand makes the whole command fall through to the normal prompt. The
threat model is an agent that has read access to the repo and is trying to turn an
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

# Project root resolution
PROJECT_DIR_ENV = "CLAUDE_PROJECT_DIR"

# Shell structure. shlex splits runs of PUNCTUATION into their own tokens; any such
# token that is not a recognised separator (`|&`, `;;`, `(`, `>&`, ...) is refused.
SUBCOMMAND_SEPARATORS = frozenset(["&&", "||", ";", "|", "&"])
PUNCTUATION = frozenset("();<>|&")
# Redirect forms that name no real file, matched as whole words (a separator may follow)
HARMLESS_REDIRECT_RE = re.compile(
    r"(?<!\S)(?:2>&1|[12]?>>?\s*/dev/null|&>\s*/dev/null)(?![^\s;|&])")
# Characters the shell acts on outside single quotes: redirection, variable and
# command substitution, brace expansion. Inside single quotes they are literal.
SHELL_ACTIVE_CHARS = frozenset("<>$`{}")
QUOTE_SINGLE, QUOTE_DOUBLE, ESCAPE = "'", '"', "\\"
# Text the analysis cannot see through even when quoted: parent traversal, line breaks,
# and a NUL, which bash truncates at while this analysis would read past it
UNANALYSABLE = ("..", "\n", "\r", "\x00")
# A token beginning with this expands to a home directory
TILDE = "~"
FLAG_PREFIX = "-"
FLAG_VALUE_SEP = "="

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
    if any(all(ch in PUNCTUATION for ch in p) for p in parts):
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

    if prog == "git":
        return git_allowed(args), cwd
    if prog in READ_ONLY_PROGRAMS:
        return not any(flag_forbidden(prog, a) for a in args), cwd
    return runner_allowed([prog] + args), cwd


def command_allowed(command, cwd, root):
    if any(bad in command for bad in UNANALYSABLE):
        return False
    stripped = HARMLESS_REDIRECT_RE.sub("", command)
    if shell_active_outside_quotes(stripped):
        return False

    lexer = shlex.shlex(stripped, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
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
        allowed, cwd = subcommand_allowed(parts, cwd, root)
        if not allowed:
            return False
    return True


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return
    if payload.get("tool_name") != MATCHED_TOOL:
        return

    root = project_root()
    cwd = payload.get("cwd")
    # Without a known starting directory inside the root, a relative path in the
    # command could resolve anywhere.
    if not root or not isinstance(cwd, str) or not inside(cwd, root):
        return

    command = (payload.get("tool_input") or {}).get("command")
    if not isinstance(command, str) or not command.strip():
        return

    try:
        allowed = command_allowed(command, os.path.realpath(cwd), root)
    except Exception:  # any analysis failure is a refusal, never an approval
        allowed = False
    if allowed:
        json.dump({"hookSpecificOutput": {
            "hookEventName": HOOK_EVENT,
            "permissionDecision": DECISION_ALLOW,
            "permissionDecisionReason": DECISION_REASON,
        }}, sys.stdout)


if __name__ == "__main__":
    main()
