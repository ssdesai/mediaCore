#!/usr/bin/env python3
"""PreToolUse hook: approve read-only and test Bash commands confined to this repo, send
back a command it cannot read with the rewrite as the reason, and print nothing for a
command it has read and cannot vouch for, so the human judges that one.

Claude Code runs this before the Bash permission check. The analysis answers one of three
verdicts (DESIGN-2026-09-18-hook-rewrite-or-ask.md §1), because "I could not read this"
and "I read it and it writes" are different answers and used to collapse into the same
silence:

  ALLOW    the whole command is provably confined to the project root and built from a
           fixed allowlist of read/test programs and the harness's own read-only entry
           points.
  REWRITE  the analysis could not read the command and there is a rewrite that always
           works — a heredoc into an interpreter, code handed to one as a string, a pipe
           into one, a program or a path decided at run time, a one-line compound, a line
           that does not tokenize (whose reason names the quote, since closing it is the
           fix), a `$NAME` the shell expands, a `~`, a brace group the expansion refuses,
           a `..` path component, a bare or relative `cd`, a line break outside a quote
           or a heredoc, a sequence mixing approved reads with a command only the
           human can judge, or a file authored through the shell (echo/printf redirected
           to a path, cat/tee fed literally, `sed -i`), whose rewrite is the Write or Edit
           tool. Denied, with that rewrite as the reason: the answer goes in front of
           the model instead of spending an approval from the human. After
           OPAQUE_REWRITE_ATTEMPTS of them in one session the hook stops denying and
           returns "ask" instead, so the human sees only what the model could not fix;
           under a headless runner (AGENTTOOLING_HEADLESS) it prints nothing there, since
           nobody can answer.
  ASK      the analysis read the command and cannot vouch for what it does: a write
           (a captured output, a copy, a move — not a file authored in the command), a
           program outside the allowlist, a path outside the root, an environment prefix,
           a whole-argument `$(…)`. It prints NOTHING, so the normal permission flow runs
           and the human approves a command this hook has read. No "ask" decision is
           emitted for this class — that would override the permissions.allow rules a
           human wrote.

Three shapes are denied outright before any of that, each read perfectly well and each
always a mistake with a mechanical answer: a `cd` or `pushd` sharing the command with
anything else; a git command that moves a ref, rewrites history or throws work away
(LIFECYCLE.md → "The three rules", rule 2); and an assignment at command position whose
own `$NAME` is used later on the same line, whose reason says to inline the literal.

Its reason for existing is `permissions.blockReadsOutsideWorkingDirectories`: that
fence stops any command whose paths resolve at run time, which is every
`cd X && cmd` chain, even for `ls` inside the repo. CONVENTIONS.md § Shell commands
tells agents not to write that shape; this hook answers the ones that still do.

Every approval rule below is a refusal, and the default is to refuse: a token the
analysis does not understand makes the whole command fall through to the normal prompt.
The threat model is an agent that has read access to the repo and is trying to turn an
auto-approved read into a read outside it, a write, or an execution — see
README.md § What the audit found and closed for the cases that were found and closed.

The git deny's own constants are not here: they are `policy.py` beside this file, the
one table `wire-settings.py` renders `permissions.deny`'s prefix rules from, so the two
halves of that policy cannot drift apart again (README.md § Editing the policy).
"""

import glob
import hashlib
import json
import os
import re
import shlex
import sys

# The policy table, imported as a sibling: this script is a hook command Claude Code runs
# from wherever the session sits, so the directory has to come from the file's own path.
# Bytecode writing is off because that path is inside the repo the hook is guarding, and
# a hook has no business leaving a __pycache__ in it.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import policy                                                        # noqa: E402

# Hook protocol
HOOK_EVENT = "PreToolUse"
MATCHED_TOOL = "Bash"
DECISION_ALLOW = "allow"
DECISION_REASON = "allow-repo-commands: read/test command confined to the project root"
DECISION_DENY = "deny"
DECISION_ASK = "ask"
# Payload fields that identify the caller. A subagent's payload carries the PARENT's
# session_id and its own agent_id, which is present only inside a subagent call (Claude
# Code hooks reference), so the pair is what a per-session counter is keyed on.
SESSION_FIELD = "session_id"
AGENT_FIELD = "agent_id"
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
    "feature-start.sh is the way in — it makes the branch and the worktree, and you may "
    "run it yourself from the primary checkout (`./agentTooling/feature-start.sh <slug> "
    "--method … [--pin]`, `--pin` when this session will coordinate the feature); its "
    "next run prunes away the ones whose work has merged. Start the feature BEFORE editing "
    "anything, then edit inside .worktrees/<slug>, never in the primary. feature-close.sh "
    "is the way out — run from the feature's worktree, on its branch, after a clean review "
    "and BEFORE the merge; merging the PR is the last step and nothing runs after it. "
    "Commit on the branch you are on and say what you need instead.")
OPAQUE_DENY_REASON = (
    "allow-repo-commands: this command hides code from anyone reading the command line — "
    "a heredoc into an interpreter, code passed as a string, a program or a path decided "
    "at run time, or a one-line compound — so nothing here can check what it does "
    "(CONVENTIONS.md § Shell commands). Rewrite it: write the script to the scratchpad "
    "with the Write tool and run it by name, or use the Read/Grep tool instead of a "
    "one-liner, or inline the literal you already have.")
# The seventh opaque shape, and the one where "write a script instead" is not the fix:
# a line no reader here can even split into words. Its reason names the quote.
UNREADABLE_DENY_REASON = (
    "allow-repo-commands: this command does not tokenize — a quote is left open, or a "
    "word no shell reader here can split — so nothing can say which words it runs, let "
    "alone what they do (CONVENTIONS.md § Shell commands). Close the quote and send it "
    "again; if the text is meant to be data rather than a command, write it to a file "
    "with the Write tool instead of quoting it onto a command line.")

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
    "du": frozenset(["--dereference", "--dereference-args"]),
    "file": frozenset(["--compile"]),
    "find": frozenset(["-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint",
                       "-fprintf", "-fls", "-L", "-follow"]),
    # --ext-diff and --textconv run whatever the repo's own config names for them
    "git": frozenset(["--output", "--ext-diff", "--textconv"]),
    "grep": frozenset(["--dereference-recursive"]),
    # --hostname-bin and --search-zip both run an external program (a hostname binary,
    # a decompressor off PATH)
    "rg": frozenset(["--pre", "--pre-glob", "--follow", "--hostname-bin",
                     "--search-zip"]),
    "sort": frozenset(["--output", "--temporary-directory", "--compress-program"]),
}
# Letters that are refused anywhere in a single-dash token, which also catches the
# combined (-ni) and attached-value (-i.bak, -o/tmp/x) spellings. `ls -L` and `du -L`
# walk THROUGH a symlink, so `ls -RL .` lists and `du -L .` sizes every file under
# whatever an in-tree link points at.
FORBIDDEN_SHORT_LETTERS = {
    "du": "LHD",
    "file": "C",
    "grep": "RS",
    "ls": "L",
    "rg": "Lz",
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
# Which `worktree` subcommands read is the table's answer, not a second opinion: the
# approval side and the deny side must agree about `list`, or a command is denied and
# approved at once.
GIT_WORKTREE_READ_ONLY = policy.worktree_read_only()
# `git branch` mutates whenever it is given a positional, so only these flags pass
GIT_BRANCH_ALLOWED_FLAGS = frozenset([
    "-a", "--all", "-r", "--remotes", "-v", "-vv", "--verbose", "--list",
    "--show-current", "--merged", "--no-merged", "--color", "--no-color",
])
GIT_BRANCH_ALLOWED_FLAG_PREFIXES = ("--format=", "--sort=")
# Global options between `git` and the subcommand that the APPROVAL side reads past to
# reach it. Before this, only the deny side skipped them, so `-C` read as the subcommand,
# matched no read-only name, and `git -C <a path in the root> status` — the commonest
# read a coordinator makes across its own worktrees — prompted every time
# (../self/DESIGN-2026-09-18-minutes-slug-and-quoting.md §5b).
#
# A deliberate SUBSET of the deny side's GIT_GLOBAL_VALUE_FLAGS, and the asymmetry is the
# point: finding a mutating subcommand behind an option is never a risk, approving a
# read-only one is. Each of the four left out fails the test "names a location and
# nothing else, so confining its value to the project root is the whole of what it can
# do":
#   -c, --config-env  set arbitrary config, so `git -c core.pager='sh -c id' log` runs
#                     `sh` — a value this analysis cannot confine at all;
#   --exec-path       moves where git looks for its own binaries;
#   --namespace       names a ref namespace rather than a path, so nothing here needs it
#                     and the safe default applies — unlisted means prompt.
GIT_GLOBAL_LOCATION_OPTIONS = frozenset(["-C", "--git-dir", "--work-tree"])

# ── The git deny ──────────────────────────────────────────────────────────────
# Every git shape that moves a ref, rewrites history or throws work away. This is the
# enforcement of LIFECYCLE.md rule 2, and every constant it reads is `policy.py`'s —
# the same table `wire-settings.py` renders `permissions.deny`'s prefix rules from, so
# the visible half of the policy cannot say something different from this half. Add a
# subcommand there and both ends move; `self/tests/policy-table.sh` asserts they did.
GIT_PROGRAM = policy.GIT_PROGRAM
# Global options between `git` and the subcommand. These take their value as the NEXT
# token, so `git -C /repo worktree add` would otherwise read `/repo` as the subcommand.
GIT_GLOBAL_VALUE_FLAGS = frozenset([
    "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env",
])
# Denied whatever their arguments, read-only spellings included: `git stash list` is one
# keystroke from `git stash`, and the prompt is the right place to tell them apart.
GIT_ALWAYS_MUTATING = policy.GIT_ALWAYS_MUTATING
GIT_PUSH = policy.GIT_PUSH
GIT_PUSH_FORCE_FLAGS = policy.GIT_PUSH_FORCE_FLAGS
GIT_PUSH_FORCE_LEASE_FLAG = policy.GIT_PUSH_FORCE_LEASE_FLAG   # also `=<ref>`
GIT_RESET = policy.GIT_RESET
GIT_RESET_MUTATING_FLAG = policy.GIT_RESET_MUTATING_FLAG
GIT_WORKTREE = policy.GIT_WORKTREE
GIT_WORKTREE_SAFE = GIT_WORKTREE_READ_ONLY            # `list` only, as the approval has it
GIT_CHECKOUT = policy.GIT_CHECKOUT
GIT_CHECKOUT_BRANCH_FLAGS = policy.GIT_CHECKOUT_BRANCH_FLAGS
GIT_SWITCH = policy.GIT_SWITCH
GIT_SWITCH_BRANCH_FLAGS = policy.GIT_SWITCH_BRANCH_FLAGS
GIT_BRANCH = policy.GIT_BRANCH
GIT_BRANCH_MUTATING_FLAGS = policy.GIT_BRANCH_MUTATING_FLAGS
# After one of these, a positional to `git branch` is a pattern to filter the listing by
# rather than a name to create (`git branch --list 'feat*'`).
GIT_BRANCH_LIST_FLAGS = policy.GIT_BRANCH_LIST_FLAGS
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
# There is deliberately NO prefix-rule twin for this one, unlike the git deny: a
# `permissions.deny` entry is a command PREFIX, and this is a relation between two tokens
# anywhere on the line, which no prefix can express. So nothing of it is in policy.py —
# hook-only, by design.
#
# `NAME=` at the start of a word, the shell's own assignment shape.
ASSIGNMENT_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=")
# Builtins that take assignments as their arguments, so `export X=/p` is still an
# assignment at command position rather than a command being given a value.
ASSIGNMENT_BUILTINS = frozenset(["export"])
# `$NAME` and `${NAME}`, and the special and positional parameters — `$?`, `$$`, `$!`,
# `$#`, `$*`, `$@`, `$-`, `$0`…`$9`, `${10}` — which the shell decides at run time just
# the same. Not `$(…)`, which starts with `(` and matches nothing here.
VAR_USE_RE = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*|[0-9]+|[?$!#*@-])\}?")

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
# Forms of an allowlisted runner that are not a run. "Repo code runs" (README.md →
# Accepted limits) covers a suite executing what the repo contains; it does not cover a
# linter rewriting that code or a type checker installing packages, which is a write
# this hook never approves.
RUNNER_FORBIDDEN_FLAGS = {
    "ruff": frozenset(["--fix", "--fix-only", "--unsafe-fixes"]),
    "mypy": frozenset(["--install-types"]),
}
RUNNER_RUFF = "ruff"
RUNNER_RUFF_FORMAT = "format"
# `ruff format` rewrites every file it is given unless it is only reporting
RUNNER_RUFF_FORMAT_REPORT_FLAGS = frozenset(["--check", "--diff"])

# ── The harness's own entry points ────────────────────────────────────────────
# Matched by BASENAME, and only when the script path resolves inside the root, so one
# rule covers both spellings of the same script: `plans/gate.sh`,
# `agentTooling/check-plans.sh` and `agentTooling/analysis/report.py` in a consuming
# repo, `self/gate.sh`, `./check-plans.sh` and `analysis/report.py` in agentTooling's own
# checkout. A basename alone is never enough — `python3 /tmp/report.py` names the same
# file name and a different program. Each of these reads, or re-derives what it prints;
# anything that freezes a cost record, writes a manifest or moves a ref is absent on
# purpose and keeps prompting (feature-start.sh, feature-close.sh, stamp-timing.sh,
# capture_planning.py --recapture/--all, manifest.py init and set-*).
ENTRY_GATE = "gate.sh"                      # gate.sh [<level label>]
ENTRY_GATE_MAX_ARGS = 1
ENTRY_CHECK_PLANS = "check-plans.sh"        # check-plans.sh [--self] <slug>
ENTRY_REPORT = "report.py"                  # report.py [--self] <slug> | --all
ENTRY_CAPTURE_PLANNING = "capture_planning.py"
ENTRY_MANIFEST = "manifest.py"
# capture_planning.py only in a listing form: --recapture, --all and --carry-lost (which
# implies --recapture) rewrite a frozen planning.json and cost real money to redo, and
# --force is what makes a capture overwrite one whose evidence has gone. A reader should
# not have to reason about argparse's ordering to know none of them can reach a write
# from here.
CAPTURE_LIST_PREFIX = "--list-"
CAPTURE_WRITING_FLAGS = frozenset(["--recapture", "--all", "--carry-lost", "--force"])
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

# ── The opaque shape ──────────────────────────────────────────────────────────
# Everything above answers "is this command confined and read-only?". This answers the
# question in front of it: can the command be READ at all? A heredoc, code handed to an
# interpreter as a string, a program or a path that only exists once the shell runs —
# none of these can be judged by anyone reading the command line, so they used to fall
# through to the human's prompt, which cost an approval and taught the model nothing.
# They are denied instead, with the rewrite as the reason (design 2026-09-17, which
# supersedes DESIGN-2026-09-16-lifecycle-restructure.md §3.7's "stays prose").
#
# A deny must not demand a rewrite forever, though: after this many in one session the
# hook returns `ask`, so the human sees only what the model could not fix.
OPAQUE_REWRITE_ATTEMPTS = 2
OPAQUE_ASK_REASON = (
    "allow-repo-commands: this command is still unreadable after %d rewrite attempts in "
    "this session, so it is the human's call now rather than another deny. Nothing here "
    "can check what it does; CONVENTIONS.md § Shell commands says what the rewrite would "
    "have been." % OPAQUE_REWRITE_ATTEMPTS)
# Programs that read a heredoc as a literal string rather than as code. `cat` is the one:
# `git commit -m "$(cat <<'EOF' … EOF)"` is how Claude Code itself writes a commit
# message, and a heredoc feeding cat hides nothing — the body IS the value.
HEREDOC_LITERAL_PROGRAMS = frozenset(["cat"])
# Interpreters, each with the single-dash letter that makes it take its code as a string
# instead of as a file. The letter is matched anywhere in a single-dash token, so `-lc`
# and `-ne` are caught with `-c` and `-e`.
INTERPRETER_CODE_LETTER = {
    "python": "c", "python2": "c", "python3": "c",
    "bash": "c", "sh": "c", "zsh": "c", "ksh": "c", "dash": "c",
    "node": "e", "perl": "e", "ruby": "e",
}
EVAL_PROGRAM = "eval"
# Programs whose ARGUMENTS hold a command of their own, so a command position exists
# inside their argument list
COMMAND_CARRIER_PROGRAMS = frozenset(["xargs"])
FIND_EXEC_FLAGS = frozenset(["-exec", "-execdir", "-ok", "-okdir"])
# Shell keywords that open a compound. One of these on a single line is control flow the
# analysis cannot follow, and the fix is a script.
COMPOUND_KEYWORDS = frozenset(["for", "while", "until", "if", "case", "select"])
SUBSTITUTION_OPEN = "$("
BACKTICK = "`"
PIPE_CHAR = "|"
OR_OPERATOR = "||"
# Segment breaks for the opaque scanner. Unlike shlex this never raises and never drops a
# heredoc body or a `#`: the opaque analysis has to read exactly the text the approval
# analysis could not.
LINE_BREAK_CHARS = "\n\r"
SEGMENT_BREAKS = ";|&" + LINE_BREAK_CHARS

# ── The three outcomes ────────────────────────────────────────────────────────
# The approval analysis used to answer a bool, so "I could not read this" and "I read it
# and it writes" collapsed into the same silence: the human paid an approval for both and
# the model learned from neither. There are three answers, not two
# (../self/DESIGN-2026-09-18-hook-rewrite-or-ask.md §1):
#
#   ALLOW    every subcommand read-only and confined. Unchanged, and decided by
#            `command_allowed` exactly as before — this layer is only ever reached once
#            that has DECLINED, so it can turn a prompt into a deny and never the other
#            way round.
#   REWRITE  the analysis could not read the command, and a rewrite exists. Denied, with
#            the rewrite as the reason, counting toward the same escalation the seven
#            opaque shapes always did. They are members of this class now.
#   ASK      the analysis READ the command and cannot vouch for what it does: a program
#            outside the allowlist, a write (other than a file authored through the
#            shell, which is a REWRITE), a path outside the root, an environment
#            prefix, a whole-argument `$(…)`. It prints nothing, exactly as before, so
#            the settings' own allow/deny rules and then the human decide. No `ask`
#            decision is emitted for this class: an explicit `ask` would override the
#            `permissions.allow` rules a human wrote, and the prompt already shows a
#            command this hook has read (design §6).
#
# Precedence on a line: any REWRITE member makes the line REWRITE — the human is never
# handed a line no reader here could split — else any ASK member makes it ASK, else ALLOW.
VERDICT_ALLOW = "ALLOW"
VERDICT_REWRITE = "REWRITE"
VERDICT_ASK = "ASK"
# How much of a member's own text a reason quotes. A reason has to name the member as
# WRITTEN — a model with three commands on one line cannot otherwise tell which one is
# being refused — and a command line can be arbitrarily long, so it is cut.
MEMBER_TEXT_MAX_CHARS = 80
MEMBER_TEXT_CUT = "..."
MEMBER_QUOTE = "`%s`"
REASON_PREFIX = "allow-repo-commands: "
# One line per shape when a line carries several, so two problems are two corrections.
REASON_LINE_SEPARATOR = "\n"
# Only `\n` ends a line for the rewrite: a `\` continuation leaves one behind, so it is
# the same shape. A CR and a NUL are text the analysis cannot see through with no
# rewrite to name, so they stay ASK (design §1, "Not rewritable").
LINE_BREAK_NEWLINE = "\n"
# The separators a SEQUENCE is made of. A pipeline is one command judged by its members
# and never split, and a `&` is a job, so neither is eligible for the one-write-per-call
# rewrite below (design §2).
SEQUENCE_SEPARATORS = frozenset(["&&", "||", ";"])
# A path component that is decided by where the command runs rather than by the text.
PARENT_COMPONENT = ".."
# An empty brace is not a group bash expands — `find . -exec rm {} \;` hands it to find
# verbatim — so there is nothing to expand and nothing to rewrite.
BRACE_EMPTY_GROUP = "{}"

VAR_USE_REWRITE_REASON = (
    "%s expands a variable the shell decides at run time, and a path that only exists "
    "once the command runs is exactly what the reads fence cannot check. Inline the "
    "literal you already have.")
TILDE_REWRITE_REASON = (
    "%s starts a word with `~`, which is a path only after the shell has expanded it. "
    "Write the absolute path.")
BRACE_REWRITE_REASON = (
    "%s carries a brace this analysis will not expand — a quote or a backslash mixed "
    "into the word, a nested group, or more words than the cap. Expand it yourself, or "
    "write a script to the scratchpad with the Write tool and run it by name.")
PARENT_PATH_REWRITE_REASON = (
    "%s names a path through a `..` component, so where it reads depends on where it "
    "runs. Write the path from the project root.")
RELATIVE_CHDIR_REWRITE_REASON = (
    "%s is a bare or relative directory change, and where it lands is decided at run "
    "time. Run `cd <absolute path>` as its own Bash call.")
LINE_BREAK_REWRITE_REASON = (
    "this command carries a line break (or a `\\` continuation) outside a heredoc body, "
    "so it is several commands in one call and nothing here can say which of them the "
    "approval would be for. Send one call per line.")
MIXED_SEQUENCE_REWRITE_REASON = (
    "this line mixes commands this hook approves with commands only you can judge, so "
    "the human ends up approving the whole line to get the one that matters. One write "
    "per Bash call, nothing else on the line: run on their own — approved: %s; run "
    "alone: %s.")

# ── A file authored through the shell ─────────────────────────────────────────
# Content written in the command itself landing in a file (self/features/
# shell-write-rewrite). CONVENTIONS.md → "Writing files" says to author files with the
# Write and Edit tools, because a write made by a subprocess gets past the repo's Edit
# allow and deny rules; and there is a rewrite that always works, so by the membership
# test above it is a REWRITE and not an ASK. Three spellings, judged per member:
#   echo / printf              with its output redirected to a path;
#   cat / tee                  fed literally — a heredoc or herestring on the member, or
#                              for tee a pipe from echo/printf or a heredoc-fed cat — with
#                              output to a path (a redirect, or a file operand of tee);
#   sed                        editing in place.
# Where the file is does not matter: the Write tool reaches the scratchpad, the root and
# /tmp alike, and is checked against the rules the shell write bypasses. A command's
# OUTPUT captured to a file (`pytest > out.log`, `cat a > b`, `cmd | tee log`) is not
# this: no Edit or Write reproduces output nobody has seen, so it stays ASK.
AUTHORING_ECHO_PROGRAMS = frozenset(["echo", "printf"])
AUTHORING_LITERAL_PROGRAMS = frozenset(["cat", "tee"])
AUTHORING_TEE_PROGRAM = "tee"
AUTHORING_HEREDOC_FED_PROGRAM = "cat"     # the one program whose heredoc feeds a tee
AUTHORING_SED_PROGRAM = "sed"
SED_IN_PLACE_LETTER = "i"                 # `-i`, `-i.bak`, `-Ei`, `-ni`, `-i ''`
SED_IN_PLACE_LONG = "--in-place"          # also `--in-place=<suffix>`
# sed's short flags that take a value: past one of them the rest of the token is that
# value (`-f<script>`), so a later `i` is a letter of a filename, not the flag.
SED_VALUE_LETTERS = "efl"
# Redirect operators. `N>`, `>`, `>>`, `>|` and `>&` write through a descriptor, `&>` and
# `&>>` write both streams; `<<`, `<<-` and `<<<` feed the member text written in the
# command. `>(…)`/`<(…)` are process substitutions and not redirects at all.
REDIRECT_CHARS_OUT, REDIRECT_CHARS_IN = ">", "<"
REDIRECT_OUTPUT_OPS = frozenset([">", ">>", ">|", ">&", "&>", "&>>"])
REDIRECT_OUT_SUFFIXES = (">", "|", "&")   # what may follow the first `>` of an operator
REDIRECT_IN_OPS = ("<<<", "<<-", "<<", "<>", "<&", "<")   # longest first
REDIRECT_LITERAL_OPS = frozenset(["<<", "<<-", "<<<"])
REDIRECT_DUP_OP = ">&"                    # `>&2`, `2>&1`: a descriptor, unless a filename
REDIRECT_BOTH_STREAMS = "&"               # the `&` of `&>` / `&>>`
PROCESS_SUBSTITUTION_PREFIXES = (">(", "<(")
# `>&N` and `>&-` duplicate or close a descriptor; any other word after `>&` is a file
FD_DUP_TARGET_RE = re.compile(r"^(?:\d+|-)$")
# Redirect targets that name no file
NON_FILE_TARGETS = frozenset(["/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty"])
# Member separators for this reader. Unlike SEGMENT_BREAKS, an `&` or a `|` that is part
# of a redirect operator (`2>&1`, `&>`, `>|`) is read as the operator and not as a break.
AUTHORING_SEPARATOR_CHARS = ";|&"
PIPE_SEPARATORS = frozenset(["|", "|&"])
SHELL_AUTHORING_REWRITE_REASON = (
    "%s writes a file from text in the command itself, and a file written by a shell "
    "subprocess is one the repo's Edit allow and deny rules never see (CONVENTIONS.md § "
    "Writing files). Use the Write tool for a new file or a whole rewrite, and the Edit "
    "tool for a change to an existing file — an append is an Edit anchored on the "
    "file's last lines.")

# ── Escalation state ──────────────────────────────────────────────────────────
# One file per session (and per subagent) under an explicit directory beneath $TMPDIR —
# a bare temp path would be unconfigurable and untestable, the same reason the runners
# give mktemp -d a template (self/PROJECT_FACTS.md). The name is a digest of the key, so
# nothing from the payload reaches the filesystem. A missing, empty, corrupt or
# unreadable file counts as zero: this state may never turn into a crash or a deny.
TMPDIR_ENV = "TMPDIR"
TMPDIR_FALLBACK = "/tmp"
STATE_DIR_NAME = "agenttooling-hook-state"
STATE_FILE_SUFFIX = ".count"
STATE_DIR_MODE = 0o700
STATE_KEY_SEPARATOR = "\0"
# Set by plan-runner-lib.sh into the `claude -p` it launches (RUNNER.md). With it set
# there is nobody to answer an `ask`, so the escalation prints nothing and the runner's
# own non-interactive policy decides.
HEADLESS_ENV = "AGENTTOOLING_HEADLESS"
# The per-pass directory the same launch site creates. A script written there and run by
# name is approved like the harness's own entry points — it is the place a denied
# heredoc is meant to become a file.
SCRATCH_ENV = "AGENTTOOLING_SCRATCH"
SCRATCH_BASH = "bash"
# At least one argument, the first being the script. Anything after it is an argument to
# that script, and each is checked like any other path — against the project root, or
# against the scratch directory the script itself came from.
SCRATCH_SCRIPT_MIN_ARGS = 1


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
        # `--list`/`-l` turns every positional into a glob to filter the listing by, so
        # `git branch --list 'feat*'` reads and moves nothing. The mutating flags are
        # judged first, which is why `git branch --list --delete old` is still denied.
        if any(a in GIT_BRANCH_LIST_FLAGS for a in rest):
            return False
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


# ── Reading what the approval analysis could not ──────────────────────────────


def opaque_segments(text):
    """`[(separator, [raw word, ...])]` for the command's top-level segments.

    A segment breaks at an unquoted `;`, `|`, `&` or line break that is outside every
    quote, substitution and subshell; a word breaks at unquoted whitespace. `separator`
    is the punctuation run that preceded the segment (`""` for the first), which is what
    tells a pipe from an `||`. Quotes, backslashes and `$(…)` are kept inside the words,
    because whether a `$` was quoted is exactly the question asked of them.

    Unlike shlex this never raises and never stops at a heredoc or a `#`. It is the one
    reader in this file whose job is the text the others refused to judge.
    """
    segments, words, word = [], [], []
    sep, pending_sep = "", ""
    in_single = in_double = escaped = in_backtick = False
    depth = 0

    for ch in text:
        if escaped:
            word.append(ch)
            escaped = False
            continue
        if ch == ESCAPE and not in_single:
            word.append(ch)
            escaped = True
            continue
        if ch == QUOTE_SINGLE and not in_double:
            in_single = not in_single
            word.append(ch)
            continue
        if ch == QUOTE_DOUBLE and not in_single:
            in_double = not in_double
            word.append(ch)
            continue
        if in_single or in_double:
            word.append(ch)
            continue
        if ch == BACKTICK:
            in_backtick = not in_backtick
            word.append(ch)
            continue
        if in_backtick:
            word.append(ch)
            continue
        if ch == SUBSHELL_OPEN:
            depth += 1
            word.append(ch)
            continue
        if ch == SUBSHELL_CLOSE and depth:
            depth -= 1
            word.append(ch)
            continue
        if depth:
            word.append(ch)
            continue
        if ch in SEGMENT_BREAKS:
            if word:
                words.append("".join(word))
                del word[:]
            if words:
                segments.append((sep, list(words)))
                del words[:]
                sep = ""
            pending_sep += ch
            continue
        if ch.isspace():
            if word:
                words.append("".join(word))
                del word[:]
            continue
        if pending_sep:
            sep, pending_sep = pending_sep, ""
        word.append(ch)

    if word:
        words.append("".join(word))
    if words:
        segments.append((sep, list(words)))
    return segments


def word_body(word):
    """A word with a leading `NAME=` and one layer of surrounding quotes removed — what
    the shell will actually use as a path or a program name."""
    match = ASSIGNMENT_RE.match(word)
    if match:
        word = word[match.end():]
    for quote in (QUOTE_SINGLE, QUOTE_DOUBLE):
        if len(word) > 1 and word.startswith(quote) and word.endswith(quote):
            return word[1:-1]
    return word


def path_body(word):
    """A word read as a PATH: a leading `NAME=` and one layer of surrounding DOUBLE
    quotes removed, and its single quotes left exactly where they are.

    `word_body` strips either quote, which is right for a program name — `'/bin/cat'` is
    `cat` whichever quote it wears — and wrong here. The question asked of a path is
    whether it holds a substitution the shell will act on, and a single quote is the one
    thing that decides it. Stripping them first made `sed -n '/```json/,/```/p' <file>`
    read as a path built from a command substitution: the line was DENIED as unreadable
    when its file sat outside the root, while the same line with a file inside it was
    approved by the read-only rule one branch earlier. A literal in single quotes is a
    literal, and the human should have been asked
    (../self/DESIGN-2026-09-18-minutes-slug-and-quoting.md §5a).

    Double quotes still come off, because `$` and a backtick stay active inside them:
    `cat "$(pwd)/README.md"` really is a path decided at run time, and `AT="$(cd … &&
    pwd)"` is the whole-argument substitution the exemption is for. `unquoted_index`,
    which reads what is left, carries its own single-quote state, so a word quoted only
    in part (`cat '$HOME'/x`) is judged character by character rather than all at once.
    """
    match = ASSIGNMENT_RE.match(word)
    if match:
        word = word[match.end():]
    if len(word) > 1 and word.startswith(QUOTE_DOUBLE) and word.endswith(QUOTE_DOUBLE):
        return word[1:-1]
    return word


def command_name(word):
    """The program a word names: quotes and a path stripped, so `/bin/cat` is `cat`."""
    return os.path.basename(word_body(word).strip(QUOTE_SINGLE + QUOTE_DOUBLE))


def unquoted_index(word, needle):
    """Where `needle` first appears in `word` outside single quotes, or -1. `grep -n '<<'
    f` carries the characters and not the operator.

    Both quotes are tracked, and only one of them hides anything: a `$`, a backtick and a
    `<<` stay ACTIVE inside double quotes, so the needle is reported there — what the
    double-quote state is for is knowing that a `'` inside `"…"` is an ordinary
    character. Before that, `cat "'"$(pwd)/x` read as a word whose single quote opened a
    span that never closed, so the substitution after it looked quoted and the line fell
    through to a prompt instead of being denied as a path decided at run time (the
    coordinator's audit of minutes-slug-and-quoting S5a, 2026-09-18). Every shape below
    is read through this walk, which is why it is fixed first.
    """
    in_single = in_double = escaped = False
    for index, ch in enumerate(word):
        if escaped:
            escaped = False
            continue
        if ch == ESCAPE and not in_single:
            escaped = True
            continue
        if ch == QUOTE_SINGLE and not in_double:
            in_single = not in_single
            continue
        if ch == QUOTE_DOUBLE and not in_single:
            in_double = not in_double
            continue
        if not in_single and word.startswith(needle, index):
            return index
    return -1


def program_words(words):
    """The segment's words with any environment prefix dropped, so the program is first.
    `X=1 python3 -c …` is python3 being run, whatever else the prefix says."""
    index = 0
    while index < len(words) and ASSIGNMENT_RE.match(words[index]):
        index += 1
    return words[index:]


def heredoc_programs(segments):
    """The program each `<<` on the line feeds, or `[]` when the line carries none.

    A heredoc's body lines read as commands to every scanner in this file, so a line that
    has one is judged on the heredoc alone — the same guard the other three denies keep,
    for the same reason: a deny must not fire on a guess about a body.

    The operator's owner is the segment's program, unless the operator sits inside a
    `$(…)` in that word — `git commit -m "$(cat <<'EOF' … EOF)"`, Claude Code's own
    commit-message shape — where the owner is the substitution's first word, `cat`.
    """
    programs = []
    for _sep, words in segments:
        head = program_words(words)
        for word in words:
            at = unquoted_index(word, HEREDOC_OPERATOR)
            if at < 0:
                continue
            opened = word[:at].rfind(SUBSTITUTION_OPEN)
            if opened < 0:
                programs.append(command_name(head[0]) if head else "")
                continue
            inner = word[opened + len(SUBSTITUTION_OPEN):at].split()
            programs.append(command_name(inner[0]) if inner else "")
    return programs


def segments_before_line_break(segments):
    """The segments on the command's FIRST line — up to, not including, the first segment
    a line break introduced. A heredoc's body always starts after that break, so this is
    the part of a heredoc-carrying command that is still a command line rather than text.
    """
    first = []
    for sep, words in segments:
        if any(ch in sep for ch in LINE_BREAK_CHARS):
            break
        first.append((sep, words))
    return first


def interpreter_takes_code(name, rest):
    """True when `name` is an interpreter and one of `rest` is the single-dash flag that
    hands it its code as a string.

    The scan stops at the first word that is not a flag, because that word is the script
    and every flag after it belongs to the script rather than to the interpreter:
    `python3 tool.py -c config.yaml` is a perfectly readable command, and reading its
    `-c` as the interpreter's would deny it and count it toward the `ask`. Every shape
    this is meant to catch puts the code flag before any script, by construction — the
    flag is what replaces the script."""
    letter = INTERPRETER_CODE_LETTER.get(name)
    if letter is None:
        return False
    for word in rest:
        if not word.startswith(FLAG_PREFIX):
            return False
        if not word.startswith(FLAG_PREFIX * 2) and letter in word[1:]:
            return True
    return False


def code_as_string(words):
    """True when some command position in this segment hands code to an interpreter as a
    string, or is `eval`. A command position is the segment's program; the argument list
    of a command carrier (`xargs`); and whatever follows `find`'s exec flags. An
    interpreter named in a flag's VALUE (`rg --pre 'sh -c id'`) is one shlex token and
    is not a command position, which is why this reads names rather than substrings."""
    head = program_words(words)
    if not head:
        return False
    positions = [0]
    if command_name(head[0]) in COMMAND_CARRIER_PROGRAMS:
        positions.extend(range(1, len(head)))
    for index, word in enumerate(head):
        if word in FIND_EXEC_FLAGS:
            positions.extend(range(index + 1, len(head)))
    for index in positions:
        name = command_name(head[index])
        if name == EVAL_PROGRAM:
            return True
        if interpreter_takes_code(name, head[index + 1:]):
            return True
    return False


def piped_into_interpreter(sep, words):
    """True when this segment is the right-hand side of a pipe and is an interpreter with
    no script to run — `… | sh`, `… | python3`. `||` is not a pipe, and a lone `-` is
    not a script."""
    if PIPE_CHAR not in sep or OR_OPERATOR in sep:
        return False
    head = program_words(words)
    if not head or command_name(head[0]) not in INTERPRETER_CODE_LETTER:
        return False
    return not any(not a.startswith(FLAG_PREFIX) for a in head[1:])


def program_decided_at_run_time(words):
    """True when the segment's program is a substitution or a variable: `$CMD …`,
    `$(which x) …`. Nothing here can say what will run."""
    head = program_words(words)
    return bool(head) and head[0].startswith((SUBSTITUTION_PREFIX, BACKTICK))


def wholly_substituted(body):
    """True when the word is ONE substitution and nothing else — `$(cd dir && pwd)`,
    `` `id` ``. Such a word decides a value, which is what a substitution is for; it is
    a substitution glued to the rest of a PATH that hides where the command will read."""
    if body.startswith(BACKTICK):
        return body.endswith(BACKTICK) and BACKTICK not in body[1:-1]
    if not body.startswith(SUBSTITUTION_OPEN):
        return False
    depth = 0
    for index, ch in enumerate(body):
        if ch == SUBSHELL_OPEN:
            depth += 1
        elif ch == SUBSHELL_CLOSE:
            depth -= 1
            if depth == 0:
                return index == len(body) - 1
    return False


def substitution_in_path(words):
    """True when a word is a path (it carries a `/`) built partly from a substitution.
    `ls $(cd dir && pwd)/src` reads somewhere this analysis cannot name; `x=$(cd dir &&
    pwd)` and `echo $(pwd)` name a value and are left alone.

    Read through `path_body`, so a `$` or a backtick inside single quotes is a literal
    and not a substitution at all — see that function for the shape this got wrong."""
    for word in words:
        body = path_body(word)
        if os.sep not in body:
            continue
        if (unquoted_index(body, SUBSTITUTION_OPEN) < 0
                and unquoted_index(body, BACKTICK) < 0):
            continue
        if not wholly_substituted(body):
            return True
    return False


def one_line_compound(words):
    """True when the segment opens a shell compound. `for … do … done` on one line is
    control flow, and a script is the honest spelling of it."""
    head = program_words(words)
    return bool(head) and word_body(head[0]) in COMPOUND_KEYWORDS


def does_not_tokenize(command):
    """True when no reader here can split the line into words — an unterminated quote,
    or a token shlex refuses.

    This is the seventh opaque shape and the plainest of them: a command nothing can
    even lex is a command nothing can judge, and before this it fell through to the
    human's prompt like any other refusal, costing an approval and teaching nothing.
    The fix is not a script in the scratchpad, so it gets its own reason
    (UNREADABLE_DENY_REASON) naming the quote.

    The two guards the other denies keep hold here as well, and for the same reason: a
    heredoc's body and the text after a `#` are data, not a command line, so an
    apostrophe in either is nobody's business — `cat <<'EOF' … don't … EOF` writes a
    file and is not a command that will not parse. They are looked for in the RAW text,
    since a line that will not tokenize cannot be asked where its quotes are.
    """
    if HEREDOC_OPERATOR in command or COMMENT_CHAR in command:
        return False
    lexer = shlex.shlex(command, posix=True, punctuation_chars=CHAIN_PUNCTUATION)
    lexer.whitespace = CHAIN_WHITESPACE
    lexer.whitespace_split = True
    lexer.commenters = SHLEX_NO_COMMENTERS
    try:
        list(lexer)
    except ValueError:
        return True
    return False


def is_opaque(command):
    """True when the command hides code from anyone reading the command line.

    Six shapes, checked against the raw text rather than against shlex's reading of it,
    because the whole category is text shlex could not read. Called only after the
    approval analysis has declined to approve: a command this hook already understands
    well enough to allow is by definition not opaque, and `ls src # list it` must keep
    its approval rather than collect a deny for its comment.
    """
    segments = opaque_segments(command)
    if not segments:
        return False
    heredocs = heredoc_programs(segments)
    if heredocs:
        if any(p not in HEREDOC_LITERAL_PROGRAMS for p in heredocs):
            return True
        # Every heredoc here feeds `cat`, so its BODY is a literal string and stays
        # unjudged — that is the `git commit -m "$(cat <<'EOF' … EOF)"` exemption. The
        # FIRST line is not a body, though, and `cat <<'EOF' | python3` hides an
        # interpreter on it: without this the rewrite a model reaches for straight after
        # `python3 - <<EOF` is denied would read as a plain `cat` and reset the counter.
        # Only the two shapes that can hide code on that line are checked; a `$(…)` in a
        # path or a one-line compound there is still judged on the heredoc alone.
        return any(code_as_string(words) or piped_into_interpreter(sep, words)
                   for sep, words in segments_before_line_break(segments))
    for sep, words in segments:
        if (code_as_string(words)
                or piped_into_interpreter(sep, words)
                or program_decided_at_run_time(words)
                or substitution_in_path(words)
                or one_line_compound(words)):
            return True
    return False


def opaque_deny_reason(command):
    """The reason this command cannot be read, or None when the analysis can read it.

    The tri-state `main()` turns on: approve / refuse a readable command (print nothing,
    and reset the counter) / deny an unreadable one. The six named shapes answer first,
    since each has a rewrite worth naming; a line that does not tokenize answers last,
    with the quote.
    """
    if is_opaque(command):
        return OPAQUE_DENY_REASON
    if does_not_tokenize(command):
        return UNREADABLE_DENY_REASON
    return None


# ── The rewritable shapes ─────────────────────────────────────────────────────
# Everything below reads the RAW text, through `opaque_segments`, for the same reason the
# seven shapes above do: this is the text the approval analysis declined to read. Each
# function answers one row of the design's table, and each row has a rewrite that always
# works — which is the whole test for membership. A shape with no rewrite to name (a CR,
# a NUL, a `..` in a token that is not a path, an environment prefix, a command's output
# captured to a file) is an ASK: the hook prints nothing and the human judges a command
# it has read. A file whose CONTENT is written in the command does have one — the Write
# or Edit tool — and is judged ahead of all of these (`authoring_reason_lines`).
#
# The two guards the three shape denies keep hold here as well, and for the same reason —
# a deny must not fire on a guess. A heredoc's body lines and the text after a `#` are
# data, not a command line, so a line carrying either is judged on the shapes above
# alone: `cat <<'EOF' … cd x … EOF` writes a file and is not a relative `cd`, and
# `ls src # X=/p; cat $X` is a comment and is not a variable the shell will expand.


def member_text(words):
    """A member as written — its raw words, whitespace normalised — cut at
    MEMBER_TEXT_MAX_CHARS so one reason cannot flood the transcript it lands in."""
    text = " ".join(words)
    if len(text) > MEMBER_TEXT_MAX_CHARS:
        return text[:MEMBER_TEXT_MAX_CHARS] + MEMBER_TEXT_CUT
    return text


def expands_a_variable(words):
    """True when some word carries a `$NAME`/`${NAME}` the shell will expand. Read by
    `active_var_uses`, which is quote-aware: `echo '$X'` is a literal string."""
    return any(active_var_uses(word) for word in words)


def starts_with_tilde(words):
    """True when a word begins with an unquoted `~`, which becomes a home directory only
    once the shell expands it."""
    return any(word.startswith(TILDE) for word in words)


def brace_outside_quotes(word):
    """True when some `{` or `}` in `word` sits outside both quotes. Bash never expands
    a brace a quote encloses — single or double, either hides it — so this is the read
    `brace_expansion_refused` needs to tell a literal `"{name}"` or `"stash@{0}"` from a
    real group.

    Tracks the same single/double/escape state `active_var_uses` keeps. An escaped brace
    (`cat \\{src,/etc/passwd\\}`) is still UNQUOTED by this test: a backslash does not
    enclose a character in a quote, it only changes how bash reads it, so that brace
    still counts as a group this analysis was asked to expand and refused (round 1 of
    this feature's review, escalations/01-review-opus.md #2; NOTES.md ruling 13).
    """
    in_single = in_double = escaped = False
    for ch in word:
        if escaped:
            escaped = False
        elif ch == ESCAPE and not in_single:
            escaped = True
            continue
        elif ch == QUOTE_SINGLE and not in_double:
            in_single = not in_single
            continue
        elif ch == QUOTE_DOUBLE and not in_single:
            in_double = not in_double
            continue
        if ch in BRACE_CHARS and not (in_single or in_double):
            return True
    return False


def brace_expansion_refused(words):
    """True when a word carries an UNQUOTED brace this analysis will not expand: a quote
    or a backslash mixed into the unquoted group (which changes bash's own reading of
    it), a nested group (one substitution pass leaves the outer braces behind), or an
    expansion past MAX_BRACE_WORDS.

    A brace bash itself leaves alone is not one of them: `{a}`, `{a..c}` and find's `{}`
    expand to themselves, so there is nothing for the model to expand by hand and no
    rewrite to name. Those keep prompting, as they did before this rule existed.

    Neither is a brace a quote encloses: `jq -r ".[] | {name}" data.json` and `git show
    "stash@{0}"` are literals bash never expands, so `brace_outside_quotes` skips them —
    there is nothing to expand and nothing to rewrite, and they keep prompting too.
    """
    for word in words:
        if not any(ch in BRACE_CHARS for ch in word) or single_quoted_word(word):
            continue
        if not brace_outside_quotes(word):
            continue
        if any(ch in QUOTING_CHARS for ch in word):
            return True
        if BRACE_GROUP_RE.search(word) and any(
                ch in BRACE_CHARS for ch in BRACE_GROUP_RE.sub("", word)):
            return True
        if BRACE_EMPTY_GROUP not in word and expand_braces(word) is None:
            return True
    return False


def parent_path_component(words):
    """True when a word names a path through a `..` COMPONENT.

    The component is the test, not the two characters: `git diff main...HEAD` carries no
    `..` component and is the human's call, while `cat ../x`, `ls a/../b` and
    `--out=../x` are paths decided by where the command runs. A word with no separator in
    it is not a path here, and a wholly single-quoted word is a literal — the reading
    `path_body` already gives every other path in this file.
    """
    for word in words:
        if single_quoted_word(word):
            continue
        body = path_body(word)
        candidates = [body]
        if FLAG_VALUE_SEP in body:
            candidates.append(body.split(FLAG_VALUE_SEP, 1)[1])
        for candidate in candidates:
            if os.sep in candidate and PARENT_COMPONENT in candidate.split(os.sep):
                return True
    return False


def relative_chdir(words):
    """True when the member is a bare or relative `cd`/`pushd`. An absolute one is the
    shape the convention asks for and is judged by the approval analysis, which confines
    it to the root; a relative one names a directory nothing here can resolve."""
    head = program_words(words)
    if not head or command_name(head[0]) not in CHDIR_PROGRAMS:
        return False
    if len(head) < 2:
        return True
    return not path_body(head[1]).startswith(os.sep)


def carries_line_break(command):
    """True when the command is several lines and none of them is a heredoc's body, and
    the break is not just an argument's own text.

    A `\\n` inside a quoted argument is one argument, not a second command — `git commit
    -m "subject\\n\\nbody"` is one call, and the rewrite this shape names ("one call per
    line") cannot be carried out on it, so it must stay an ASK rather than become a
    REWRITE (round 1 of this feature's review, escalations/01-review-opus.md #1). The
    walk tracks the same single/double/escape state `active_var_uses` keeps: a `\\n`
    outside both quotes is a real line break, and an escaped `\\n` outside both quotes
    still counts, since that is the `\\` continuation (`ls src \\\n tests`).
    """
    if HEREDOC_OPERATOR in command:
        return False
    in_single = in_double = escaped = False
    for ch in command:
        if escaped:
            escaped = False
        elif ch == ESCAPE and not in_single:
            escaped = True
            continue
        elif ch == QUOTE_SINGLE and not in_double:
            in_single = not in_single
            continue
        elif ch == QUOTE_DOUBLE and not in_single:
            in_double = not in_double
            continue
        if ch == LINE_BREAK_NEWLINE and not (in_single or in_double):
            return True
    return False


def member_allowed(text, cwd, root):
    """Whether this one member would be approved on its own — the question the
    one-write-per-call rewrite is built from. The same oracle the whole line is judged
    by, asked about one command: a member that is approved here is a command the model
    can send on its own and have approved with no prompt at all.

    The payload's cwd is used for every member, which is exact here: a `cd` sharing a
    line with another command is denied before any of this runs, so no member of a
    sequence that reaches this point moves the directory the next one resolves against.
    """
    if not root or cwd is None:
        return False
    try:
        return command_allowed(text, cwd, root)
    except Exception:   # an analysis failure is never an approval
        return False


def mixed_sequence_reason(segments, cwd, root):
    """The rewrite for a sequence that mixes approved members with members only the human
    can judge (design §2), or None.

    A sequence whose members are ALL ASK is one ASK — one prompt, not two: the rule takes
    noise out of the prompt, it does not multiply prompts. A PIPELINE is one command,
    judged by its members and never split, so only `&&`, `||` and `;` are eligible.
    """
    if len(segments) < 2:
        return None
    if any(sep not in SEQUENCE_SEPARATORS for sep, _words in segments[1:]):
        return None
    approved, alone = [], []
    for _sep, words in segments:
        text = member_text(words)
        (approved if member_allowed(text, cwd, root) else alone).append(text)
    if not approved or not alone:
        return None
    return MIXED_SEQUENCE_REWRITE_REASON % (
        ", ".join(MEMBER_QUOTE % text for text in approved),
        ", ".join(MEMBER_QUOTE % text for text in alone))


def rewrite_reason_lines(command, cwd, root):
    """One reason line per rewritable shape on this line, in the order they were found.

    Called only once the approval analysis has declined and the seven opaque shapes have
    passed, so everything here is a command that used to print nothing.
    """
    if HEREDOC_OPERATOR in command or COMMENT_CHAR in command:
        return []
    lines = []
    if carries_line_break(command):
        lines.append(LINE_BREAK_REWRITE_REASON)
    segments = opaque_segments(command)
    for _sep, words in segments:
        quoted = MEMBER_QUOTE % member_text(words)
        for fires, template in ((expands_a_variable, VAR_USE_REWRITE_REASON),
                                (starts_with_tilde, TILDE_REWRITE_REASON),
                                (brace_expansion_refused, BRACE_REWRITE_REASON),
                                (parent_path_component, PARENT_PATH_REWRITE_REASON),
                                (relative_chdir, RELATIVE_CHDIR_REWRITE_REASON)):
            if not fires(words):
                continue
            line = template % quoted
            if line not in lines:
                lines.append(line)
    if lines:
        return lines
    mixed = mixed_sequence_reason(segments, cwd, root)
    return [mixed] if mixed else []


# ── A file authored through the shell ─────────────────────────────────────────


class RedirectMember(object):
    """One member of a command line as the shell will run it: its `words` with every
    redirect taken out, its `redirects` as `(operator, raw target)` in order, and its
    `text` as written — the slice of the command line it occupies."""

    def __init__(self, words, redirects, text):
        self.words, self.redirects, self.text = words, redirects, text


def redirect_members(command, stop_at_line_break):
    """`[(separator, RedirectMember)]` for the command's top-level members, reading
    redirect operators the way bash does — which `opaque_segments` does not: it breaks at
    every `&` and `|`, so `2>&1`, `&> f` and `>| f` come apart there.

    Quote-aware like every reader here: a `>` inside either quote or behind a backslash is
    text. `$(…)`, backticks and `(…)` are one opaque word, as in `opaque_segments`, so a
    write inside a substitution is not judged. A `>(` or `<(` opens a process
    substitution, which is a word and not a redirect.

    With `stop_at_line_break` the walk ends at the first line break outside every quote
    and substitution: on a line carrying a heredoc that is where the body begins, and the
    body is data — the cut `segments_before_line_break` makes for the `cat` heredoc
    exemption. A line whose quotes are still open at the end names no member at all: it
    is the unreadable shape's to answer, not this one's."""
    members, words, redirects, word = [], [], [], []
    pending = [None]            # the operator whose target the next word is
    sep, start = "", 0
    in_single = in_double = escaped = in_backtick = False
    depth, index, length = 0, 0, len(command)

    def end_word():
        if not word:
            return
        token = "".join(word)
        del word[:]
        if pending[0] is not None:
            redirects.append((pending[0], token))
            pending[0] = None
        else:
            words.append(token)

    def flush(end):
        end_word()
        pending[0] = None
        if words or redirects:
            members.append((sep, RedirectMember(list(words), list(redirects),
                                                command[start:end].strip())))
        del words[:]
        del redirects[:]

    while index < length:
        ch = command[index]
        if escaped:
            word.append(ch)
            escaped = False
        elif ch == ESCAPE and not in_single:
            word.append(ch)
            escaped = True
        elif ch == QUOTE_SINGLE and not in_double:
            in_single = not in_single
            word.append(ch)
        elif ch == QUOTE_DOUBLE and not in_single:
            in_double = not in_double
            word.append(ch)
        elif in_single or in_double:
            word.append(ch)
        elif ch == BACKTICK:
            in_backtick = not in_backtick
            word.append(ch)
        elif in_backtick:
            word.append(ch)
        elif ch == SUBSHELL_OPEN:
            depth += 1
            word.append(ch)
        elif ch == SUBSHELL_CLOSE and depth:
            depth -= 1
            word.append(ch)
        elif depth:
            word.append(ch)
        elif ch in REDIRECT_CHARS and command.startswith(SUBSHELL_OPEN, index + 1):
            word.append(ch)                      # `>(…)`: a process substitution
        elif ch == REDIRECT_CHARS_OUT:
            if word and "".join(word).isdigit():
                del word[:]                      # `2>`: the descriptor is the operator's
            end_word()
            op = ch
            if command[index + 1:index + 2] in REDIRECT_OUT_SUFFIXES:
                op += command[index + 1]
            pending[0] = op
            index += len(op)
            continue
        elif ch == REDIRECT_CHARS_IN:
            if word and "".join(word).isdigit():
                del word[:]
            end_word()
            op = next(o for o in REDIRECT_IN_OPS if command.startswith(o, index))
            pending[0] = op
            index += len(op)
            continue
        elif (ch == REDIRECT_BOTH_STREAMS
              and command.startswith(REDIRECT_CHARS_OUT, index + 1)):
            end_word()
            op = REDIRECT_BOTH_STREAMS + REDIRECT_CHARS_OUT
            if command.startswith(REDIRECT_CHARS_OUT, index + len(op)):
                op += REDIRECT_CHARS_OUT
            pending[0] = op
            index += len(op)
            continue
        elif ch in LINE_BREAK_CHARS:
            flush(index)
            if stop_at_line_break:
                return members
            sep, start = ch, index + 1
        elif ch in AUTHORING_SEPARATOR_CHARS:
            flush(index)
            end = index
            while end < length and command[end] in AUTHORING_SEPARATOR_CHARS:
                end += 1
            sep, start = command[index:end], end
            index = end
            continue
        elif ch.isspace():
            end_word()
        else:
            word.append(ch)
        index += 1

    if in_single or in_double or in_backtick:
        return []
    flush(length)
    return members


def file_target(raw):
    """True when a redirect target or a tee operand names a file: not empty, not one of
    NON_FILE_TARGETS, not a process substitution. Where the file is does not matter."""
    if raw.startswith(PROCESS_SUBSTITUTION_PREFIXES):
        return False
    body = word_body(raw)
    return bool(body) and body not in NON_FILE_TARGETS


def writes_to_file(member):
    """True when one of the member's redirects sends its output to a file. `>&2` and
    `2>&1` duplicate a descriptor and are not targets at all."""
    for op, target in member.redirects:
        if op not in REDIRECT_OUTPUT_OPS:
            continue
        if op == REDIRECT_DUP_OP and FD_DUP_TARGET_RE.match(target):
            continue
        if file_target(target):
            return True
    return False


def fed_literally(member):
    """True when the member's input is a heredoc or a herestring on the member itself."""
    return any(op in REDIRECT_LITERAL_OPS for op, _target in member.redirects)


def member_program(member):
    head = program_words(member.words)
    return (command_name(head[0]), head[1:]) if head else (None, [])


def piped_from_literal(sep, previous):
    """True when this member is the right-hand side of a pipe whose left-hand member
    writes literal text: echo/printf, or a heredoc-fed cat."""
    if sep not in PIPE_SEPARATORS or previous is None:
        return False
    name, _args = member_program(previous)
    return (name in AUTHORING_ECHO_PROGRAMS
            or (name == AUTHORING_HEREDOC_FED_PROGRAM and fed_literally(previous)))


def tee_writes_operand(args):
    """True when tee is given a file operand: a word that is not a flag. Heredoc
    delimiters and redirect targets are not in `args` — `redirect_members` took them out."""
    return any(not word_body(a).startswith(FLAG_PREFIX) and file_target(a) for a in args)


def sed_edits_in_place(args):
    """True when sed is told to edit in place: `--in-place[=…]`, or an `i` among the
    leading letters of a single-dash token before any letter that takes a value. The
    scan stops at the first character that is not a letter, so `-i.bak` is in place and
    a brace group (`-{n,i}`) is left to the brace rules, which refuse it on their own."""
    for arg in args:
        body = word_body(arg)
        if body == SED_IN_PLACE_LONG or body.startswith(SED_IN_PLACE_LONG + FLAG_VALUE_SEP):
            return True
        if not body.startswith(FLAG_PREFIX) or body.startswith(FLAG_PREFIX * 2):
            continue
        for letter in body[1:]:
            if letter == SED_IN_PLACE_LETTER:
                return True
            if letter in SED_VALUE_LETTERS or not letter.isalpha():
                break
    return False


def authors_a_file(sep, member, previous):
    """True when this member lands text written in the command itself in a file."""
    name, args = member_program(member)
    if name in AUTHORING_ECHO_PROGRAMS:
        return writes_to_file(member)
    if name == AUTHORING_SED_PROGRAM:
        return sed_edits_in_place(args)
    if name in AUTHORING_LITERAL_PROGRAMS:
        is_tee = name == AUTHORING_TEE_PROGRAM
        if not (fed_literally(member) or (is_tee and piped_from_literal(sep, previous))):
            return False
        return writes_to_file(member) or (is_tee and tee_writes_operand(args))
    return False


def authoring_reason_lines(command):
    """One reason line per member that authors a file through the shell, naming the
    member as written — a sibling of `rewrite_reason_lines`, judged before the opaque
    shapes so `tee f <<'EOF'` is told to use the Write tool rather than to write a script.

    On a line carrying a heredoc only the text before the first line break is judged: the
    body is data, so a Markdown body full of `> quote` lines is never read as redirects.
    A `#` on the judged text means the line is not judged, the guard every rewrite keeps.
    """
    members = redirect_members(command, stop_at_line_break=HEREDOC_OPERATOR in command)
    if any(COMMENT_CHAR in member.text for _sep, member in members):
        return []
    lines, previous = [], None
    for sep, member in members:
        if authors_a_file(sep, member, previous):
            line = SHELL_AUTHORING_REWRITE_REASON % (
                MEMBER_QUOTE % member_text(member.text.split()))
            if line not in lines:
                lines.append(line)
        previous = member
    return lines


def command_verdict(command, cwd, root):
    """(verdict, reason) for the whole line — the tri-state `main()` acts on.

    ALLOW is `command_allowed`'s answer and nothing else. The verdict layer sits ON TOP
    of that oracle rather than replacing it, deliberately: re-deriving approval from
    per-member verdicts would approve lines the whole-line analysis refuses (`ls ;; ls`
    has two approved members and a separator nothing here recognises), and this feature
    may not widen what runs without a prompt. So the only thing this can do to a command
    is turn a silent prompt into a deny that names the fix.
    """
    if root and cwd is not None:
        try:
            if command_allowed(command, cwd, root):
                return VERDICT_ALLOW, DECISION_REASON
        except Exception:   # any analysis failure is a refusal, never an approval
            pass
    # A file authored through the shell, judged after ALLOW has declined and BEFORE the
    # opaque shapes: `tee f <<'EOF'` is a heredoc into something other than `cat`, and its
    # rewrite is the Write tool rather than a script in the scratchpad. Only the members
    # that author a file are named; whatever else the line carries is judged when the
    # model sends what is left of it.
    try:
        authoring = authoring_reason_lines(command)
    except Exception:       # an analysis failure is never a deny
        authoring = []
    if authoring:
        return VERDICT_REWRITE, REASON_PREFIX + REASON_LINE_SEPARATOR.join(authoring)
    try:
        reason = opaque_deny_reason(command)
    except Exception:       # an analysis failure is never a deny
        reason = None
    if reason is not None:
        return VERDICT_REWRITE, reason
    try:
        lines = rewrite_reason_lines(command, cwd, root)
    except Exception:       # likewise
        lines = []
    if lines:
        return VERDICT_REWRITE, REASON_PREFIX + REASON_LINE_SEPARATOR.join(lines)
    return VERDICT_ASK, None


# ── The escalation counter ────────────────────────────────────────────────────


def state_path(session_id, agent_id):
    """Where this caller's opaque-command count lives, or None when the payload names no
    session. No session is no counter: nothing to escalate against, so such a command is
    denied every time rather than ever reaching `ask`."""
    if not isinstance(session_id, str) or not session_id:
        return None
    key = session_id + STATE_KEY_SEPARATOR + (agent_id if isinstance(agent_id, str) else "")
    digest = hashlib.sha256(key.encode("utf-8", "replace")).hexdigest()
    temp = os.environ.get(TMPDIR_ENV) or TMPDIR_FALLBACK
    return os.path.join(temp, STATE_DIR_NAME, digest + STATE_FILE_SUFFIX)


def read_attempts(path):
    try:
        with open(path) as handle:
            return max(0, int(handle.read().strip()))
    except Exception:      # absent, empty, corrupt, unreadable — all count as zero
        return 0


def bump_attempts(path):
    """The new count. A state file that cannot be written is not an error: the count
    stays where it was, which is the safe direction — another deny, never an `ask`."""
    count = read_attempts(path) + 1
    try:
        os.makedirs(os.path.dirname(path), STATE_DIR_MODE)
    except OSError:        # already there, or not creatable
        pass
    try:
        with open(path, "w") as handle:
            handle.write(str(count))
    except OSError:
        pass
    return count


def clear_attempts(path):
    """A command this analysis could read puts the caller back at zero, whether it was
    approved, refused or denied for one of the three older shapes."""
    if not path:
        return
    try:
        os.remove(path)
    except OSError:
        pass


def scratch_root():
    """The runners' per-pass scratch directory, resolved, or None. Absolute and existing
    only: an unset or nonsense value approves nothing."""
    value = os.environ.get(SCRATCH_ENV)
    if not value or not value.startswith(os.sep) or not os.path.isdir(value):
        return None
    return os.path.realpath(value)


def scratch_argument_allowed(token, cwd, root, scratch):
    """An argument AFTER a scratch script. Existence never decides it.

    A relative, non-flag value — including the value after `=` in `--out=../x` — is
    judged LEXICALLY first: `os.path.normpath(os.path.join(cwd, value))` must land
    inside the project root or inside the scratch root, whether or not anything is
    there yet. `value_confined`'s "a value that names nothing on disk is not a path"
    is the right call for a harmless reader argument that only fails on its own
    (`cat ../x`); it is the wrong call here, because a script's argument may well be
    the OUTPUT path it is about to create, and a relative `../x` that does not exist
    would otherwise be approved on the strength of not existing yet and denied the
    moment the script creates it — which way it goes must not depend on timing.
    A bare flag (`--flag`, `-v`) carries no path and needs no such check; an absolute
    value keeps `inside()`'s existing behaviour, which already judges by resolution
    through symlinks rather than by existence.

    Once the lexical check passes (or does not apply), the path still has to clear the
    same confinement every other path in this file gets once it exists: `token_confined`
    against the project root, or `lexically_inside` and `inside` against the scratch
    directory — so a symlink out of either root is not confined even once it exists.
    """
    if FLAG_VALUE_SEP in token:
        value = token.split(FLAG_VALUE_SEP, 1)[1]
    elif token.startswith(FLAG_PREFIX):
        value = None
    else:
        value = token

    if value and not value.startswith(FLAG_PREFIX) and not value.startswith(os.sep):
        candidate = os.path.join(cwd, value)
        if not (lexically_inside(candidate, root) or lexically_inside(candidate, scratch)):
            return False

    return (token_confined(token, cwd, root)
            or (lexically_inside(token, scratch) and inside(token, scratch)))


def scratch_entry_allowed(prog, args, cwd, root):
    """`bash <scratch>/x.sh` and `python3 [-B] <scratch>/x.py` — the one place OUTSIDE
    the project root this analysis approves a script from, and the place the opaque deny
    tells the model to write one. Resolved through symlinks like every other path, so a
    link out of the scratch directory is not a script in it.

    The script may take arguments, each of which must itself be confined — to the project
    root or to the scratch directory — since an argument is one more thing nothing here
    would otherwise have checked, and a scratch script handed `/etc/passwd` reads it as
    surely as `cat` would. A flag BEFORE the script is not a script: `bash -x <scratch>/
    x.sh` changes how bash runs the file, and the first word after the interpreter's own
    flags is the only thing this approves."""
    scratch = scratch_root()
    if scratch is None:
        return False
    if prog == SCRATCH_BASH:
        rest = args
    elif prog == PYTHON_PROGRAM:
        rest = args
        while rest and rest[0] in PYTHON_INTERPRETER_FLAGS:
            rest = rest[1:]
    else:
        return False
    if len(rest) < SCRATCH_SCRIPT_MIN_ARGS:
        return False
    script, script_args = rest[0], rest[1:]
    if not (script.startswith(os.sep) and os.path.lexists(script)
            and inside(script, scratch)):
        return False
    return all(scratch_argument_allowed(a, cwd, root, scratch) for a in script_args)


def entry_script(token, cwd, root, basename):
    """True when the token names `basename` and the file it spells is inside the root —
    resolved through symlinks, like every other path, and required to exist, so a
    basename on its own vouches for nothing.

    The token must carry a DIRECTORY COMPONENT (`./x`, `self/gate.sh`, an absolute path).
    A bare `check-plans.sh` is resolved by bash along `$PATH`, not from the cwd, so the
    file this function would find in the repo and the program bash would run are two
    different things — and the one bash runs is whatever `$PATH` names first. That form
    prompts (self/BACKLOG.md, raised by the permissions-policy-inherit review)."""
    if os.path.basename(token) != basename or not os.path.dirname(token):
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
    """Bare flags carry no path; `--flag=value` and `key=value` carry one in the value.

    A flag with no `=` that carries a `/` is refused outright. Its value is attached to
    the option letter — `grep -f/etc/hosts`, `file -m/etc/hosts` — and where the option
    ends is the program's business, not something this analysis can know, so it cannot
    say which part of the token is the path. `value_confined` returns True for anything
    starting with `-`, which is how those read outside the tree. A prompt, never an
    approval; no flag this hook approves is spelled with a `/` in it.
    """
    if FLAG_VALUE_SEP in token:
        return value_confined(token.split(FLAG_VALUE_SEP, 1)[1], cwd, root)
    if token.startswith(FLAG_PREFIX) and os.sep in token:
        return False
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


def git_location_args(args):
    """`args` past git's global LOCATION options, or None when this side will not read
    what sits in front of the subcommand.

    Only GIT_GLOBAL_LOCATION_OPTIONS is read past, and **nothing else in front of the
    subcommand is skipped**: any other token starting with `-` returns None, so the
    caller sees no subcommand and does not approve. A bare flag is not harmless just
    because it takes no value — `--paginate`/`-p` forces the pager named by config even
    when stdout is not a tty, which is a program this analysis never chose. `--no-pager`
    goes the same way, as an accepted cost of the rule being a listing rather than a
    judgement about each flag.

    A location option's value must be PRESENT and must not itself start with `-`, in
    both the attached (`--git-dir=<path>`) and the separate (`-C <path>`) spellings:
    `git -C` alone and `git -C --git-dir status` name no location, and a reader that
    guessed at one would be guessing about where the command runs.

    **Confinement is not repeated here.** `subcommand_allowed` has already put every
    argument through `token_confined` before this is reached, which covers both
    spellings and every repetition of them — `git -C <root> -C /tmp status` fails there,
    on the second value, whatever this function makes of the first. A second
    confinement path would be a second place for the two to disagree.

    Approval side only. The deny side has its own, wider walk (`git_subcommand_args`),
    which is untouched.
    """
    while args and args[0].startswith(FLAG_PREFIX):
        if args[0].split(FLAG_VALUE_SEP, 1)[0] not in GIT_GLOBAL_LOCATION_OPTIONS:
            return None
        if FLAG_VALUE_SEP in args[0]:
            value = args[0].split(FLAG_VALUE_SEP, 1)[1]
            if not value or value.startswith(FLAG_PREFIX):
                return None
            args = args[1:]
            continue
        if len(args) < 2 or args[1].startswith(FLAG_PREFIX):
            return None
        args = args[2:]
    return args


def git_allowed(args):
    args = git_location_args(args)
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


def runner_form_allowed(runner, args):
    """The runner is allowlisted; this judges the FORM of the invocation. `ruff --fix`
    and a bare `ruff format` rewrite the tree and `mypy --install-types` installs
    packages — none of which is the repo's own code running."""
    forbidden = RUNNER_FORBIDDEN_FLAGS.get(runner, frozenset())
    if any(a.split(FLAG_VALUE_SEP, 1)[0] in forbidden for a in args):
        return False
    if runner == RUNNER_RUFF and args[:1] == [RUNNER_RUFF_FORMAT]:
        return any(a in RUNNER_RUFF_FORMAT_REPORT_FLAGS for a in args[1:])
    return True


def runner_allowed(head):
    for prefix in RUNNER_PREFIXES:
        if len(head) >= len(prefix) and tuple(head[:len(prefix)]) == prefix:
            return runner_form_allowed(prefix[-1], head[len(prefix):])
    return False


def subcommand_allowed(parts, cwd, root):
    """(allowed, cwd after this subcommand)."""
    if not parts or any(all(ch in PUNCTUATION for ch in p) for p in parts):
        return False, cwd

    # An assignment at command position is an ENVIRONMENT PREFIX: bash runs the NEXT
    # word as the program. program_name() would take this word's basename instead, so
    # `X=/tmp/e/pytest src/a.py` read `src/a.py` as an argument to an allowlisted runner
    # while bash executed it. The analysis does not follow a prefix, so it refuses one.
    if ASSIGNMENT_RE.match(parts[0]):
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

    # Before the root check, and the only rule that reaches past it: the runners' own
    # per-pass scratch directory is under $TMPDIR by construction, so a script written
    # there can never be confined to the project root.
    if scratch_entry_allowed(prog, args, cwd, root):
        return True, cwd

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

    state = state_path(payload.get(SESSION_FIELD), payload.get(AGENT_FIELD))

    # The three shape denies go first. None of them needs a root or a cwd — each shape is
    # wrong wherever it runs — and each names a mechanical fix for a command this
    # analysis CAN read, so a specific reason beats the general one below. A command that
    # gets one of them is a command the model spelled readably, which is what the
    # escalation counter is counting, so each clears it.
    for judge, reason in ((chains_chdir, DENY_REASON),
                          (mutates_git_refs, GIT_DENY_REASON),
                          (uses_own_assignment, ASSIGN_DENY_REASON)):
        try:
            fires = judge(command)
        except Exception:  # an analysis failure is never a deny
            fires = False
        if fires:
            clear_attempts(state)
            emit(DECISION_DENY, reason)
            return

    root = project_root()
    cwd = payload.get("cwd")
    # Without a known starting directory inside the root, a relative path in the
    # command could resolve anywhere, so nothing is approved. The verdict is still
    # taken: a command nothing can read is unreadable wherever it runs.
    start = None
    if root and isinstance(cwd, str) and inside(cwd, root):
        start = os.path.realpath(cwd)

    verdict, reason = command_verdict(command, start, root)
    if verdict == VERDICT_ALLOW:
        clear_attempts(state)
        emit(DECISION_ALLOW, DECISION_REASON)
        return
    if verdict == VERDICT_ASK:
        # Read, and not vouched for. The hook prints nothing, so the settings' own rules
        # and then the human decide — and the model has just shown it can write a command
        # this analysis reads, so the escalation count goes back to zero.
        clear_attempts(state)
        return

    attempts = bump_attempts(state) if state else 1
    if attempts <= OPAQUE_REWRITE_ATTEMPTS:
        emit(DECISION_DENY, reason)
        return
    if os.environ.get(HEADLESS_ENV):
        # Nobody is at a terminal to answer an `ask`, so fall through and let the
        # runner's own non-interactive policy decide (RUNNER.md).
        return
    emit(DECISION_ASK, OPAQUE_ASK_REASON)


if __name__ == "__main__":
    main()
