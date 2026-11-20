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
own `$NAME` is used later on the same line, whose reason says to inline the literal. The
git deny's reason is chosen by profile (env_profile.py, imported beside policy.py): the
local layout's locally, and in a Claude Code cloud container one naming the assigned
branch and the started feature — where two more shapes are denied too, from policy.py's
cloud-only entries: switching to another branch, and a push whose target is not the
current one (README.md § The git shape, by profile).

One more deny goes before those three, and it is not about shape: in a session that is an
orchestration record's `session` (hooks/orchestrator_role.py holds the rule) a Bash command
that runs a lifecycle build script (BUILD_SCRIPTS), and an `Agent` call whose prompt opens
with a `feature: <repo>/<slug>` header (an implementer brief, read by brief_header.parse —
`feature: none — <reason>` is not one), are denied with the reason that module renders — an
orchestrator spawns a session per feature and builds nothing itself. The hook is wired for
both tools (wire-settings.py's HOOK_MATCHERS); on `Agent` it answers that deny or prints
nothing, never an allow. The scripts refuse the same session themselves; this is the early
feedback. README.md § The orchestrator role.

On `Agent` there is one more deny, after the orchestrator's: a prompt whose first non-empty
line is not a brief header — `feature: <repo>/<slug>` or `feature: none — <reason>`, defined
once in brief_header.py beside this file — is sent back naming that line, because cost
attribution claims a delegate by it (README.md § The brief header).

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

import fnmatch
import glob
import hashlib
import json
import os
import re
import secrets
import shlex
import subprocess
import sys

# The policy table, imported as a sibling: this script is a hook command Claude Code runs
# from wherever the session sits, so the directory has to come from the file's own path.
# Bytecode writing is off because that path is inside the repo the hook is guarding, and
# a hook has no business leaving a __pycache__ in it.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import policy                                                        # noqa: E402
# The profile detector, the same way: the one place the profile rule lives
# (self/features/review-base-and-cloud-hook/). Guarded, unlike policy: a copy of hooks/
# that lacks it reads as LOCAL — today's answers — rather than crashing every Bash call.
try:
    import env_profile                                               # noqa: E402
except ImportError:
    env_profile = None
# The orchestrator-role rule (self/features/orchestrator-role-guard/), imported the same
# guarded way: a copy of hooks/ without it leaves the rule silent. The rule is written
# once, there, and the lifecycle scripts read the same module (plan-runner-roots.sh).
try:
    import orchestrator_role                                         # noqa: E402
except Exception:  # a missing or broken sibling (or its shared_rules.py) leaves the rule silent
    orchestrator_role = None
# The rules the hook shares with analysis/ and the lifecycle scripts have one definition,
# shared_rules.py (self/features/shared-hook-rules/); orchestrator_role imports it, so a copy
# of hooks/ without it has already left the role rule silent above. Imported the same guarded
# way for the slug pattern below: without it, no slug is admitted (see ORCHESTRATOR_SLUG_RE).
try:
    import shared_rules                                              # noqa: E402
except Exception:
    shared_rules = None
# The brief header (self/features/delegate-cost-claims/): every Agent brief opens with the
# line naming the feature its cost belongs to. Its one definition is brief_header.py beside
# this file, which analysis/capture_planning.py reads too; imported the same guarded way, so
# a copy of hooks/ without it leaves the rule silent.
try:
    import brief_header                                              # noqa: E402
except ImportError:
    brief_header = None

# Hook protocol
HOOK_EVENT = "PreToolUse"
MATCHED_TOOL = "Bash"
# The second tool the hook is wired to (wire-settings.py's HOOK_MATCHERS): it judges only
# the orchestrator-role rule there, below
AGENT_TOOL = "Agent"
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

# The orchestrator role (hooks/orchestrator_role.py holds the rule; README.md § The
# orchestrator role). The first line of every implementer brief is `feature: <repo>/<slug>`
# (ORCHESTRATION.md → Rules), so an `Agent` call whose prompt opens with that header is a
# delegate that would build a feature; and the six scripts that build or close one are the
# shell half. A contract with ORCHESTRATION.md and with the scripts' names — both move
# together. The header is read by brief_header.parse; this bare marker is the fallback
# when that module is missing.
BUILD_BRIEF_MARKER = "feature: "
BUILD_SCRIPTS = ("feature-start.sh", "run-plans.sh", "run-verify.sh", "run-review.sh",
                 "run-batch.sh", "feature-close.sh")
AGENT_PROMPT_FIELD = "prompt"
# The brief-header rule's rewrite: what an Agent prompt must open with, and why. The two
# forms come from brief_header.py, the one definition; the reason is rendered only when
# that module is present.
BRIEF_HEADER_DENY_TEMPLATE = (
    "allow-repo-commands: every Agent brief begins with one line naming the feature its "
    "cost belongs to (CONVENTIONS.md § Delegate briefs). Put `%(feature)s` first — the "
    "repo's name and the feature's slug, nothing after them — or `%(none)s` for work that "
    "belongs to no feature, such as read-only analysis, and send the call again. Cost "
    "attribution claims a delegate by that line (analysis/README.md § The brief header): "
    "without it the delegate's cost is counted by no feature.")
# Which commands RUN a build script (self/features/hook-role-hardening/, F4, and security
# audit round 1, F8/F10). Reading only the program at command position let any wrapper
# through (`env ./feature-start.sh`, `command …`, `env CLAUDE_CODE_SESSION_ID=zz …`, which
# also spoofs the id the scripts' own refusal reads). The judge now reads every command of
# the line (`invokes_build_script`):
#   - a word that NAMES a build script — literally, quoting removed — in a command that is not
#     exempt below is a run, wherever the word stands: `env ./run-plans.sh`, `xargs
#     ./feature-close.sh`, `--exec=./run-plans.sh`, `GIT_EXTERNAL_DIFF=./run-plans.sh git diff`;
#   - a PATTERN — a glob, a brace group, `$…`, a backtick, ANSI-C `$'…'` / `$"…"` (read as
#     matching every name) — is a run only where a program is launched: at command position,
#     and as an argument of a known launcher (BUILD_SCRIPT_LAUNCHERS; `find`'s only after
#     -exec). So `echo $HOME`, `find . -name '*.sh'` and `jq … */report.json` are not;
#   - EXEMPT commands launch nothing they name (BUILD_SCRIPT_READERS, and the read-only or
#     record-writing forms of git, gh, `sed -n Np` and `bash -n`, `exempt_from_build_judge`):
#     a name in them is text — a commit message, a grep pattern — unless the line also runs a
#     launcher, where `cat run-plans.sh | bash` is a run;
#   - a whole-argument `"$(cat <<'EOF' … EOF)"` is read as its body, text to an exempt
#     command and a mention to any other.
# What no name match can see — a wrapper script, `xargs bash` fed names on stdin, a git
# config naming a program, `rg --pre` on a copied script — is the documented limit
# (hooks/README.md → "The orchestrator role"); the lifecycle scripts' own refusal and the
# human prompt on every write are what stand there. Only an orchestrator session is ever
# denied by this.
BUILD_SCRIPT_READERS = frozenset([
    "cat", "head", "tail", "wc", "grep", "egrep", "fgrep", "rg", "ls", "stat", "file",
    "diff", "cmp", "du", "nl", "od", "cksum", "md5sum", "sha1sum", "sha256sum",
    "shellcheck", "realpath", "readlink", "basename", "dirname", "echo", "printf", "jq",
    "date", "pwd", "true", "test", "[",
])
# A reader with one of these flags runs a program it is given (`rg --pre ./x`)
BUILD_SCRIPT_READER_EXEC_FLAGS = ("--pre", "--hostname-bin")
# Programs that run another program from their arguments: a pattern among their arguments
# may expand to a build script's name
BUILD_SCRIPT_LAUNCHERS = frozenset([
    "env", "command", "builtin", "exec", "nohup", "time", "nice", "timeout", "stdbuf",
    "xargs", "sudo", "doas", "su", "runuser", "setsid", "flock", "watch", "chrt", "ionice",
    "taskset", "unbuffer", "script", "strace", "ltrace", "nsenter", "chroot", "busybox",
    "parallel", "bash", "sh", "zsh", "dash", "ksh", "source", ".", "eval", "find", "make",
    "python", "python3", "perl", "ruby", "node",
])
# `find` launches only what follows these
FIND_LAUNCH_FLAGS = frozenset(["-exec", "-execdir", "-ok", "-okdir"])
FIND_EXEC_END = (";", "+", "\\;")
# Shell keywords a command list starts with before its program (`do head "$f"`)
BUILD_SCRIPT_LEAD_KEYWORDS = frozenset(["do", "then", "else", "elif", "if", "while", "until", "!", "{"])
# The exempt forms of git and gh: subcommands that read, or that commit and push records.
# Not exempt with a git global option before the subcommand (`git -c alias.x=… x`), nor with
# a flag that runs a program (`git grep -O<prog>`, `push --receive-pack=<prog>`).
BUILD_SCRIPT_GIT_EXEMPT = frozenset(["commit", "push", "log", "diff", "show", "grep", "status", "add"])
BUILD_SCRIPT_GIT_EXEC_FLAGS = ("-O", "--open-files-in-pager", "--receive-pack", "--upload-pack",
                               "--exec", "--ext-diff", "--textconv")
BUILD_SCRIPT_GH_EXEMPT = frozenset(["pr", "issue", "api", "repo", "release"])
# `sed -n <addr>p` — the hook's own read-only sed shape — and `bash -n <file>`
SED_PRINT_ONLY_RE = re.compile(r"^(?:[0-9]+|\$)?(?:,(?:[0-9]+|\$))?p$")
SYNTAX_ONLY_FLAG = "-n"
SYNTAX_ONLY_SHELLS = frozenset(["bash", "sh"])
# A leading `NAME=value` word is an environment assignment, not the program
ENV_ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# Characters that make a word a pattern bash may expand into a build script's name: a glob,
# a brace group, or a parameter/command substitution (each read as "anything" — `*`).
BUILD_SCRIPT_GLOB_CHARS = frozenset("*?[")
BUILD_SCRIPT_WILDCARD = "*"
BUILD_SCRIPT_EXPANSION_RE = re.compile(r"[@+!?*]\([^()]*\)|\{[^{}]*\}|\$\{[^}]*\}|\$\([^)]*\)?|\$[A-Za-z0-9_@*#?$!-]+|`[^`]*`?|\$\\")
# ANSI-C and locale quoting in the raw line, replaced by the wildcard before the line is read:
# shlex would otherwise drop the `$'` and leave escapes it does not decode (round 1, F8b)
ANSI_C_QUOTE_RE = re.compile(r"\$'(?:[^'\\]|\\.)*'?|\$\"(?:[^\"\\]|\\.)*\"?")
# An extended glob (`@(…)`, `+(…)`, `!(…)`, `?(…)`, `*(…)`), which shlex would split at its
# parentheses: read as the wildcard before the line is tokenized
EXTGLOB_RE = re.compile(r"[@+!?*]\([^()]*\)")
# A whole-argument heredoc substitution, `"$(cat <<'EOF'\n…\nEOF\n)"` — the shape Claude
# Code writes commit messages and PR bodies in — read as its body (round 1, F10)
# — but only where the body ends as bash ends it (`heredoc_body_span`): the head here, the
# tail after the terminator line, and nothing in between to match (hook-audit-gaps, B1)
HEREDOC_ARGUMENT_START = "\"$(cat <<"
HEREDOC_ARGUMENT_HEAD_RE = re.compile(
    r"\"\$\(cat <<(-?)[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2\n")
# (a line continuation may sit before the `)` and before the `"`: bash deletes both there)
HEREDOC_ARGUMENT_TAIL_RE = re.compile(r"(?:\s|\\\n)*\)(?:\\\n)*\"")
HEREDOC_ARGUMENT_STRICT_TAIL = ")\""
# `<<-` strips leading tabs from every body line and from the terminator line
HEREDOC_STRIP_TABS_FLAG = "-"
HEREDOC_TAB = "\t"
# What may stand between a whole-argument heredoc's `<<` and its delimiter, and a character
# of that delimiter (HEREDOC_ARGUMENT_HEAD_RE's own word)
HEREDOC_ARGUMENT_FILL = HEREDOC_STRIP_TABS_FLAG + " " + HEREDOC_TAB
HEREDOC_WORD_CHAR_RE = re.compile(r"[A-Za-z0-9_]")
# How a heredoc body's own line continuations are read (`comment_and_heredoc_free`'s `joins`).
# Bash joins a body line that ends in an ODD run of backslashes with the next one BEFORE it
# looks for the terminator, when the delimiter is unquoted (`EO\⏎F` ends a `<<EOF` body; with
# `<<'EOF'` it is two body lines) — the parser's reading. A backtick substitution's text has
# had every such continuation deleted before any heredoc in it is read, a quoted delimiter's
# body included, and the walk knows only that a backtick came before the operator — so that
# is a second reading. The third joins nothing, which is how this hook read every body until
# round 3 (escalations/02-audit-opus.md, R2-1): kept beside the other two, so that a line it
# denied by reading a body as written is still denied.
HEREDOC_JOINS_PARSER, HEREDOC_JOINS_BACKTICK, HEREDOC_JOINS_AS_WRITTEN = "parser", "backtick", "written"
# A backslash escaped by another: a run of backslashes before a line break continues the line
# only when one is left over after these
ESCAPED_BACKSLASH = "\\\\"
# Inside backticks bash halves every such pair when it takes the substitution's text, and
# deletes a continuation as it does; the substitution's own parser then reads what is left.
# So there a run before a line break, modulo this, is: 1 or 3 — a continuation, deleted with
# its last backslash; 2 — `\⏎` once halved, a continuation to the inner parser, deleted with
# both; 0 — none. The shortest of the second kind is `\\⏎`
BACKTICK_ESCAPE_CYCLE = len(ESCAPED_BACKSLASH) * 2
BACKTICK_CONTINUATION = ESCAPED_BACKSLASH + "\n"
# `heredoc_body_span`'s `joins`: the run of backslashes before a line break whose every
# multiple is NO continuation in the body — never one (a quoted delimiter); an odd run is one
# (an unquoted delimiter, and a quoted one inside backticks); the backtick cycle (an unquoted
# delimiter inside backticks)
HEREDOC_JOIN_NEVER, HEREDOC_JOIN_ODD, HEREDOC_JOIN_BACKTICK = 0, len(ESCAPED_BACKSLASH), BACKTICK_ESCAPE_CYCLE
# A heredoc delimiter holding one of these is not read, and its body not placed: bash keeps a
# `$(…)` or backtick span whole, blanks included, reads `$"x"` as `x` and `$'x'` decoded, and
# takes a carriage return for a character of the word (`<<EOF\r` ends at a line `EOF\r`).
# A plain `$x` or `${x}` is the literal it is to bash.
HEREDOC_DELIMITER_UNREAD_RE = re.compile(r"[`\r]|\$[(\"']")
# Where a `<<` may be a shift and no heredoc: anywhere after an arithmetic opener (`((`, `$[`),
# or inside a word that opened a subscript (`a[1<<2]=5`). Its "body" is not placed.
HEREDOC_SHIFT_RE = re.compile(r"\(\(|\$\[|\[[^\s();<>|&]*$")
# A brace: of a `${…}` expansion, where a `#` is the expansion's own operator or text and
# never a comment, and of a brace group
BRACE_OPEN, BRACE_CLOSE = "{", "}"
# What a whole-argument heredoc stands as in `judged_text`: an empty quoted word
HEREDOC_ARGUMENT_STAND_IN = "\"\""
# A `{x..y[..step]}` brace sequence — letters or integers — and its step when none is given
BRACE_SEQUENCE_RE = re.compile(r"^(-?[0-9]+|[A-Za-z])\.\.(-?[0-9]+|[A-Za-z])(?:\.\.(-?[0-9]+))?$")
BRACE_SEQUENCE_STEP = 1
# What a git command whose braces expand past MAX_BRACE_WORDS is judged as: the first of the
# subcommands that always mutate. A git command that cannot be read is not passed on.
GIT_UNREADABLE_ARGS = (policy.GIT_ALWAYS_MUTATING[0],)
# A carriage return is no blank to bash (`a\r#b` is one word), though the lexer here splits on it
CARRIAGE_RETURN = "\r"
# The redirects that feed a command a FILE on a descriptor (`N<` and `N<>` are these with the
# descriptor dropped): a shell fed a build script that way runs it
REDIRECT_INPUT_FILE_OPS = frozenset(["<", "<>"])
# A bracket expression (`[h]`, `[^x]`, `[!x]`, `[[:alpha:]]`) matches one character, and is read
# as `?`: fnmatch knows neither bash's `[^…]` nor a POSIX class, and would match neither
BUILD_SCRIPT_BRACKET_RE = re.compile(r"\[[!^]?\]?(?:\[[:.=][^\]]*[:.=]\]|[^\]])*\]")
BUILD_SCRIPT_ANY_CHARACTER = "?"
# The words of a line read as text: split at blanks and at every operator character, so a
# pattern glued to one (`true;./run-p*.sh;true`) is still a word of its own
BUILD_SCRIPT_TEXT_SPLIT_RE = re.compile(r"[\s();<>|&]+")
# Filters that never run what they read or are handed on stdin: beside an exempt reader that
# names a build script they launch nothing (`grep -c x run-plans.sh | sort`). Every other
# non-exempt command may (`cat run-plans.sh | unshare sh`): the launcher list is never
# complete. Named bare, so it is PATH's program, and without sort's `--compress-program`
# (any prefix GNU accepts), which is handed the data
BUILD_SCRIPT_FILTERS = frozenset(["sort", "uniq", "cut", "tr", "tee"])
BUILD_SCRIPT_FILTER_EXEC_FLAGS = ("--co",)
# git's `-O<pager>` inside a cluster of short flags (`git grep -nO./x`)
BUILD_SCRIPT_GIT_EXEC_SHORT = "O"
# The placeholder a heredoc body is parked under while the line is read: a fresh random
# token per call, so a command cannot spell one itself (security audit round 2, N4)
HEREDOC_PLACEHOLDER = "__heredoc_%s_%d__"
HEREDOC_PLACEHOLDER_RE_TEMPLATE = r"__heredoc_%s_(\d+)__"
HEREDOC_TOKEN_BYTES = 8
# What quoting does to a line that cannot be tokenized: removed, so `./run-pla""ns.sh` and
# `./run-pla\ns.sh` read as the name they spell
BUILD_SCRIPT_QUOTING_RE = re.compile(r"[\"'\\]")
# A backslash-newline: deleted from the line before it is read, as bash deletes it
LINE_CONTINUATION = "\\\n"
# Characters that glue a pattern to the code around it inside one argument (`system("./run-p*.sh")`)
BUILD_SCRIPT_PIECE_STRIP = "\"'`;(){}|&<>"
# find's placeholder for the file it found: a word, not a pattern
FIND_PLACEHOLDER = "{}"

# Project root resolution
PROJECT_DIR_ENV = "CLAUDE_PROJECT_DIR"

# Chain detection. A directory change sharing a command with anything else is denied.
# Unlike the approval analysis, a line break separates commands here, as it does in bash.
CHDIR_PROGRAMS = frozenset(["cd", "pushd"])
CHAIN_PUNCTUATION = "();<>|&\n"
CHAIN_WHITESPACE = " \t\r"
# Where a `#` may start a comment: at the line's start or right after an unescaped blank or
# operator character — a carriage return is neither; anywhere else in a word it is a literal.
# After a `)` bash starts one only where the paren closed a subshell or a `case` pattern
# (`a=(x)#b` and `$(x)#b` are one word), which the doubt below covers.
COMMENT_PREDECESSORS = frozenset(CHAIN_WHITESPACE + CHAIN_PUNCTUATION) - frozenset(CARRIAGE_RETURN)
# What puts a `#` that may start a comment IN DOUBT: one of these anywhere in the text the walk
# has kept before it, quoted or not (a placed heredoc body and a whole-argument heredoc are
# not kept). Past an opener the walk cannot say whether bash is inside an arithmetic
# expression, a subscript, a pattern or a nested quote, where a `#` after a blank is text
# (`$((1 #b))`, `a[1 #b]=5`, `"$(echo " #")"`), or whether a `)` closed a word. A comment in
# doubt is read both ways, each one on its own — dropped, and kept as the commands it may be —
# and a line with more than MAX_COMMENT_DOUBTS is not read finely at all (hook-audit-gaps
# NOTES.md, coordinator ruling 7)
COMMENT_DOUBT_OPENERS = frozenset("([{`")
MAX_COMMENT_DOUBTS = 5
# The readings a caller of `heredoc_body_span` may ask for of a RUN-ON line — a body line
# inside a substitution that begins with the delimiter and is not the delimiter alone (`EOF)`,
# `EOF )`, `EOFS)`, `EOF x)`: bash 5.2 ends a `$(…)` heredoc there when a `)` follows on the
# line, and runs the rest of it), or, in a backtick substitution, one holding a backtick (the
# substitution's text ends there, and the body with it). Body text (the main parser; an older
# bash inside `$(…)`); the end of the body at a line that begins with the delimiter; or the
# end of the body at a line's backtick. With none asked for, such a body is not placed at
# all. A body may hold several run-on lines and end at any of them: each is tried in turn,
# and a body with more than MAX_RUN_ON_LINES is not read finely
HEREDOC_RUN_ON_IS_BODY, HEREDOC_RUN_ON_ENDS, HEREDOC_RUN_ON_BACKTICK = "body", "ends", "backtick"
MAX_RUN_ON_LINES = 4
SUBSHELL_OPEN, SUBSHELL_CLOSE = "(", ")"
# A `(` directly after a word ending in this opens a command substitution
SUBSTITUTION_PREFIX = "$"
# `$$` is the shell's PID: the quote or brace after it is a plain one (`$$'a\'`, `$${x`)
PID_PARAMETER = SUBSTITUTION_PREFIX * 2
REDIRECT_CHARS = frozenset("<>")
HEREDOC_OPERATOR = "<<"
HERESTRING_OPERATOR = "<<<"
# The environment variable that makes git ignore `refs/replace/`, and the value that sets it
GIT_NO_REPLACE_ENV, GIT_NO_REPLACE_ON = "GIT_NO_REPLACE_OBJECTS", "1"

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
ANSI_C_QUOTE_PREFIX = "$"   # `$'…'`: a quote whose backslashes escape
# Text the analysis cannot see through even when quoted: parent traversal, line breaks,
# and a NUL, which bash truncates at while this analysis would read past it
UNANALYSABLE = ("..", "\n", "\r", "\x00")
# A token beginning with this expands to a home directory
TILDE = "~"
FLAG_PREFIX = "-"
# Both option prefixes a shell takes: `+n`, `+o noexec` undo `-n` (round 2, N1)
OPTION_PREFIXES = ("-", "+")
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

# git subcommands that only read; `branch`, `stash` and `worktree` are narrowed further
GIT_READ_ONLY_SUBCOMMANDS = frozenset([
    "blame", "branch", "describe", "diff", "log", "ls-files", "rev-parse",
    "shortlog", "show", "stash", "status", "worktree",
])
# Which `stash` subcommands read (`list`, `show`) is the table's answer too, for the same
# reason as `worktree` below
GIT_STASH = policy.GIT_STASH
GIT_STASH_READ_ONLY = policy.stash_read_only()
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
GIT_DIR_FLAG = "--git-dir"
GIT_GLOBAL_LOCATION_OPTIONS = frozenset(["-C", GIT_DIR_FLAG, "--work-tree"])
# What a read behind those options may use: the root checkout's own git directory, its
# common directory (named by a linked worktree's `commondir` file) or a direct child of the
# common directory's `worktrees/` — never one planted in the tree (read_uses_own_gitdir).
# Git stops its discovery at a directory holding `.git` (GIT_DOT_ENTRY) or `HEAD` (GIT_HEAD,
# the file every git directory holds), so the walk stops at either too.
GIT_COMMONDIR_FILE = shared_rules.COMMONDIR_NAME if shared_rules is not None else ""
GIT_WORKTREES_DIR = "worktrees"
# A location value bash would expand as a pattern names no directory this side can judge:
# `git -C plans/e?il status` is read here as the literal word, while bash runs git in
# `plans/evil`, a planted git directory (self/features/hook-silent-allow-sweep/, item 1). A
# glob character or an extglob opener anywhere in a location value approves nothing.
GIT_LOCATION_PATTERN_CHARS = frozenset("*?[")

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
# Denied whatever their arguments. `stash` is not among them any more: it is denied
# unless its first argument is one of GIT_STASH_READ_ONLY (`git_mutates`).
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

# ── The git deny, by profile ──────────────────────────────────────────────────
# Which profile this session runs under is env_profile.py's to say (the module beside
# this file, imported in-process: no process per Bash call), never this file's — it
# spells neither profile variable, and self/profile-confinement.sh keeps it that way.
# Locally nothing below changes an answer but one: GIT_DENY_REASON, the local layout's, is
# printed exactly as before, and a push to `main` — denied in BOTH profiles since round 2,
# read from the words alone — gets GIT_PUSH_PROTECTED_DENY_REASON (below). Under `cloud`
# (self/features/review-base-and-cloud-hook/):
#   - the git deny's reason is the cloud one — this container IS the feature's checkout
#     on its branch — naming the branch, and the started feature and its close when one
#     exists, the way session-start.sh orients a session;
#   - and the table's two cloud-only entries are enforced (policy.GIT_CLOUD_ONLY):
#     switching away from the current branch, and a push whose target is not it.
# Everything that needs the repository — the current branch, the started feature, whether
# a `git checkout` argument names a commit — is asked of git in a subprocess, and ONLY on
# the cloud path of a git command that could be denied. Any failure there (a detached
# HEAD, no repo, git missing, a timeout) leaves today's answer in place, never a crash and
# never an allow; an invalid profile reads as local.
GIT_CLOUD_ONLY_RULE = policy.cloud_only_rule
CLOUD_SWITCH_AWAY = policy.CLOUD_SWITCH_AWAY
CLOUD_PUSH_ELSEWHERE = policy.CLOUD_PUSH_ELSEWHERE
GIT_SWITCH_DETACH_FLAGS = policy.GIT_SWITCH_DETACH_FLAGS
GIT_CHECKOUT_DETACH_FLAGS = policy.GIT_CHECKOUT_DETACH_FLAGS
GIT_ORPHAN_FLAG = policy.GIT_ORPHAN_FLAG
GIT_PREVIOUS_BRANCH = policy.GIT_PREVIOUS_BRANCH
GIT_PUSH_EVERY_REF_FLAGS = policy.GIT_PUSH_EVERY_REF_FLAGS
GIT_PUSH_DELETE_FLAGS = policy.GIT_PUSH_DELETE_FLAGS
# ── The push to `main`, in BOTH profiles ──────────────────────────────────────
# policy.GIT_HOOK_ONLY's entry (self/features/review-base-and-cloud-hook/SPEC.md → "Round
# 2"): a push whose destination is policy.GIT_PROTECTED_BRANCH is refused locally and in
# the cloud. Locally it is read from the command's words alone — no git probe, so a bare
# `git push` while checked out on `main` is not caught there (NOTES.md ruling 21); in the
# cloud the current branch is read anyway, so `HEAD` and a push with no refspec resolve to
# it. The cloud refuses it with the cloud reason; locally it has its own.
GIT_HOOK_ONLY_RULE = policy.hook_only_rule
PUSH_TO_PROTECTED = policy.PUSH_TO_PROTECTED
GIT_PROTECTED_BRANCH = policy.GIT_PROTECTED_BRANCH
GIT_PUSH_PROTECTED_DENY_REASON = (
    "allow-repo-commands: this git command pushes to `%(protected)s`, and agents never push "
    "`%(protected)s` (LIFECYCLE.md § The three rules, rule 2). Push the feature's own "
    "branch — the one you are on — instead. Work reaches `%(protected)s` only through the "
    "PR that feature-close.sh opens after a clean review (LIFECYCLE.md step 6), and a "
    "human merges it (step 7); nothing an agent runs pushes it. Commit on the branch you are on "
    "and say what you need instead." % {"protected": GIT_PROTECTED_BRANCH})
# How the arguments are READ — parsing helpers, not policy, so they stay here beside the
# reader like GIT_BRANCH_VALUE_FLAGS. Flags of each verb that take the NEXT token as their
# value, so the value is not mistaken for the branch or the refspec.
GIT_SWITCH_VALUE_FLAGS = frozenset(["-c", "-C", GIT_ORPHAN_FLAG])
GIT_CHECKOUT_VALUE_FLAGS = frozenset(["-b", "-B", GIT_ORPHAN_FLAG])
# `--repo <r>` / `--repo=<r>` NAMES the remote, so every positional after it is a refspec
# (round 2: `git push --repo origin main` is judged like `git push origin main`)
GIT_PUSH_REPO_FLAG = "--repo"
GIT_PUSH_VALUE_FLAGS = frozenset([GIT_PUSH_REPO_FLAG, "--receive-pack", "--exec",
                                  "--push-option"])
GIT_PUSH_VALUE_LETTER = "o"                       # `-o <option>`, also `-o<option>`
GIT_PUSH_DELETE_LETTER = "d"                      # `-d`, also inside `-ud`
GIT_PUSH_FORCE_LETTER = "f"                       # `-f`, also inside `-fu`, `-uf`
# A `git checkout` that restores files and switches nothing: everything after `--` is a
# path, and these flags make every positional one.
GIT_PATHSPEC_SEPARATOR = "--"
GIT_CHECKOUT_PATH_FLAGS = frozenset(["-p", "--patch", "--pathspec-from-file"])
# Names that mean "the branch I am on"
GIT_HEAD_NAMES = frozenset(["HEAD", "@"])
GIT_BRANCH_REF_PREFIX = "refs/heads/"
# A refspec: `[+]<src>[:<dst>]`; an empty src deletes dst
GIT_REFSPEC_FORCE_PREFIX = "+"
GIT_REFSPEC_SEPARATOR = ":"
LONG_FLAG_PREFIX = "--"
# The git calls, each bounded: a hook that hangs stalls every Bash call in the session.
# `rev-parse --show-toplevel --symbolic-full-name HEAD` answers the checkout's root and
# its branch in one process (`HEAD` alone on a detached HEAD).
GIT_LOCATION_FLAG = "-C"
# ── The approved push, in the cloud only (self/features/cloud-checkpoint-push/) ────────
# A container is reclaimed with whatever it never pushed, so `git push [-u] origin <B>` is
# approved silently when `<B>` is the checkout's current branch AND a tracked manifest's
# branches[0] — the started feature's own branch (own_push_allowed). The remote is the same
# name plan-runner-roots.sh pushes to (PUSH_REMOTE); a branch is a plain name, so none of
# `+<B>`, `<B>:<B>`, `HEAD` or `refs/heads/<B>` is approved.
OWN_PUSH_REMOTE = "origin"
OWN_PUSH_UPSTREAM_FLAGS = ("-u", "--set-upstream")
OWN_PUSH_BRANCH_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9._/-]*$")
# The push runs against the root checkout's OWN git directory and an effective config that
# redirects and executes nothing (self/features/own-push-real-gitdir/NOTES.md rulings 1-5).
# The checkout is found by walking the filesystem — the nearest directory at or above the
# root holding a `.git` entry — never by asking git, which a planted git directory can fool
# (`core.worktree` makes `--show-toplevel` report the root). Its git directory is that `.git`
# directory, or the path on the `gitdir:` line of a `.git` file (a linked worktree).
GIT_DOT_ENTRY = shared_rules.GIT_ENTRY if shared_rules is not None else ""  # "" approves nothing
OWN_PUSH_GITFILE_RE = re.compile(r"^gitdir: (.+)$")
OWN_PUSH_GITFILE_MAX_BYTES = 4096
GIT_PROBE_GITDIR_AND_TOPLEVEL = ("rev-parse", "--absolute-git-dir", "--show-toplevel")
GIT_PROBE_COMMON_DIR = ("rev-parse", "--git-common-dir")
GIT_PROBE_PUSH_URLS = ("remote", "get-url", "--push", "--all", OWN_PUSH_REMOTE)
# `git config --list -z`: every scope, one NUL-ended record per entry, `key\nvalue` (a key
# with no value has no newline). Git prints section and key lower-case, the subsection as written.
GIT_PROBE_CONFIG_LIST = ("config", "--list", "-z")
CONFIG_RECORD_SEPARATOR = "\0"
CONFIG_VALUE_SEPARATOR = "\n"
# A key present at all means a prompt: each redirects a push, runs a program, or names a
# file the tree could change between the probe and the push. `remote.origin.*` is the remote
# this approval pushes to (OWN_PUSH_REMOTE). `credential.helper`, `credential.<sub>.helper`
# and `core.askpass` name a program git runs when the server asks for credentials (a
# `!`-prefixed helper is a shell command): own-push-credential-keys.
OWN_PUSH_PRESENT_KEYS = frozenset([
    "remote.origin.push", "remote.origin.pushurl", "remote.origin.receivepack",
    "remote.origin.vcs", "remote.origin.mirror", "remote.pushdefault",
    "core.sshcommand", "core.hookspath", "core.fsmonitor",
    "push.recursesubmodules", "push.gpgsign", "pager.push", "include.path",
    "submodule.recurse", "push.followtags",
    "credential.helper", "core.askpass",
])
# `.*`, not `.+`: an empty subsection (`[credential ""]` lists as `credential..helper`) counts.
OWN_PUSH_PRESENT_KEY_RES = (re.compile(r"^branch\..*\.pushremote$"),
                            re.compile(r"^includeif\..*\.path$"),
                            re.compile(r"^hook\..*\.(event|command)$"),
                            re.compile(r"^credential\..*\.helper$"),
                            re.compile(r"^remote\..*\.proxy$"))
# The transport (own-push-transport-keys): `http.*` is deny-by-default. Any `http.<var>` or
# `http.<url>.<var>` whose variable is not in this short set prompts, so a proxy, a TLS
# setting (`sslverify`, `sslcainfo`, `sslcert`, `sslkey`, `sslbackend`, `proxyssl*`), a
# `curloptresolve`, a cookie file, an `extraheader`, `emptyauth`, `followredirects` and any
# variable a newer git adds all prompt. Each kept variable tunes the transfer and neither
# redirects it, weakens TLS nor names a file; the cloud's ~/.gitconfig sets `proxyauthmethod`.
OWN_PUSH_HTTP_SECTION = "http"
OWN_PUSH_HTTP_SAFE_VARS = frozenset([
    "proxyauthmethod", "postbuffer", "lowspeedlimit", "lowspeedtime",
    "maxrequests", "minsessions", "version",
])
# The askpass programs git runs from the environment: a NON-EMPTY value prompts. An empty one
# runs nothing (git's `askpass && *askpass`), and the cloud container sets GIT_ASKPASS empty.
OWN_PUSH_ASKPASS_ENVS = ("GIT_ASKPASS", "SSH_ASKPASS")
# The helper programs git runs from the environment: SET at all, even empty, prompts. Git runs
# `git-remote-https` and its other dashed helpers from GIT_EXEC_PATH; the three ssh ones are
# listed for completeness, though an https origin does not use them
# (self/features/hook-silent-allow-sweep/, item 2).
OWN_PUSH_HELPER_ENVS = ("GIT_EXEC_PATH", "GIT_SSH", "GIT_SSH_COMMAND", "GIT_PROXY_COMMAND")
# Removed from every probe's environment. GIT_CONFIG replaces the file `git config` reads and
# no other git command's, so a GIT_CONFIG naming a url-only file hid every key the own-push
# probe looks for while the push itself still read them (item 3).
GIT_PROBE_DROPPED_ENVS = frozenset(["GIT_CONFIG"])
OWN_PUSH_DEFAULT_KEY = "push.default"
OWN_PUSH_DEFAULT_VALUES = frozenset(["simple", "current"])
# The origin url: exactly one value, http(s), and no `url.*.insteadOf` / `pushInsteadOf`
# that applies to it (`remote get-url --push --all` prints the rewritten urls)
OWN_PUSH_URL_KEY = "remote.origin.url"
OWN_PUSH_URL_SCHEMES = ("https://", "http://")
# The two hooks a push runs locally, looked for in the common git directory's default
# hooks directory (`core.hookspath` already prompts), as any file type
GIT_HOOKS_DIR = "hooks"
OWN_PUSH_HOOKS = ("pre-push", "reference-transaction")
GIT_PROBE_TIMEOUT_SECONDS = 5
GIT_PROBE_TOPLEVEL_AND_HEAD = ("rev-parse", "--show-toplevel", "--symbolic-full-name",
                               "HEAD")
GIT_PROBE_COMMIT = ("rev-parse", "--verify", "--quiet")
GIT_COMMIT_PEEL = "^{commit}"
# Remote-tracking branch names, `origin/x` → `x`: what `git checkout x` / `git switch x`
# would create a local branch from when no local `x` exists
GIT_PROBE_REMOTE_BRANCHES = ("for-each-ref", "--format=%(refname:lstrip=3)", "refs/remotes")
# The started feature: a tracked manifest whose `branches[0]` is this branch — the reading
# session-start.sh makes (git grep narrows, the fence decides; a fence with no branches
# reads as its slug, plan-runner-roots.sh's manifest_branch).
GIT_PROBE_GREP = ("grep", "-l", "-F", "-e")
MANIFEST_NAME = "README.md"
MANIFEST_FENCE_OPEN_RE = re.compile(r"^```json\s*$")
MANIFEST_FENCE_CLOSE_RE = re.compile(r"^```\s*$")
MANIFEST_BRANCHES_FIELD = "branches"
# The repo's shape, from where THIS file sits relative to the project root: agentTooling's
# own checkout (the hook at <root>/hooks/) spells `./feature-start.sh --self` and keeps its
# features in self/features; a consuming repo vendors it (at <root>/agentTooling/hooks/)
# and keeps them in plans/features. session-start.sh's TOOL_PREFIX / SELF_ARG, read the
# same way.
SELF_TOOL_PREFIX = "./"
SELF_ARG = "--self "
SELF_FEATURES_DIR = "self/features"
CONSUMER_FEATURES_DIR = "plans/features"
VENDORED_DIR_DEFAULT = "agentTooling"
TOOL_PREFIX_TEMPLATE = "./%s/"
# The branch, as the reason names it, and what it says when it cannot be read
BRANCH_QUOTE = "`%s`"
BRANCH_UNKNOWN = ("this session's assigned branch (HEAD is detached or unreadable here, "
                  "so it could not be named)")
GIT_CLOUD_DENY_REASON_TEMPLATE = (
    "allow-repo-commands: this git command creates, switches or deletes a branch, pushes "
    "somewhere other than this branch, or moves a ref, and agents never do that "
    "(LIFECYCLE.md § The three rules, rule 2). This is a Claude Code cloud container: it "
    "IS the feature's checkout, on %(branch)s — no worktree, and no other branch to make, "
    "switch to or push. %(feature)s Commit on %(branch)s, push only %(branch)s, and say "
    "what you need instead.")
GIT_CLOUD_STARTED_TEMPLATE = (
    "Feature '%(slug)s' is started on this branch (%(manifest)s, written by "
    "feature-start.sh): build it here, and close it with "
    "`%(prefix)sfeature-close.sh %(self_arg)s%(slug)s` after a clean review and BEFORE "
    "the merge — merging the PR is the last step.")
GIT_CLOUD_UNSTARTED_TEMPLATE = (
    "Start the feature here, on this branch, with "
    "`%(prefix)sfeature-start.sh %(self_arg)s<slug>` — it makes no worktree and no other "
    "branch; `%(prefix)sfeature-close.sh %(self_arg)s<slug>` is the way out, after a clean "
    "review and before the merge.")
# The off-branch case (self/features/cloud-off-branch-remedy/): a container the platform
# restarted after reclaiming it comes back cloned on `main`, not on the feature's branch,
# while the feature's committed manifest still names that branch. A switch to it is still
# refused — the cloud never switches away, and no carve-out lets this one through (the
# fence's NOTES.md says why) — but the cloud reason above would offer "commit on `main`,
# push only `main`" as the remedy, the forbidden action. When the checkout is on
# GIT_PROTECTED_BRANCH or detached and the switch names a branch a tracked manifest records
# as `branches[0]`, this reason is printed instead; it never tells the agent to commit or
# push the base. `%(here)s` is the current branch quoted, or OFF_BRANCH_DETACHED.
GIT_REMOTE_REF_PREFIX = "refs/remotes/"
GIT_REMOTE_SEPARATOR = "/"
# The manifest normally lives on the feature's branch, not on `main`, so besides the
# checkout's tracked manifests the commit the switch would land on is searched too:
# `git grep <tree>` prints `<tree>:<path>`, and `git show <tree>:<path>` reads it.
GIT_TREE_PATH_SEPARATOR = ":"
GIT_SHOW = "show"
GIT_PROBE_REMOTE_REFS = ("for-each-ref", "--format=%(refname)", "refs/remotes")
OFF_BRANCH_DETACHED = "a detached HEAD"
GIT_CLOUD_OFF_BRANCH_TEMPLATE = (
    "allow-repo-commands: this git command switches this container to `%(target)s`, and a "
    "Claude Code cloud session never switches branches (LIFECYCLE.md § The three rules, "
    "rule 2). `%(target)s` is feature '%(slug)s''s branch (%(manifest)s, written by "
    "feature-start.sh), and this container is OFF it, on %(here)s: a container the "
    "platform reclaimed and restarted comes back cloned on `%(protected)s`, not on the "
    "feature's branch. The session cannot fix that itself. The remedy is a fresh session "
    "launched on `%(target)s`, or the human checking `%(target)s` out in this container. "
    "Do not commit or push here, and do not start a feature on `%(protected)s`: stop, and "
    "say that this container is off its feature's branch `%(target)s`.")
# The cached-clone case (self/features/detached-at-branch-tip-attach/): a session launched
# to CONTINUE a feature's branch can come up with HEAD detached exactly at
# origin/<branch>, the local <branch> a stale ancestor from an earlier clone — and a fresh
# session reproduces it, so the off-branch remedy above does not cure it. On a detached
# HEAD in the cloud, a `git switch`/`git checkout` that would put the working tree on a
# commit other than HEAD's is refused (`detached_switch_moves`; the stale local ref is the
# trap), and one landing on HEAD's own commit is not. Every cloud refusal on a detached
# HEAD that is ATTACHABLE — `attachable_branch`, plan-runner-roots.sh's
# attachable_branches in Python: a tracked manifest's branches[0] whose
# refs/remotes/origin/<branch> IS HEAD's commit and whose local ref is absent or an
# ancestor of HEAD — gets this reason, naming attach-branch.sh, which checks the same
# conditions and re-attaches moving nothing. `git checkout -B` and friends stay refused:
# the settings file's prefix rules refuse them whatever this hook says.
GIT_HEAD = "HEAD"
GIT_ATTACH_REMOTE_PREFIX = "refs/remotes/origin/"
GIT_PROBE_IS_ANCESTOR = ("merge-base", "--is-ancestor")
GIT_PROBE_ATTACH_CANDIDATES = ("for-each-ref", "--points-at", GIT_HEAD,
                               "--format=%(refname:lstrip=3)", "refs/remotes/origin")
ATTACH_SCRIPT = "attach-branch.sh"
GIT_CLOUD_ATTACH_TEMPLATE = (
    "allow-repo-commands: this git command moves or makes a branch ref, switches the "
    "working tree to another commit, or pushes from a detached HEAD, and a Claude Code "
    "cloud session never does that itself (LIFECYCLE.md § The three rules, rule 2). This "
    "container's HEAD is detached exactly at `origin/%(branch)s`, the tip of feature "
    "'%(slug)s''s branch (%(manifest)s), and the local `%(branch)s` is absent or behind "
    "it: the platform re-checked-out a cached clone detached, and a fresh session will not "
    "cure that. Re-attach with `%(command)s` — it checks exactly that, points "
    "`%(branch)s` at HEAD and checks it out, so it moves nothing — then build, commit and "
    "push `%(branch)s` here. Not `git checkout -B`, and not a plain `git checkout "
    "%(branch)s`, which would land on the stale local commit.")

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
# ── The runners' flag allowlists (self/features/runner-write-allows/) ───────────
# "Repo code runs" (README.md → Accepted limits) covers a suite executing what the repo
# contains; it does not cover a linter rewriting that code, a type checker running an
# interpreter or installing packages, or a runner writing a report file. Each of ruff,
# mypy and pytest is approved only in the words listed here, matched EXACTLY word by word:
# an abbreviation (`mypy --inst` is `--install-types`), an unknown flag, an attached short
# value (`-kfoo`), a bare `--` and any `@file` argument file is no approval, so a flag this
# list does not know prompts. A value-taking flag lists as one: its value is the next word
# (or the `=` of a long flag), and that word starts with neither `-` nor `@`.
RUNNER_RUFF = "ruff"
RUNNER_MYPY = "mypy"
RUNNER_PYTEST = "pytest"
RUNNER_ARGFILE_PREFIX = "@"
RUNNER_LONG_PREFIX = "--"
# ruff: the read-only subcommands. `clean` deletes the cache, `server` and `analyze` are
# not a lint, and any other word prompts.
RUNNER_RUFF_CHECK = "check"
RUNNER_RUFF_FORMAT = "format"
RUNNER_RUFF_VERSION = "version"
RUNNER_RUFF_RULE = "rule"
RUNNER_RUFF_RULE_WORDS = 2                  # `rule <code>`
# `ruff format` rewrites every file it is given unless it is only reporting
RUNNER_RUFF_FORMAT_REPORT_FLAGS = frozenset(["--check", "--diff"])
# `--version`/`-h` and friends: with no subcommand, one of these is the whole command
RUNNER_INFO_FLAGS = frozenset(["--version", "-V", "--help", "-h"])
RUNNER_BARE_FLAGS = {
    RUNNER_RUFF: frozenset([
        # file selection
        "--respect-gitignore", "--no-respect-gitignore", "--force-exclude",
        "--no-force-exclude",
        # settings and output
        "--preview", "--no-preview", "--isolated", "--no-cache", "--statistics",
        "--show-fixes", "--no-show-fixes", "--show-files", "--show-settings", "--diff",
        "--check", "--no-fix", "--exit-zero", "-e", "-q", "--quiet", "-s", "--silent",
        "-v", "--verbose",
    ]) | RUNNER_INFO_FLAGS,
    RUNNER_MYPY: frozenset([
        # strictness
        "--strict", "--ignore-missing-imports", "--check-untyped-defs",
        "--disallow-untyped-defs", "--disallow-incomplete-defs", "--warn-unused-ignores",
        "--warn-return-any", "--warn-redundant-casts", "--no-implicit-optional",
        # import handling
        "--namespace-packages", "--explicit-package-bases",
        # output
        "--show-error-codes", "--hide-error-codes", "--show-column-numbers",
        "--show-error-context", "--hide-error-context", "--pretty", "--no-pretty",
        "--no-error-summary", "--no-color-output", "--color-output", "--show-traceback",
        # run settings
        "--no-incremental",
    ]) | RUNNER_INFO_FLAGS,
    RUNNER_PYTEST: frozenset([
        # verbosity
        "--quiet", "--verbose", "--exitfirst", "--showlocals",
        # run control and output
        "--strict-markers", "--disable-warnings", "--no-header", "--no-summary",
        "--co", "--collect-only", "--lf", "--last-failed", "--ff", "--failed-first",
        "--sw", "--stepwise",
    ]) | RUNNER_INFO_FLAGS,
}
RUNNER_VALUE_FLAGS = {
    RUNNER_RUFF: frozenset([
        # rule selection
        "--select", "--ignore", "--extend-select", "--extend-ignore", "--per-file-ignores",
        "--extend-per-file-ignores",
        # file selection
        "--exclude", "--extend-exclude",
        # settings and output
        "--target-version", "--line-length", "--output-format",
    ]),
    RUNNER_MYPY: frozenset([
        # targets
        "-p", "--package", "-m", "--module",
        # import handling and run settings
        "--follow-imports", "--python-version", "--platform", "--soft-error-limit",
    ]),
    RUNNER_PYTEST: frozenset([
        # selection
        "-k", "-m", "--deselect", "--ignore", "--ignore-glob",
        # run control and output
        "--maxfail", "--tb", "--durations", "--color", "-n",
    ]),
}
# A settings file as a value: approved only when it names an existing regular file inside
# the root (an inline `--config 'fix = true'` is a TOML override that turns `fix` on)
RUNNER_CONFIG_FLAGS = {
    RUNNER_RUFF: frozenset(["--config"]),
    RUNNER_MYPY: frozenset(["--config-file"]),
    RUNNER_PYTEST: frozenset(),
}
# ...and only under a name the tool finds by itself, so the flag names nothing a run would
# not have read anyway: `--config fix.toml` (holding `fix = true`) rewrote the tree and a
# `--config-file cfg.ini` with `junit_xml` or `plugins` wrote or imported
# (self/features/hook-silent-allow-sweep/, item 5)
RUNNER_CONFIG_NAMES = {
    RUNNER_RUFF: frozenset(["pyproject.toml", "ruff.toml", ".ruff.toml"]),
    RUNNER_MYPY: frozenset(["mypy.ini", ".mypy.ini", "pyproject.toml", "setup.cfg"]),
    RUNNER_PYTEST: frozenset(),
}
# pytest's short letters bundle: `-qx`, `-vv`, and `-r<chars>` with its report set
RUNNER_SHORT_BUNDLES = {
    RUNNER_RUFF: (),
    RUNNER_MYPY: (),
    RUNNER_PYTEST: (re.compile(r"-[qvxsl]+"), re.compile(r"-r[fEsxXpPaAwN]+")),
}

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
ENTRY_REPORT = "report.py"
ENTRY_CAPTURE_PLANNING = "capture_planning.py"
ENTRY_MANIFEST = "manifest.py"
# The three Python scripts are approved only at their real places, PINNED (self/features/
# runner-write-allows/): `<root>/analysis/<script>` in agentTooling's own checkout and
# `<root>/agentTooling/analysis/<script>` in a consuming repo — the lexical path equal to
# one of those, with no symlink component below the root. A file that merely carries the
# basename is not the script. gate.sh and check-plans.sh are matched by their known
# spellings below, and a token with a symlink component below the root is no approval either.
ENTRY_PINNED_OWN = "analysis"
ENTRY_PINNED_VENDORED = os.path.join("agentTooling", "analysis")
# Of the two, only the one beside the running hook is pinned — `analysis/` for
# `<root>/hooks/…`, `agentTooling/analysis/` for `<root>/agentTooling/hooks/…`, the way
# `orchestrator_tooling_file` pins — so a planted copy at the other path prompts
# (self/features/hook-silent-allow-sweep/, item 6). The gate and check-plans are approved
# only at their known spellings, relative to the root; the same basename elsewhere prompts.
ENTRY_GATE_SPELLINGS = frozenset([os.path.join("self", ENTRY_GATE), os.path.join("plans", ENTRY_GATE)])
ENTRY_CHECK_PLANS_SPELLINGS = frozenset([ENTRY_CHECK_PLANS,
                                         os.path.join("agentTooling", ENTRY_CHECK_PLANS)])
# `<root>/analysis/report.py` without --self writes to `<root>/../plans/features/`, outside
# the root, so it needs --self; the vendored script writes `<root>/plans/features/` either way.
ENTRY_PINNED_NEEDS_SELF = ENTRY_PINNED_OWN
# report.py [--self] <slug> | --all | --rounds-md <slug> | --orchestration <slug>: those
# words and no others (`--arm-root` and `--checkout` move the artifact root and prompt)
REPORT_ALL_FLAG = "--all"
REPORT_ROUNDS_FLAG = "--rounds-md"
REPORT_ORCHESTRATION_FLAG = "--orchestration"
# capture_planning.py and manifest.py are approved only in their documented read-only
# shapes, matched EXACTLY word by word (self/features/python-entry-exact/): searching the
# words for a listing flag or a `get` let argparse read something else — the last of a
# repeated option, a unique-prefix abbreviation (`--forc` is `--force`), a decoy value
# that looks like a flag. Any word the shape does not name, a repeat, or a `--x=y` form is
# no approval, and nothing here emulates argparse.
ENTRY_SELF_FLAG = "--self"                  # first word only, as the docs spell it
# The lifecycle's one slug pattern (shared_rules.SLUG_RE); without shared_rules.py it
# matches nothing, so the form is handed to the human rather than approved
ENTRY_SLUG_RE = shared_rules.SLUG_RE if shared_rules is not None else re.compile(r"(?!)")
# capture_planning.py [--self] --list-sessions|--list-subagents [its options, each once]
CAPTURE_LISTING_OPTIONS = {
    "--list-sessions": frozenset(["--unclaimed", "--since"]),
    "--list-subagents": frozenset(["--unclaimed", "--everywhere", "--since", "--for"]),
}
CAPTURE_VALUE_OPTIONS = frozenset(["--since", "--for"])  # each takes the next, dashless word
# manifest.py [--self] [--orchestration] <slug> get <key> — `init` and every `set-*`
# rewrite a fence
MANIFEST_ORCHESTRATION_SCOPE = "--orchestration"
MANIFEST_READ_SUBCOMMAND = "get"
# Syntax checkers: `bash -n` parses without executing, and shellcheck only reads. Both
# take files and no other flag; every file is checked against the root like any path.
SYNTAX_BASH = "bash"
SYNTAX_BASH_PARSE_FLAG = "-n"
SYNTAX_SHELLCHECK = "shellcheck"
# `python3 [-B] -m py_compile <files>` — the gate's own python syntax check. -B is accepted
# wherever python is. It does NOT stop py_compile writing `__pycache__/*.pyc`: that write is
# the check's own output, confined to the root, and is listed under hooks/README.md's "Tool
# caches" accepted limit.
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
# An input redirect from a file. On an interpreter it IS the script — `ls | python3 <
# a.py` runs a.py, which anyone can open — so a member carrying one is not a pipe into an
# interpreter with no script. A heredoc or herestring is `<<`/`<<<`, never this.
REDIRECT_SCRIPT_OP = "<"
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
# A timer in place of a notification (self/DESIGN-2026-10-05-cloud-execution.md §9). It
# used to fall through to a silent prompt; this only ever turns that prompt into a deny,
# never into an approval. ORCHESTRATION.md's rule: nobody polls, ever.
SLEEP_PROGRAM = "sleep"
SLEEP_REWRITE_REASON = (
    "%s waits on a timer, and nobody polls (ORCHESTRATION.md): run the long command in "
    "the background and wait for the notification it sends when it exits, rather than "
    "sleeping to check on it.")
MIXED_SEQUENCE_REWRITE_REASON = (
    "this line mixes commands this hook approves with commands only you can judge, so "
    "the human ends up approving the whole line to get the one that matters. One write "
    "per Bash call, nothing else on the line: run on their own — approved: %s; run "
    "alone: %s.")
# The own-branch push is approved only as the whole command (own_push_alone_reason)
OWN_PUSH_ALONE_REWRITE_REASON = (
    "the own-branch push is approved only when it is the whole command. One write per Bash "
    "call, nothing else on the line: run the push alone (%s), and the rest in a call of "
    "its own.")

# ── A file authored through the shell ─────────────────────────────────────────
# Content written in the command itself landing in a file (self/features/
# shell-write-rewrite). CONVENTIONS.md → "Shell commands" (its last table row and the
# "Handed to the human" paragraph) says to author files with the Write and Edit tools,
# because a write made by a subprocess gets past the repo's Edit allow and deny rules;
# and there is a rewrite that always works, so by the membership test above it is a
# REWRITE and not an ASK. Three spellings, judged per member:
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
    "Shell commands). Use the Write tool for a new file or a whole rewrite, and the Edit "
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


def never_judged(text):
    """True when no deny or rewrite may judge the line — the guard every one of them
    keeps, for the two places the readers here would not read it as the shell does.

    A `#` outside quotes and unescaped is either a comment, whose text the shell never
    runs, or a mid-word literal the readers cannot place against a heredoc
    (`cat a#<<EOF`); either way a deny would be a guess. A `#` inside single or double
    quotes or behind a backslash is a literal to the shell and to every reader here, so
    `grep -n '^#' f` is judged like `grep -n '^x' f`. A line whose quotes never close
    counts when it holds a `#` at all, since where the quote was meant to end cannot be
    known.

    A `$'…'` that escapes a quote (`$'\\''`) is the other, `#` or no `#`. That is ANSI-C
    quoting: the backslash makes the quote a character, and every reader here — shlex
    among them — ends the quote at it instead. So `ls $'\\'' # '; cd x` had its comment
    read as quoted and a `cd` the shell never runs denied (review round 1,
    escalations/01), and `echo $'\\''` was told to close a quote that is closed. Any `$`
    before the quote counts: bash reads `$$'…'` as the PID and a plain quote, zsh as a
    `$` and an ANSI-C one, and a line the two read differently is not one to deny. A
    `$'…'` with no such escape ends where a plain quote does, and is read as one."""
    in_single = in_double = in_ansi = escaped = after_dollar = False
    for ch in text:
        literal = escaped
        if escaped:
            if in_ansi and ch == QUOTE_SINGLE:
                return True
            escaped = False
        elif in_ansi:
            if ch == ESCAPE:
                escaped = True
            elif ch == QUOTE_SINGLE:
                in_ansi = False
        elif ch == ESCAPE and not in_single:
            escaped = True
        elif ch == QUOTE_SINGLE and not in_double:
            if after_dollar:
                in_ansi = True
            else:
                in_single = not in_single
        elif ch == QUOTE_DOUBLE and not in_single:
            in_double = not in_double
        elif ch == COMMENT_CHAR and not (in_single or in_double):
            return True
        after_dollar = (ch == ANSI_C_QUOTE_PREFIX and not literal
                        and not (in_single or in_double or in_ansi))
    return (in_single or in_double or in_ansi) and COMMENT_CHAR in text


# A redirect's file descriptor: an ASCII digit run no bigger than a C int (bash reads a
# larger one as an ordinary word), or a `{name}` variable redirect (`{fd}>file`).
MAX_DESCRIPTOR = 2147483647
VARIABLE_DESCRIPTOR_RE = re.compile(r"\{[A-Za-z_][A-Za-z0-9_]*\}")
# What stands in for an operator character that is quoted or escaped while the line is
# lexed: private-use characters, which shlex reads as part of a word.
MASK_BASE = 0xE000
MASKED_PUNCTUATION = {ch: chr(MASK_BASE + i) for i, ch in enumerate(CHAIN_PUNCTUATION)}
UNMASKED_PUNCTUATION = {mask: ch for ch, mask in MASKED_PUNCTUATION.items()}
# The fail-closed rule (`fails_closed`): a line holding the word `case` or one of
# FAIL_CLOSED_MARKERS (below the operators), quoted or not, together with a git word is not
# read finely — it is never approved, and the deny side denies only
# what its one plain reading finds (self/features/orchestration-record-fixes/NOTES.md)
CASE_WORD_RE = re.compile(r"(?<![A-Za-z0-9_])case(?![A-Za-z0-9_])")
GIT_WORD_RE = re.compile(r"(?<![A-Za-z0-9_])git(?![A-Za-z0-9_])")
# Quote and backslash characters, deleted before looking for the git word (`g""it`, `g\it`)
GIT_WORD_DROPPED_CHARS = str.maketrans("", "", "\"'\\")
# Operators, longest first, as bash reads them left to right (`&&>x` is `&&` then `>`)
OPERATOR_KIND_REDIRECT, OPERATOR_KIND_SEPARATOR, OPERATOR_KIND_PAREN = (
    "redirect", "separator", "paren")
PROCESS_SUBSTITUTION_OPENERS = ("<(", ">(")
FAIL_CLOSED_MARKERS = (SUBSTITUTION_PREFIX + SUBSHELL_OPEN, BACKTICK, HEREDOC_OPERATOR) + \
    PROCESS_SUBSTITUTION_OPENERS
# The unreadable-ledger fail-closed rule (`unreadable_ledger_refuses`): with the role ledger
# unreadable, a raw command holding any of these — a substitution, a heredoc or herestring,
# ANSI-C or locale quoting, a `${…}` expansion — is refused outright rather than read for a
# build script (rounds 12-13 of orchestration-record-fixes; its NOTES.md)
UNREADABLE_LEDGER_MARKERS = FAIL_CLOSED_MARKERS + (
    SUBSTITUTION_PREFIX + QUOTE_SINGLE, SUBSTITUTION_PREFIX + QUOTE_DOUBLE,
    SUBSTITUTION_PREFIX + "{")
UNREADABLE_LEDGER_REASON = (
    "allow-repo-commands: this checkout's orchestrator role ledger cannot be read, so every "
    "session here is refused building, and a command holding a substitution, a heredoc or "
    "herestring, $'…' or $\"…\" quoting or a ${…} expansion is refused outright rather than "
    "read for one. Repair the checkout's .git or its orchestrator ledger, or run the command "
    "without the substitution or heredoc (literal words; the Write tool for a long message).")
PUNCTUATION_OPERATORS = (
    ("&>>", OPERATOR_KIND_REDIRECT), ("<<<", OPERATOR_KIND_REDIRECT),
    ("<(", OPERATOR_KIND_PAREN), (">(", OPERATOR_KIND_PAREN),
    ("&&", OPERATOR_KIND_SEPARATOR), ("||", OPERATOR_KIND_SEPARATOR),
    ("|&", OPERATOR_KIND_SEPARATOR), (";;", OPERATOR_KIND_SEPARATOR),
    ("&>", OPERATOR_KIND_REDIRECT), (">>", OPERATOR_KIND_REDIRECT),
    (">&", OPERATOR_KIND_REDIRECT), (">|", OPERATOR_KIND_REDIRECT),
    ("<<", OPERATOR_KIND_REDIRECT), ("<&", OPERATOR_KIND_REDIRECT),
    ("<>", OPERATOR_KIND_REDIRECT), (">", OPERATOR_KIND_REDIRECT),
    ("<", OPERATOR_KIND_REDIRECT), (";", OPERATOR_KIND_SEPARATOR),
    ("|", OPERATOR_KIND_SEPARATOR), ("&", OPERATOR_KIND_SEPARATOR),
    ("\n", OPERATOR_KIND_SEPARATOR), ("(", OPERATOR_KIND_PAREN),
    (")", OPERATOR_KIND_PAREN),
)


class QuotedWord(str):
    """A word made only of operator characters that was quoted or escaped in the line
    (`';'`, `"|"`, `\\;`): bash hands it to the program as an argument, never as a separator
    or a redirect (self/features/orchestration-record-fixes/NOTES.md, the audit's F1)."""


def is_operator_token(token):
    """True when `token`, from `chain_tokens`, is a run of operators the shell acts on."""
    return (bool(token) and not isinstance(token, QuotedWord)
            and all(ch in CHAIN_PUNCTUATION for ch in token))


def mask_quoted_punctuation(command):
    """`command` with every operator character that is inside quotes or behind a backslash
    swapped for a private-use stand-in of the same width, so the lexer cannot read it as an
    operator; `chain_tokens` swaps them back in the words it returns. An unbalanced quote
    leaves the rest of the line masked, and the lexer refuses it anyway. A substitution is no
    scope here: `"$(…)"` stays one quoted word, and a line holding one is the fail-closed
    rule's (`fails_closed`), never read finely."""
    out, quote, index = [], None, 0
    while index < len(command):
        ch = command[index]
        index += 1
        if quote == QUOTE_SINGLE:
            if ch == QUOTE_SINGLE:
                quote = None
                out.append(ch)
            else:
                out.append(MASKED_PUNCTUATION.get(ch, ch))
        elif ch == ESCAPE:
            out.append(ch)
            if index < len(command):
                out.append(MASKED_PUNCTUATION.get(command[index], command[index]))
                index += 1
        elif quote == QUOTE_DOUBLE:
            if ch == QUOTE_DOUBLE:
                quote = None
                out.append(ch)
            else:
                out.append(MASKED_PUNCTUATION.get(ch, ch))
        elif ch in (QUOTE_SINGLE, QUOTE_DOUBLE):
            quote = ch
            out.append(ch)
        else:
            out.append(ch)
    return "".join(out)


def is_heredoc_operator(token):
    """True when `token`, from `chain_tokens`, holds a heredoc's `<<` the shell acts on — never
    a quoted or escaped `'<<'`/`\\<\\<` (a `QuotedWord`) or a `<<<` herestring, which is a
    plain redirect (round 8's B1: either one switched every git deny on the line off)."""
    return is_operator_token(token) and (OPERATOR_KIND_REDIRECT, HEREDOC_OPERATOR) in \
        punctuation_pieces(token)


def heredoc_body_line(text, at, joins):
    """`(indexes, end)` for the body line that begins at `text[at]`: the index in `text` of
    each character bash reads on it, and of the line break that ends it (-1 at the end of the
    text). With `joins` (HEREDOC_JOIN_ODD), a line ending in an odd run of backslashes goes on
    in the next one, its last backslash and the break deleted, as bash reads an unquoted
    delimiter's body: `EO\\⏎F` is the line `EOF`, and `EO\\\\⏎F` (an escaped backslash) is
    two lines. With HEREDOC_JOIN_BACKTICK that one is joined as well, both backslashes
    deleted (BACKTICK_ESCAPE_CYCLE)."""
    indexes = []
    while True:
        end = text.find(LINE_BREAK_NEWLINE, at)
        stop = len(text) if end < 0 else end
        left = (stop - at - len(text[at:stop].rstrip(ESCAPE))) % joins if joins else 0
        dropped = left % len(ESCAPED_BACKSLASH) or left
        if end < 0 or not dropped:
            return indexes + list(range(at, stop)), end
        indexes.extend(range(at, stop - dropped))
        at = end + 1


def heredoc_body_span(text, start, delimiter, strip_tabs, run_on=None, in_backtick=False,
                      skip=0, ended=None, joins=HEREDOC_JOIN_NEVER):
    """`(terminator_start, resume)` for the heredoc whose body begins at `text[start]`, or None
    when the end cannot be placed exactly as bash places it — THE one place a heredoc body's
    extent is computed (the deny readers' `judged_text` and the whole-argument readers'
    `heredoc_argument_at` both ask it). A body ends only at a line holding the delimiter and
    nothing else (leading tabs stripped under `<<-`): `terminator_start` is that line's first
    character and `resume` the first character after it, where the command goes on. A RUN-ON
    line — one that begins with the delimiter and goes on, whatever follows it (`EOF)`, `EOF;`,
    `EOF )`, `EOFS)`, `EOF x)`) — is body text to the main parser, but is where bash 5.2 ends
    a `$(…)` heredoc and runs the rest of the line whenever a `)` follows on it; which
    characters may come between is not asked (round 1 asked, and `EOF )` hid a command:
    escalations/01-audit-opus.md, E1). With `in_backtick`, a line holding a backtick is one
    too: a backtick substitution's text, and its heredoc, end at the backtick. A run-on line,
    and a delimiter that is never found (bash runs to the end of the input), is not placed, so
    the caller reads the text as commands rather than hide them in a body (hook-audit-gaps,
    B1). A caller that knows more says how to read a run-on line with `run_on`:
    HEREDOC_RUN_ON_IS_BODY, the plain body line it is to the main parser and to an older
    bash's `$(…)`; HEREDOC_RUN_ON_ENDS, bash 5.2's `$(…)` reading — the body ends at a line
    that begins with the delimiter and `resume` is the character after the delimiter, so the
    rest of the line is read; or HEREDOC_RUN_ON_BACKTICK — it ends at a line's backtick, and
    `resume` is the backtick. Each of the last two takes the other's line for body, and the
    first `skip` lines of its own as well: bash ends the body at the first run-on line a `)`
    follows on, which need not be the first run-on line (`EOFS⏎EOF git push …)`). A body
    ended at a run-on line is noted in `ended`, so a caller trying each line in turn knows
    when none is left.

    With `joins` each line is read as bash reads an UNQUOTED delimiter's body: joined with the
    next where it ends in a line continuation (`heredoc_body_line`), before the tabs are
    stripped and before it is compared — `EO\\⏎F`, `E\\⏎O\\⏎F`, `EOF\\⏎` and an empty line,
    and `⇥EO\\⏎F` under `<<-` each end the body, and `x\\⏎EOF` does not
    (escalations/02-audit-opus.md, R2-1). The caller knows whether the delimiter was quoted,
    and says which runs of backslashes join (HEREDOC_JOIN_NEVER, _ODD, _BACKTICK)."""
    if not delimiter:
        return None
    at = start
    while at < len(text):
        indexes, end = heredoc_body_line(text, at, joins)
        line = "".join(text[i] for i in indexes)
        if strip_tabs:
            line = line.lstrip(HEREDOC_TAB)
        if line == delimiter:
            return at, (len(text) if end < 0 else end + 1)
        # where a run-on line may stop being body: after the delimiter, or at the backtick
        cuts = {HEREDOC_RUN_ON_ENDS: len(delimiter) if line.startswith(delimiter) else -1,
                HEREDOC_RUN_ON_BACKTICK: line.find(BACKTICK) if in_backtick else -1}
        if cuts.get(run_on, -1) >= 0:
            if not skip:
                if ended is not None:
                    ended.append(at)
                return at, indexes[len(indexes) - len(line) + cuts[run_on]]
            skip -= 1
        if end < 0 or (run_on is None and max(cuts.values()) >= 0):
            return None
        at = end + 1
    return None


def heredoc_delimiter(command, at, in_backtick=False):
    """`(delimiter, strip_tabs, end, quoted)` for the word after a `<<` that ended at
    `command[at]` (an attached `-` is `<<-`), read as bash reads a delimiter: quotes and
    backslashes removed, and `quoted` when it held any — bash then joins no line of the body.
    A line continuation is deleted wherever bash deletes one first: before the `-`, between
    the operator and the word, inside the word and inside its double quotes, and after it
    (`<<\\⏎EOF`, `<<E\\⏎OF`, `<<"E\\⏎OF"`, `<<'EOF'\\⏎`) — `in_backtick`, inside its single
    quotes too — and it quotes nothing. None when there is no word, a quote never closes, or
    the word holds what bash reads differently (HEREDOC_DELIMITER_UNREAD_RE)."""
    def joined(index):
        while True:
            if command.startswith(LINE_CONTINUATION, index):
                index += len(LINE_CONTINUATION)
            elif in_backtick and command.startswith(BACKTICK_CONTINUATION, index):
                index += len(BACKTICK_CONTINUATION)
            else:
                return index

    at = joined(at)
    strip_tabs = command.startswith(HEREDOC_STRIP_TABS_FLAG, at)
    index = joined(at + 1 if strip_tabs else at)
    while index < len(command) and command[index] in CHAIN_WHITESPACE:
        index = joined(index + 1)
    word, quoted = [], False
    while index < len(command):
        ch = command[index]
        if ch in (QUOTE_SINGLE, QUOTE_DOUBLE):
            close = command.find(ch, index + 1)
            if close < 0:
                return None
            piece = command[index + 1:close]
            word.append(piece if ch == QUOTE_SINGLE and not in_backtick
                        else piece.replace(LINE_CONTINUATION, ""))
            index, quoted = joined(close + 1), True
        elif ch == ESCAPE:
            word.append(command[index + 1:index + 2])
            index, quoted = joined(index + 2), True
        elif ch in CHAIN_WHITESPACE or ch in CHAIN_PUNCTUATION:
            break
        else:
            word.append(ch)
            index = joined(index + 1)
    delimiter = "".join(word)
    if not delimiter or HEREDOC_DELIMITER_UNREAD_RE.search(
            command[at:index + 1].replace(LINE_CONTINUATION, "")):
        return None
    return delimiter, strip_tabs, index, quoted


def comment_and_heredoc_free(command, keep_bodies=False, run_on=None, flips=(), doubts=None,
                             drop_pid=False, skip=0, ended=None, joins=HEREDOC_JOINS_PARSER,
                             open_heads=False):
    """The line as bash reads it with its non-commands removed — each unquoted comment (a `#`
    that starts a word, through the end of its line) and each heredoc's body and terminator
    line, the operator and its delimiter word kept — or None when a body cannot be placed:
    `heredoc_body_span` finds no end; `heredoc_delimiter` does not read the delimiter; the
    `<<` may be a shift (HEREDOC_SHIFT_RE, or inside `${…}`); or a substitution opens between
    the operator and the end of its line, which bash may read through before any body (`cat
    <<EOF $(echo a⏎cmd⏎EOF⏎)` runs cmd). With `keep_bodies` no heredoc is looked for: only
    comments go, and the bodies stay to be read as commands. One walk, because the two are
    tangled: an apostrophe in a comment must not open a quote, and a body is not scanned for
    quotes or comments at all.

    A heredoc with no substitution opener (`$(`, `<(`, `>(`, a backtick) anywhere before its
    operator is the main parser's, and ends only at its terminator line (`EOF)` is body).
    After one, a run-on body line is read as `run_on` and `skip` say (`heredoc_body_span`,
    which is told when a backtick came before the operator, and notes in `ended` a body it
    ends at such a line): unplaced by default, and `judged_texts` asks for every reading.

    A line continuation (`\\⏎`, outside single and ANSI-C quotes) is deleted, as bash deletes
    it, so the characters around it are neighbours: `git pu\\⏎sh` is a push, `a \\⏎#b` holds a
    comment and `a\\⏎#b` none. Inside a comment bash deletes none, and neither does this walk,
    which has left the comment behind by then: the line after `ls # x \\⏎` is a command.
    It is deleted from the line itself, BEFORE the walk tests what it is looking at, so no
    test here reads a construct bash has already joined as two pieces (round 3,
    escalations/02-audit-opus.md, R2-2): an operator (`<\\⏎<EOF`, `<<\\⏎<`), a delimiter
    (`heredoc_delimiter`), a substitution opener (`<\\⏎(`, `$\\⏎(`), an arithmetic opener or
    a subscript before a `<<` (`(\\⏎(`, `$\\⏎[`, `a[1\\⏎<<2]`), `$\\⏎{`, `$\\⏎'`, and a
    whole-argument heredoc's head and tail (`"$\\⏎(cat <<'EOF'⏎`). Inside backticks one is
    deleted inside single and ANSI-C quotes too — bash deletes it from a backtick
    substitution's text before it reads the quotes there — and so is the `\\\\⏎` bash halves
    to one for the substitution's own parser (BACKTICK_ESCAPE_CYCLE). A body's own
    continuations are `heredoc_body_span`'s: joined where the delimiter is unquoted, and as
    `joins` says (HEREDOC_JOINS_PARSER) — `judged_texts` asks for each reading.

    A `#` may be a comment where bash may start one: after an UNESCAPED blank or operator
    (`a\\ #b` is one word), outside `${…}`, and inside backticks only as far as the closing
    backtick. It is dropped for certain only when none of COMMENT_DOUBT_OPENERS is in the
    text kept before it. Past one it is IN DOUBT: this walk drops it too, appends its index
    to `doubts`, and keeps the Nth one as text when `flips[N]` is true — `judged_texts` asks
    for every combination, so the deny side never rests on the guess.

    A whole-argument `"$(cat <<'EOF' … )"` (`heredoc_argument_at`) — a quoted
    delimiter, so its body is text, and nothing substituted before it, so the quote state
    here is bash's — is one word whatever quotes its body holds, and stands as `""`. `$'…'`
    is walked as the ANSI-C quote it is, its `\\'` no end (the lexer does not read that, and
    `never_judged` holds such a line back) — after an ODD run of `$` only: `$$` is the PID, so
    `$$'a\\'` is a plain quote and `$${x` opens no expansion. With `drop_pid` that PID is left
    out of the text returned, so no later reader takes its quote for an ANSI-C one: the git
    deny's reading (`judged_texts`), since bash runs what follows such a quote; the
    chained-`cd` deny does not ask for it, and keeps leaving a line zsh reads differently
    alone. A line whose quotes never close is returned as it came, and a last backslash that
    escapes nothing is dropped. Nothing else here follows a substitution's scope, as
    `mask_quoted_punctuation` does not: any other `"$(…)"` is one quoted word.

    A whole-argument head that is NOT stood in — an unquoted delimiter, a `)"` that does not
    follow the terminator, a substitution before it — is one quoted word too, whatever bash
    runs after its body (`echo "$(cat <<EOF⏎EOF⏎cmd⏎)"` runs cmd). With `open_heads` it is
    read as the substitution it is instead: its `"` and the next `"` are dropped, so its
    heredoc is placed like any other and what follows the body is read as commands.
    `judged_texts` asks for both (escalations/02-review-opus.md, the third reproduction)."""
    out, pending, index, written = [], [], 0, command
    in_single = in_double = in_ansi = in_backtick = escaped = literal = opened = False
    expansion_depth = dollars = 0
    doubts = [] if doubts is None else doubts
    operator_end = 0    # where the first pending heredoc's operator and delimiter end

    def substituted(start, end):
        # A substitution opener in command[start:end], quoted or not. Whether it has closed
        # again is not asked: a `case` pattern's `)` and a quote nested in `"$(…)"` would each
        # fool a count, and reading too much as "inside" only reads more text as commands.
        return any(marker in command[start:end] for marker in FAIL_CLOSED_MARKERS
                   if marker != HEREDOC_OPERATOR)

    def kept():
        # The text kept so far: what a `#` is judged against, since a deleted continuation, a
        # dropped comment and a placed body are not its neighbours
        return "".join(out)

    def join(at):
        # Delete the line continuations at command[at:], where the caller knows bash deletes
        # them: what follows is then the neighbour of what came before, for every test here.
        # One is the last backslash of an odd run and the line break after it; inside
        # backticks, outside the quotes there, also the last TWO of a run bash halves to one
        # (BACKTICK_ESCAPE_CYCLE), seen from the run's start
        nonlocal command
        while True:
            start = end = at
            while command.startswith(ESCAPE, end):
                end += 1
            while command.startswith(ESCAPE, start - 1, start):
                start -= 1
            if end == at or not command.startswith(LINE_BREAK_NEWLINE, end):
                return
            if end - at == len(ESCAPE) and (end - start) % len(ESCAPED_BACKSLASH):
                cut = len(ESCAPE)
            elif in_backtick and not (in_single or in_ansi) and at == start and \
                    (end - start) % BACKTICK_ESCAPE_CYCLE == len(ESCAPED_BACKSLASH):
                cut = len(ESCAPED_BACKSLASH)
            else:
                return
            command = command[:end - cut] + command[end + 1:]

    def join_head(at):
        # ... through the head of a whole-argument heredoc, `"$(cat <<-'EOF'⏎`, whose `"` is
        # at command[at - 1]: between its characters, inside a double-quoted delimiter and
        # after the delimiter — never inside a single-quoted one, where bash deletes none
        for expected in HEREDOC_ARGUMENT_START[1:]:
            join(at)
            if not command.startswith(expected, at):
                return
            at += 1
        join(at)
        while command[at:at + 1] and command[at] in HEREDOC_ARGUMENT_FILL:
            at += 1
            join(at)
        quote = command[at:at + 1]
        if quote == QUOTE_SINGLE:
            at = command.find(quote, at + 1)
        else:
            if quote == QUOTE_DOUBLE:
                at += 1
                join(at)
            while HEREDOC_WORD_CHAR_RE.match(command, at):
                at += 1
                join(at)
        if at > 0 and quote in (QUOTE_SINGLE, QUOTE_DOUBLE) and command.startswith(quote, at):
            join(at + 1)

    while index < len(command):
        if not escaped and (in_backtick or not (in_single or in_ansi)):
            # a line continuation, deleted as bash deletes it — here, where the walk has left
            # every comment it reads behind — and deleted from an operator the walk is about
            # to look ahead for (`<\⏎<`, `<<\⏎<`), which bash reads joined
            join(index)
            if command.startswith(REDIRECT_CHARS_IN, index):
                join(index + len(REDIRECT_CHARS_IN))
                if command.startswith(HEREDOC_OPERATOR, index):
                    join(index + len(HEREDOC_OPERATOR))
            if index == len(command):
                break
        ch = command[index]
        # whether the character before this one was escaped, and whether this one is
        after_literal, literal = literal, escaped
        # the run of unescaped `$` that ends right before this character: an odd one leaves a
        # `$` for the quote or brace after it, an even one is PIDs (`$$`) and leaves none
        after_dollars = dollars
        dollars = dollars + 1 if ch == SUBSTITUTION_PREFIX and not escaped else 0
        if escaped:
            escaped = False
        elif in_single:
            in_single = ch != QUOTE_SINGLE
        elif ch == ESCAPE:
            escaped = True
        elif in_ansi:
            in_ansi = ch != QUOTE_SINGLE
        elif in_double:
            in_double = ch != QUOTE_DOUBLE
        elif ch == QUOTE_SINGLE:
            # `$'…'` is ANSI-C quoting: a backslash escapes in it, the quote included
            in_ansi = after_dollars % len(PID_PARAMETER) == 1
            in_single = not in_ansi
            if in_single and after_dollars and drop_pid:
                del out[-after_dollars:]    # `$$'…'`: the PID goes, the plain quote stays
        elif ch == QUOTE_DOUBLE:
            join_head(index + 1)
            head = HEREDOC_ARGUMENT_HEAD_RE.match(command, index)
            found = head and head.group(2) and not substituted(0, index) and \
                heredoc_argument_at(command, index, run_on=run_on, skip=skip, ended=ended)
            if found:
                out.append(HEREDOC_ARGUMENT_STAND_IN)
                index = found[1]
                continue
            if opened or (head and open_heads):
                # the `"` of a head this reading opens, or the next `"` after one — taken
                # for the one that closes it: neither is kept, and what lies between is
                # read as the substitution it is, its heredoc placed like any other
                opened = not opened
                index += 1
                continue
            in_double = True
        elif ch == BACKTICK:
            in_backtick = not in_backtick
        elif ch == BRACE_OPEN and after_dollars % len(PID_PARAMETER) == 1:
            # only a `${` nests: `${x:-{}` ends at its first `}` (escalations/01-review-opus.md)
            expansion_depth += 1
        elif ch == BRACE_CLOSE and expansion_depth:
            expansion_depth -= 1
        elif ch == COMMENT_CHAR and not expansion_depth and not after_literal and (
                not kept() or kept()[-1] in COMMENT_PREDECESSORS
                or (in_backtick and kept()[-1] == BACKTICK)):
            flipped = False
            if COMMENT_DOUBT_OPENERS.intersection(kept()):
                doubts.append(index)
                flipped = any(flips[len(doubts) - 1:len(doubts)])
            if not flipped:
                ends = [command.find(end, index) for end in
                        ((LINE_BREAK_NEWLINE, BACKTICK) if in_backtick else (LINE_BREAK_NEWLINE,))]
                index = min([end for end in ends if end >= 0] or [len(command)])
                continue
        elif (not keep_bodies and command.startswith(HEREDOC_OPERATOR, index)
              and not command.startswith(HERESTRING_OPERATOR, index)
              and not command.startswith(HERESTRING_OPERATOR, max(index - 1, 0))):
            if expansion_depth or HEREDOC_SHIFT_RE.search(command, 0, index):
                return None
            parsed = heredoc_delimiter(command, index + len(HEREDOC_OPERATOR), in_backtick)
            if parsed is None:
                return None
            delimiter, strip_tabs, end, quoted = parsed
            operator_end = operator_end if pending else end
            ticked = BACKTICK in command[:index]
            pending.append((delimiter, strip_tabs,
                            run_on if substituted(0, index) else HEREDOC_RUN_ON_IS_BODY, ticked,
                            # which of the body's lines are joined at their continuations
                            HEREDOC_JOIN_NEVER if joins == HEREDOC_JOINS_AS_WRITTEN else
                            (HEREDOC_JOIN_ODD, HEREDOC_JOIN_BACKTICK)[not quoted]
                            if ticked and joins == HEREDOC_JOINS_BACKTICK else
                            (HEREDOC_JOIN_ODD, HEREDOC_JOIN_NEVER)[quoted]))
            word = command[index:end]   # kept as bash reads it, its continuations deleted
            for continuation in ((BACKTICK_CONTINUATION,) if in_backtick else ()) + (LINE_CONTINUATION,):
                word = word.replace(continuation, "")
            out.append(word)
            index = end
            continue
        elif ch == LINE_BREAK_NEWLINE and pending:
            if substituted(operator_end, index):
                return None
            out.append(ch)
            index += 1
            for delimiter, strip_tabs, mode, ticked, body_joins in pending:
                span = heredoc_body_span(command, index, delimiter, strip_tabs, mode, ticked,
                                         skip, ended, body_joins)
                if span is None:
                    return None
                index = span[1]
            pending = []
            continue
        out.append(ch)
        index += 1
    if in_single or in_double or in_ansi:
        # ... as a TornReading when this walk had built a reading of it by then
        return TornReading(written) if "".join(out) != written else written
    if escaped:
        out.pop()   # the line's last character, a backslash that escapes nothing: bash runs
        #             the command without it, and the lexer refuses the whole line with it
    return "".join(out)


class TornReading(str):
    """The line as it came, from a `comment_and_heredoc_free` that BUILT a reading of it — a
    comment dropped, a body placed, a whole-argument heredoc stood in or opened, a line
    continuation deleted — and then found that reading's quotes never close. To every reader
    it is the line it equals; `judged_texts` alone asks which kind it was handed, because the
    reading is one bash may make and no reader can lex: bash had run everything before the
    open quote by the time it met it (escalations/03-audit-opus.md, R3-1)."""


def torn_reading(text, reread):
    """True when `text`, a reading `comment_and_heredoc_free` made, is a built reading that
    does not tokenize — THE one test of it, asked of every reading `judged_texts` takes, so
    that none is dropped quietly: the line is then denied (`judged_texts` for a line that
    names git, `does_not_tokenize` for any other). `reread()` is the same reading with its
    `$$` kept: a line whose only change is a dropped PID was not built, and stays the line
    `never_judged` holds back (`grep $$'\\'#' f`, which bash and zsh read differently)."""
    return isinstance(text, TornReading) and isinstance(reread(), TornReading)


# Ruling 45's opened head as bash reads it (escalations/03-audit-opus.md, R3-2): blanks and
# line breaks after the `$(`, blanks between `cat` and the `<<`, and a line continuation
# between any two of its characters. `judged_texts` respells each one HEREDOC_ARGUMENT_START
# for the opened reading, so `"$( cat <<EOF` is opened as `"$(cat <<EOF` is. Text before the
# `$(` (`"x$(cat <<EOF`) is not this head: any other `"$(…)"` stays the one word it was.
CONTINUATIONS_PATTERN = r"(?:\\\n)*"
HEREDOC_OPENED_HEAD_RE = re.compile(CONTINUATIONS_PATTERN.join(
    ("\"", r"\$", r"\((?:[ \t\n]|\\\n)*c", "a", r"t(?:[ \t]|\\\n)*<", "<")))


def judged_texts(command, torn=None):
    """The texts the deny side's readers lex: every reading bash may make of the line, each a
    `comment_and_heredoc_free`, and a deny is owed when any of them holds one. One, when every
    body is placed and no comment is in doubt. Inside a substitution a run-on body line is
    read each way — not placed, as body text (an older bash), and as the end of the body
    (bash 5.2), at the first such line and at each later one in turn — and each comment in
    doubt is read both ways, in every combination: dropped first, then each one kept. When
    no reading places a body, the line with only its comments removed: its body lines read as
    commands (a deny may then fire on text bash would have taken for a body, which is the
    cost of never hiding one). A line with more comments in doubt than MAX_COMMENT_DOUBTS, or
    more run-on lines in a body than MAX_RUN_ON_LINES, is not read: when it names git it is
    judged as a git command that cannot be read (GIT_UNREADABLE_ARGS), and otherwise
    OverflowError is raised — a run to the build-script judge, no deny to the others.

    A line that holds a heredoc and a line continuation is read with each reading of a body's
    own continuations as well (HEREDOC_JOINS_PARSER first: bash's), and one that holds a
    whole-argument heredoc's head (`"$(cat <<`, in any spelling of HEREDOC_OPENED_HEAD_RE)
    with that head opened as well as closed (`open_heads`): every combination, the walk's own
    first. The operator, the head and the git word are looked for with every continuation
    deleted, which only ever finds more.

    A built reading that does not tokenize (`torn_reading`) is never dropped quietly: it is
    noted in `torn`, and a line with one that names git is judged as a git command that
    cannot be read, like a line past a cap. Any other keeps its texts — the readers here
    cannot lex that one — and takes the tokenize deny (`does_not_tokenize`). Two readings
    are left out, each a guess the walk makes beside bash's own reading rather than a
    placement: a comment in doubt kept as text (the reading that drops it is asked), and the
    bodies read as commands when none could be placed."""
    texts = []
    torn = [] if torn is None else torn
    joined = command.replace(LINE_CONTINUATION, "")
    join_modes = (HEREDOC_JOINS_PARSER,) + (
        (HEREDOC_JOINS_BACKTICK, HEREDOC_JOINS_AS_WRITTEN)
        if joined != command and HEREDOC_OPERATOR in joined else ())
    # the line each reading walks: as written, and with every opened head respelled
    lines = ((command, False),) + (
        ((HEREDOC_OPENED_HEAD_RE.sub(HEREDOC_ARGUMENT_START, command), True),)
        if HEREDOC_OPENED_HEAD_RE.search(command) else ())
    readings = [(line, dict(joins=joins, open_heads=open_heads))
                for line, open_heads in lines for joins in join_modes]

    def unread():
        # What a line that cannot be read is judged as: a git command that cannot be read
        # when it names git, and None when there is no git to refuse
        if GIT_WORD_RE.search(joined.translate(GIT_WORD_DROPPED_CHARS)):
            return [" ".join((GIT_PROGRAM,) + GIT_UNREADABLE_ARGS)]
        return None

    def read(built=True, **how):
        # every reading of the comments in doubt: the walk's own first, then each one flipped
        todo = [(reading, ()) for reading in reversed(readings)]
        while todo:
            ((line, reading), flips), doubts = todo.pop(), []
            how_read = dict(reading, flips=flips, **how)
            text = comment_and_heredoc_free(line, doubts=doubts, drop_pid=True, **how_read)
            if len(doubts) > MAX_COMMENT_DOUBTS:
                raise OverflowError(command)
            # ... and a reading that holds a whole-argument head nothing here reads is noted
            # with them, whichever reading it is (`unread_head`)
            if unread_head(text or "") or built and not any(flips) and torn_reading(
                    text, lambda: comment_and_heredoc_free(line, **how_read)):
                torn.append(text)
            if text is not None and text not in texts:
                texts.append(text)
            todo.extend(((line, reading), flips + (False,) * (at - len(flips)) + (True,))
                        for at in range(len(flips), len(doubts)))

    try:
        read()
        if HEREDOC_OPERATOR in joined:
            read(run_on=HEREDOC_RUN_ON_IS_BODY)
            for run_on in (HEREDOC_RUN_ON_ENDS, HEREDOC_RUN_ON_BACKTICK):
                # ... ending at the first run-on line, then at the second, until a reading
                # finds none left to end at
                skip, ended = 0, [None]
                while ended:
                    if skip > MAX_RUN_ON_LINES:
                        raise OverflowError(command)
                    ended = []
                    read(run_on=run_on, skip=skip, ended=ended)
                    skip += 1
        if not texts:
            read(built=False, keep_bodies=True)
    except OverflowError:
        if unread() is None:
            raise       # no git to refuse: the build-script judge takes a reading that fails
            #             for a run (`build_script_denial`), and the other denies let it be
        return unread()
    # A line NO reading of which is judged — none tokenizes, or `never_judged` holds each one
    # back for its ANSI-C quote, as `command_words` does — AND whose syntax bash itself
    # refuses (`bash_refuses`) is judged the same way, built or not and whatever `<<` or `#`
    # it holds: bash ran every complete line before the one it could not parse (`git push -f
    # origin y⏎echo '#`, `git push -f origin y⏎echo $'\'' "`, a PR body whose terminator was
    # dropped — escalations/05-audit-opus.md and 06-audit-opus.md, B1). A line bash parses
    # keeps the verdict its texts get: shlex refuses `$'it\'s'` and `"$(echo "it's")"`, and
    # bash reads both (escalations/06-review-opus.md). Bash is asked last, and only about a
    # line that names git and that nothing here judges; its answer can only add this deny.
    unjudged = all(never_judged(text.replace(COMMENT_CHAR, "")) or chain_tokens(text) is None
                   for text in texts)
    return (torn or unjudged and unread() and bash_refuses(command)) and unread() or texts


# `bash_refuses` asks bash whether a line parses. `bash -n` reads commands and executes none:
# no substitution, redirection, heredoc body, alias or `set +n` in the text runs (each tried
# on bash 5.2: self/features/hook-audit-gaps/NOTES.md, round 7). The text goes in on stdin,
# never as an argument or as a file it names, and stdin closes after it; no startup file is
# read; the environment is BASH_SYNTAX_ENV alone, so no BASH_ENV, ENV, SHELLOPTS or exported
# function reaches bash; and the PATH that finds bash is the system's directories, never the
# session's.
BASH_SYNTAX_ARGV = ("bash", "--norc", "--noprofile", "-n")
BASH_SYNTAX_ENV = {"PATH": "/usr/bin:/bin"}
BASH_SYNTAX_TIMEOUT_SECONDS = 5
# A NUL cannot reach a shell inside an argument, and bash drops one it reads from stdin
BASH_UNREADABLE_CHAR = "\0"
# One hook call reads `judged_texts` many times: bash is asked once per line
BASH_REFUSALS = {}


def bash_refuses(command):
    """True unless bash parses `command` cleanly: `bash -n` over it exits 0 and prints nothing.

    Fails closed: no bash on BASH_SYNTAX_ENV's PATH, a timeout, a NUL or a character that
    does not encode, a non-zero exit, and any output at all count as refused — a heredoc
    that runs to the end of the line exits 0 with a warning, and bash ran what came before
    it. The answer only ever ADDS the unreadable-git deny to a line no reading here judges
    (`judged_texts`); it approves nothing and switches no other deny off.

    The bash asked is the system's, with no options set — not the shell the session runs,
    which may be another version, or zsh, with aliases and `shopt`s of its own (`git add
    !(x)` parses there under extglob and not here, whatever `shopt -s` the line itself
    holds: nothing is executed). What this bash wrongly refuses is one more deny on a line
    nothing here could read; what it wrongly accepts keeps the verdict it had unasked."""
    if command not in BASH_REFUSALS:
        try:
            done = subprocess.run(BASH_SYNTAX_ARGV, input=command.encode(), env=BASH_SYNTAX_ENV,
                                  capture_output=True, timeout=BASH_SYNTAX_TIMEOUT_SECONDS)
            BASH_REFUSALS[command] = bool(BASH_UNREADABLE_CHAR in command or done.returncode
                                          or done.stdout or done.stderr)
        except (OSError, subprocess.SubprocessError, ValueError):
            BASH_REFUSALS[command] = True
    return BASH_REFUSALS[command]


# What follows a whole-argument head's `<<`, taken crudely: the `-` and blanks, then everything
# up to the next blank or operator character. Not bash's delimiter word — a quoted blank or
# operator cuts it short — and it need not be: `unread_head` asks only whether it is the plain
# word HEREDOC_ARGUMENT_HEAD_RE reads.
HEREDOC_HEAD_WORD_RE = re.compile("[%s]*[^%s]*" % (
    re.escape(HEREDOC_ARGUMENT_FILL), re.escape(CHAIN_PUNCTUATION + CHAIN_WHITESPACE)))


def unread_head(text):
    """True when `text` holds a whole-argument heredoc's head (`"$(cat <<`, in any spelling of
    HEREDOC_OPENED_HEAD_RE) whose delimiter is NOT the bare or fully quoted identifier
    HEREDOC_ARGUMENT_HEAD_RE reads: partly quoted (`E'O'F`, `E"O"F`, `''EOF`), backslash-quoted
    (`\\EOF`, `E\\OF`), empty (`''`, `""`) or no identifier (`E-F`, `123`, `'E O F'`, `'E)F'`).
    Bash reads each as a delimiter; no reading here stands such a head in or opens it, so the
    line was one quoted word whatever bash ran after the body (escalations/04-audit-opus.md,
    R4-1). It is not read for a message at all: `judged_texts` notes the reading as torn, which
    is the git deny for a line that names git and the tokenize deny for any other. The
    delimiter word is not parsed — a commit message never spells one that way. A herestring
    (`"$(cat <<<x)"`) is no head."""
    return any(
        not text.startswith(REDIRECT_CHARS_IN, head.end()) and not HEREDOC_ARGUMENT_HEAD_RE.match(
            HEREDOC_ARGUMENT_START + HEREDOC_HEAD_WORD_RE.match(text, head.end()).group()
            + LINE_BREAK_NEWLINE)
        for head in HEREDOC_OPENED_HEAD_RE.finditer(text))


def tears_a_reading(command):
    """True when a reading bash may make of the line is built and does not tokenize, or holds
    a whole-argument head nothing here reads (`judged_texts`' `torn`). A line past a cap is
    not read, and is not this."""
    torn = []
    try:
        judged_texts(command, torn)
    except OverflowError:
        pass
    return bool(torn)


def judged_text(command):
    """The first of `judged_texts`, for a caller that reads one text."""
    return judged_texts(command)[0]


def heredoc_argument_at(text, at, strict=False, run_on=None, skip=0, ended=None):
    """`(body, end)` for the whole-argument heredoc substitution `"$(cat <<'EOF'⏎…⏎EOF⏎)"`
    spelled at `text[at]` — `end` is the index after its closing `)"` — or None. The body ends
    at `heredoc_body_span`'s terminator line and the `)"` must follow it, so the audit's
    `EOF)" ; cmd ; echo "⏎EOF⏎)"` is not one (hook-audit-gaps, B1) — unless the caller asks
    for one of the readings of that run-on line (`run_on`, `skip` and `ended`, as
    `heredoc_body_span` takes them). `strict` is the orchestrator's reading: a quoted
    delimiter, no `<<-`, no body line that begins with the delimiter and goes on, and the `)"`
    on the very next line. An unquoted delimiter's body is joined at its line continuations
    before its end is looked for, as bash joins it."""
    head = HEREDOC_ARGUMENT_HEAD_RE.match(text, at)
    if not head or (strict and (head.group(1) or not head.group(2))):
        return None
    span = heredoc_body_span(text, head.end(), head.group(3), bool(head.group(1)), run_on,
                             skip=skip, ended=ended,
                             joins=HEREDOC_JOIN_NEVER if head.group(2) else HEREDOC_JOIN_ODD)
    if span is None:
        return None
    terminator_start, resume = span
    if strict:
        if not text.startswith(HEREDOC_ARGUMENT_STRICT_TAIL, resume):
            return None
        tail_end = resume + len(HEREDOC_ARGUMENT_STRICT_TAIL)
    else:
        tail = HEREDOC_ARGUMENT_TAIL_RE.match(text, resume)
        if not tail:
            return None
        tail_end = tail.end()
    return text[head.end():max(head.end(), terminator_start - 1)], tail_end


def replace_heredoc_arguments(command, replace):
    """`command` with each whole-argument heredoc substitution (`heredoc_argument_at`) replaced
    by `replace(body)`."""
    out, at = [], 0
    while True:
        start = command.find(HEREDOC_ARGUMENT_START, at)
        if start < 0:
            break
        found = heredoc_argument_at(command, start)
        if found is None:
            out.append(command[at:start + 1])
            at = start + 1
            continue
        out.append(command[at:start])
        out.append(replace(found[0]))
        at = found[1]
    out.append(command[at:])
    return "".join(out)


def judged_tokens(text):
    """`chain_tokens` for the deny side's readers, over one of `judged_texts`: comments and
    heredoc bodies left out, everything else read — the heredoc's own line (`git push origin
    main <<EOF`, `cat <<EOF; git push …`) and every command AFTER its body (`cat <<EOF⏎x⏎EOF⏎git
    push origin main`), so a heredoc never switches a deny off; the fail-closed rule keeps the
    line from approval. When no body could be placed the text holds them, read as commands;
    when that does not lex (a body holding an apostrophe), its first line is read if it holds
    the heredoc. None when nothing can be read."""
    tokens = chain_tokens(text)
    if tokens is None and LINE_BREAK_NEWLINE in text:
        tokens = chain_tokens(text.split(LINE_BREAK_NEWLINE, 1)[0])
        if tokens is None or not any(is_heredoc_operator(t) for t in tokens):
            return None
    return tokens


def punctuation_pieces(run):
    """`run`, a token of operator characters, as `[(kind, operator)]` read the way bash
    does, left to right and longest first: `;>x`'s `;>` is a separator and a redirect, and
    only the redirect takes the word after it as its target (the audit's F2)."""
    pieces, index = [], 0
    while index < len(run):
        for operator, kind in PUNCTUATION_OPERATORS:
            if run.startswith(operator, index):
                pieces.append((kind, operator))
                index += len(operator)
                break
        else:
            # A character of CHAIN_PUNCTUATION with no operator of its own — read as a
            # separator rather than spin here forever (self/tests/hook-cloud-profile.sh
            # asserts every character has a one-character operator)
            pieces.append((OPERATOR_KIND_SEPARATOR, run[index]))
            index += 1
    return pieces


def is_bare_descriptor(command, start, token):
    """True when `token` is spelled in `command` at `start` exactly, as a whole unquoted
    word: preceded by the line start, whitespace or an operator, never a quote or a
    backslash. Only that is a redirect's file descriptor — bash reads `'2'>x`, `\\2>x` and
    `x2>y` as an argument, so dropping the digit would shift every word after it (`git -C
    '1'>/dev/null push origin main` read as `-C push`), and so is a digit run past a C int
    (`99999999999>x`) — self/features/orchestration-record-fixes/NOTES.md, the audit's
    bypass 2 and F5. A `{name}` is a descriptor too (`{fd}>x`, F4)."""
    if start < 0 or command[start:start + len(token)] != token:
        return False
    if token.isascii() and token.isdigit():
        if int(token) > MAX_DESCRIPTOR:
            return False
    elif not VARIABLE_DESCRIPTOR_RE.fullmatch(token):
        return False
    return start == 0 or command[start - 1] in CHAIN_WHITESPACE or command[start - 1] in CHAIN_PUNCTUATION


def chain_tokens(command):
    """The line as the deny side's readers lex it — words, and runs of CHAIN_PUNCTUATION
    as their own tokens — or None when it does not tokenize.

    A redirect's file descriptor is the operator's, never a word of the command: in
    `git push origin feat 2>&1`, bash hands git `push origin feat`, and the `2` is part of
    `2>&1`. shlex splits it off as a word of its own, so it is dropped here — a word of
    digits that the lexer ended on the `<` or `>` right after it, with no space between
    (`2 >&1` keeps its `2`, as bash does). Kept, the `2` read as a refspec, and in a cloud
    container `git push -u origin <current branch> 2>&1 | tail -3` was refused as a push of
    a second branch named `2` (self/features/ablation-harness-fixes/)."""
    # Quoted and escaped operator characters are masked first: shlex drops the quoting, so
    # a quoted `';'` would otherwise come back as a separator and `'>'` as a redirect.
    masked = mask_quoted_punctuation(command)
    lexer = shlex.shlex(masked, posix=True, punctuation_chars=CHAIN_PUNCTUATION)
    lexer.whitespace = CHAIN_WHITESPACE
    lexer.whitespace_split = True
    lexer.commenters = SHLEX_NO_COMMENTERS
    tokens = []
    try:
        while True:
            token = lexer.get_token()
            if token == lexer.eof:
                break
            # shlex ends a word by READING the character after it — pushed back when it is
            # punctuation — so the stream's position is one past the character that ended it.
            ended_on = lexer.instream.tell() - 1
            if (0 <= ended_on < len(masked) and masked[ended_on] in REDIRECT_CHARS
                    and is_bare_descriptor(masked, ended_on - len(token), token)):
                continue
            word = token.translate(str.maketrans(UNMASKED_PUNCTUATION))
            if word != token and all(ch in CHAIN_PUNCTUATION for ch in word):
                word = QuotedWord(word)
            tokens.append(word)
    except ValueError:
        return None
    return tokens


def chains_chdir(command):
    """True when a cd or pushd shares the command with any other command. What it cannot
    tokenize, a heredoc whose body cannot be placed (`heredoc_body_span`), and anything
    `never_judged` holds back (a `#` inside a word, a `$'…'` escaping a quote) is never judged
    a chain: a deny must not fire on a guess. Comments and heredoc bodies are not read, and
    what follows a body is (`ls;<<EOF cat⏎x⏎EOF⏎cd /tmp && ls`)."""
    text = comment_and_heredoc_free(command)
    if text is None or never_judged(text):
        return False
    tokens = chain_tokens(text)
    if tokens is None:
        return False
    # A `$(…)` substitution is its own scope: a cd inside it moves no path the outer
    # command resolves (`x=$(cd dir && pwd)` is how a path is made absolute), so nothing
    # in it is a head, and the word after it is back where the `$(` left off. A plain
    # `(…)` subshell is not: its cd moves the commands beside it.
    heads, at_head, redirect_target, prev_word = [], True, False, ""
    open_parens = []  # (is_substitution, at_head when it opened), innermost last
    for t in tokens:
        if is_operator_token(t):
            for i, (kind, operator) in enumerate(punctuation_pieces(t)):
                if kind == OPERATOR_KIND_REDIRECT:
                    redirect_target = True
                elif kind == OPERATOR_KIND_SEPARATOR:
                    redirect_target = False
                    at_head = True
                elif operator in PROCESS_SUBSTITUTION_OPENERS:
                    # `<(…)` / `>(…)`: a word of the command, with a scope of its own
                    open_parens.append((True, at_head))
                    redirect_target = False
                    at_head = True
                elif operator == SUBSHELL_OPEN:
                    is_substitution = i == 0 and prev_word.endswith(SUBSTITUTION_PREFIX)
                    open_parens.append((is_substitution, at_head))
                    at_head = True
                elif open_parens:
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
    the line cannot be judged: text that does not tokenize, or one `never_judged` holds
    back — `chains_chdir`'s guards, for the same reason: a deny must not fire on a guess. A
    comment and a heredoc's body are not read (`judged_text`); its own line and everything
    after the body are. An unbalanced quote inside a comment therefore hides nothing
    (hook-audit-gaps, A: `git push origin main # '`).

    One plain reading: every operator ends a command, a paren included, and a quoted word —
    `"$(…)"` among them — is one word. It does not follow shell grammar into substitutions,
    `case` arms or heredoc bodies, and it does not try to: a line holding any of those and a
    git word is the fail-closed rule's (`fails_closed`), which never approves it, so what this
    reading misses there is a prompt, never an allow. What it does find is denied
    (`echo $(true) git push origin main` is, as on `origin/main`). Rounds 4 to 8 of
    orchestration-record-fixes stacked a scoped and a crude reading on this one; each was met
    by the next grammar shape, and they are gone (its NOTES.md)."""
    # Every reading of the line (`judged_texts`), one after another: a command is owed its
    # deny when any reading bash may make of the line holds it. The walk has taken each
    # reading's comments out, so a `#` still in it is the literal bash reads (`a#b`, `$#`,
    # `${x#y}`) and is kept from `never_judged`, whose `#` guard is for text no walk has read
    # (`git push --force origin x a#b` lost its deny to that `#`); its other guard holds.
    tokens = []
    for text in judged_texts(command):
        reading = None if never_judged(text.replace(COMMENT_CHAR, "")) else judged_tokens(text)
        if reading is not None:
            tokens.extend(reading + [LINE_BREAK_NEWLINE])
    if not tokens:
        return None

    commands, current, at_head, redirect_target = [], [], True, False

    def flush():
        if current:
            commands.append(list(current))
            del current[:]

    for t in tokens:
        if is_operator_token(t):
            for kind, _operator in punctuation_pieces(t):
                if kind == OPERATOR_KIND_REDIRECT:
                    redirect_target = True
                    continue
                redirect_target = False
                flush()
                at_head = True
            continue
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


def bundles_push_force(token):
    """True when `token` is a cluster of `git push`'s short flags holding `-f` (`-fu`, `-uf`,
    `-vfq`): git reads the letters left to right and a force among them is a force push. The
    letters stop at `-o`, which takes the rest of the word as its value (`-ofoo` pushes an
    option, not a force); `-u`, `-q`, `-v`, `-n`, `-d` and the rest are no force
    (hook-audit-gaps, the `-fu` gap)."""
    if not token.startswith(FLAG_PREFIX) or token.startswith(LONG_FLAG_PREFIX):
        return False
    for letter in token[1:]:
        if letter == GIT_PUSH_VALUE_LETTER:
            return False
        if letter == GIT_PUSH_FORCE_LETTER:
            return True
    return False


def git_mutates(args):
    """True when these subcommand tokens move a ref, rewrite history or throw work away."""
    if not args:
        return False
    subcommand, rest = args[0], args[1:]
    if subcommand in GIT_ALWAYS_MUTATING:
        return True
    if subcommand == GIT_STASH:
        # Only the FIRST argument names a stash subcommand: bare `git stash`, a leading
        # flag or pathspec (both a push) and an unknown subcommand are all denied.
        return not rest or rest[0] not in GIT_STASH_READ_ONLY
    if subcommand == GIT_PUSH:
        return any(a in GIT_PUSH_FORCE_FLAGS
                   or a.split(FLAG_VALUE_SEP, 1)[0] == GIT_PUSH_FORCE_LEASE_FLAG
                   or bundles_push_force(a)
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


def brace_sequence(body):
    """The members of a `{x..y[..step]}` sequence — letters or integers, in either direction —
    or None when `body` is no sequence (bash leaves those braces as written). Numbers are not
    zero-padded: no git flag is a number. Raises OverflowError past MAX_BRACE_WORDS."""
    match = BRACE_SEQUENCE_RE.match(body)
    if not match or match.group(1).isalpha() != match.group(2).isalpha():
        return None
    letters = match.group(1).isalpha()
    low, high = [ord(end) if letters else int(end) for end in match.group(1, 2)]
    step = abs(int(match.group(3) or BRACE_SEQUENCE_STEP)) or BRACE_SEQUENCE_STEP
    span = range(low, high + 1, step) if low <= high else range(low, high - 1, -step)
    if len(span) > MAX_BRACE_WORDS:
        raise OverflowError(body)
    return [chr(member) if letters else str(member) for member in span]


def brace_words(word):
    """Every word bash's brace expansion makes of `word`, in bash's order — the git deny's
    reading (`expanded_argv` is the approval's: simple groups, and None for the rest, which an
    approval refuses and a deny must still read). The leftmost group that expands — comma
    alternatives at its own depth, or a sequence (`brace_sequence`) — is replaced by each
    alternative and the result expanded again, so nested and repeated groups are read; a group
    that does not expand (`{a}`, `{}`, an unclosed `{`) stays as written. The word comes from
    the lexer with its quoting gone, so a quoted group is expanded as well: more words to
    judge, never fewer. Raises OverflowError past MAX_BRACE_WORDS."""
    start = word.find(BRACE_OPEN)
    while start >= 0:
        depth, commas, end = 0, [], -1
        for at in range(start, len(word)):
            if word[at] == BRACE_OPEN:
                depth += 1
            elif word[at] == BRACE_CLOSE:
                depth -= 1
                if not depth:
                    end = at
                    break
            elif word[at] == BRACE_ALTERNATIVE_SEP and depth == 1:
                commas.append(at)
        if end >= 0:
            cuts = [start] + commas + [end]
            alternatives = [word[a + 1:b] for a, b in zip(cuts, cuts[1:])] if commas else \
                brace_sequence(word[start + 1:end])
            if alternatives is not None:
                words = []
                for alternative in alternatives:
                    words.extend(brace_words(word[:start] + alternative + word[end + 1:]))
                    if len(words) > MAX_BRACE_WORDS:
                        raise OverflowError(word)
                return words
        start = word.find(BRACE_OPEN, start + 1)
    return [word]


def git_commands(command):
    """`(words, args)` for every git command on the line the deny may judge: `args` are
    the tokens after `git` and its global options. Empty when the line cannot be judged
    (`command_words`' guards)."""
    commands = command_words(command)
    if commands is None:
        return []
    judged = []
    for words in commands:
        # A brace word is judged as bash will expand it (`brace_words`): skipping it let
        # `git branch -D old {a,b}` through to a prompt, and bash runs that (hook-audit-gaps,
        # F2). Each word is replaced in place by its expansion, empty words dropped as bash
        # drops them; a word that expands to nothing is kept as written (a quoted `'{,}'` is
        # that word to bash). Past the cap the command cannot be read, and a git command that
        # cannot be read is judged as one that mutates, never passed on.
        if any(ch in BRACE_CHARS for word in words for ch in word):
            try:
                words = [made for word in words
                         for made in ([w for w in brace_words(word) if w] or [word])]
            except (OverflowError, RecursionError):
                if git_subcommand_args(words) is not None or \
                        any(ch in BRACE_CHARS for ch in words[0]):
                    judged.append((words, list(GIT_UNREADABLE_ARGS)))
                continue
        args = git_subcommand_args(words)
        if args is not None:
            judged.append((words, args))
    return judged


def mutates_git_refs(command):
    """True when any command on the line is a ref-moving git command. Independent of the
    root, the cwd and the profile: the shape is wrong wherever it runs."""
    return any(git_mutates(args) for _, args in git_commands(command))


def profile_is_cloud():
    """True only when hooks/env_profile.py decides `cloud`. Never raises: a module that is
    missing, an invalid override, any failure at all reads as local — today's answers."""
    if env_profile is None:
        return False
    try:
        return env_profile.is_cloud()
    except Exception:  # detection failing is never a deny and never a crash
        return False


def git_location(words, cwd):
    """The directory a git command runs in: the payload's cwd (else the project root),
    moved by each `-C <path>` among git's global options the way git itself composes them.
    None when nothing absolute can be had."""
    location = cwd if isinstance(cwd, str) and os.path.isabs(cwd) else project_root()
    args = words[1:]
    while args and args[0].startswith(FLAG_PREFIX):
        flag = args[0]
        takes_value = flag.split(FLAG_VALUE_SEP, 1)[0] in GIT_GLOBAL_VALUE_FLAGS
        attached = FLAG_VALUE_SEP in flag
        if flag == GIT_LOCATION_FLAG and len(args) > 1 and location is not None:
            location = os.path.join(location, args[1])
        args = args[2:] if (takes_value and not attached) else args[1:]
    return location


def git_probe_text(location, *argv):
    """`git -C <location> <argv>`: its whole stdout, or None on any failure — a non-zero
    exit, no git, a timeout. Bounded and silent; never raises."""
    env = {k: v for k, v in os.environ.items() if k not in GIT_PROBE_DROPPED_ENVS}
    try:
        done = subprocess.run((GIT_PROGRAM, "-C", location) + tuple(argv),
                              stdin=subprocess.DEVNULL, capture_output=True, text=True,
                              timeout=GIT_PROBE_TIMEOUT_SECONDS, env=env)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    if done.returncode != 0:
        return None
    return done.stdout


def git_probe(location, *argv):
    """`git -C <location> <argv>`: its stdout lines, or None on any failure."""
    text = git_probe_text(location, *argv)
    return None if text is None else text.splitlines()


def checkout_state(location):
    """`(toplevel, branch)` of the checkout at `location`; `branch` is None on a detached
    HEAD, and both are None when git cannot say."""
    if not location:
        return None, None
    lines = git_probe(location, *GIT_PROBE_TOPLEVEL_AND_HEAD)
    if not lines or len(lines) < 2:
        return None, None
    toplevel, head = lines[0], lines[1]
    branch = head[len(GIT_BRANCH_REF_PREFIX):] if head.startswith(GIT_BRANCH_REF_PREFIX) else None
    return toplevel, branch


def branch_name(ref, branch):
    """A branch-or-HEAD spelling as the branch it names: `HEAD`/`@` are `branch`, and
    `refs/heads/x` is `x`."""
    if ref in GIT_HEAD_NAMES:
        return branch
    if ref.startswith(GIT_BRANCH_REF_PREFIX):
        return ref[len(GIT_BRANCH_REF_PREFIX):]
    return ref


def switch_leaves(rest, branch):
    """True when `git switch <rest>` would leave `branch`: `--detach`/`-d`, `--orphan`,
    `-` (the previous branch), or a first positional that is any other branch."""
    skip = False
    for token in rest:
        if skip:
            skip = False
            continue
        if token == GIT_PREVIOUS_BRANCH:
            return True
        if token.startswith(FLAG_PREFIX):
            name = token.split(FLAG_VALUE_SEP, 1)[0]
            if name in GIT_SWITCH_DETACH_FLAGS or name == GIT_ORPHAN_FLAG:
                return True
            skip = name in GIT_SWITCH_VALUE_FLAGS and FLAG_VALUE_SEP not in token
            continue
        return branch_name(token, branch) != branch
    return False


def names_a_commit(location, ref):
    """True when `ref` is a commit git would switch to: one it resolves (a branch, a tag,
    a sha), or a remote-tracking branch's short name, which `git checkout <name>` turns
    into a new local branch. False when git cannot say — a path, then."""
    if git_probe(location, *(GIT_PROBE_COMMIT + (ref + GIT_COMMIT_PEEL,))) is not None:
        return True
    remote_branches = git_probe(location, *GIT_PROBE_REMOTE_BRANCHES)
    return bool(remote_branches) and ref in remote_branches


def checkout_leaves(rest, branch, location):
    """True when `git checkout <rest>` would leave `branch`. A file checkout never does:
    anything after `--`, a path-mode flag, or more than one positional (a tree-ish and
    paths, or only paths). One positional leaves when it is `-`, or names a commit that is
    not this branch; one git cannot resolve is a path."""
    if GIT_PATHSPEC_SEPARATOR in rest:
        return False
    positionals, skip = [], False
    for token in rest:
        if skip:
            skip = False
            continue
        if token == GIT_PREVIOUS_BRANCH:
            return True
        if token.startswith(FLAG_PREFIX):
            name = token.split(FLAG_VALUE_SEP, 1)[0]
            if name in GIT_CHECKOUT_PATH_FLAGS:
                return False
            if name in GIT_CHECKOUT_DETACH_FLAGS or name == GIT_ORPHAN_FLAG:
                return True
            skip = name in GIT_CHECKOUT_VALUE_FLAGS and FLAG_VALUE_SEP not in token
            continue
        positionals.append(token)
    if len(positionals) != 1:
        return False
    target = positionals[0]
    if branch_name(target, branch) == branch:
        return False
    return names_a_commit(location, target)


def push_reading(rest):
    """`(refspecs, wholesale)` of `git push <rest>`, read from its words alone. `refspecs`
    are the positionals after the remote — the first positional is the remote unless
    `--repo <r>` / `--repo=<r>` named it, in which case every positional is a refspec.
    `wholesale` is a flag that pushes every branch, ref or tag, or deletes."""
    positionals, pending, wholesale, repo_named = [], None, False, False
    for token in rest:
        if pending is not None:
            repo_named = repo_named or pending == GIT_PUSH_REPO_FLAG
            pending = None
            continue
        if token.startswith(LONG_FLAG_PREFIX):
            name = token.split(FLAG_VALUE_SEP, 1)[0]
            if name in GIT_PUSH_EVERY_REF_FLAGS or name in GIT_PUSH_DELETE_FLAGS:
                wholesale = True
            if name in GIT_PUSH_VALUE_FLAGS:
                if FLAG_VALUE_SEP in token:
                    repo_named = repo_named or name == GIT_PUSH_REPO_FLAG
                else:
                    pending = name             # the next token is its value
            continue
        if token.startswith(FLAG_PREFIX) and token != FLAG_PREFIX:
            for i, letter in enumerate(token[1:]):
                if letter == GIT_PUSH_DELETE_LETTER:
                    wholesale = True
                if letter == GIT_PUSH_VALUE_LETTER:
                    if i == len(token) - 2:    # `-o <value>`; `-o<value>` is attached
                        pending = GIT_PUSH_VALUE_LETTER
                    break
            continue
        positionals.append(token)
    return (positionals if repo_named else positionals[1:]), wholesale


def refspec_destination(refspec, branch):
    """`(destination, deletes)` of one refspec `[+]<src>[:<dst>]`: `dst`, else `src`, as
    the branch it names (`HEAD`/`@` are `branch`, None when that is unknown;
    `refs/heads/` stripped). An empty `src` deletes `dst`."""
    spec = refspec[len(GIT_REFSPEC_FORCE_PREFIX):] if refspec.startswith(
        GIT_REFSPEC_FORCE_PREFIX) else refspec
    source, separator, destination = spec.partition(GIT_REFSPEC_SEPARATOR)
    if separator and not source:
        return branch_name(destination, branch), True
    return branch_name(destination or source, branch), False


def push_goes_elsewhere(rest, branch):
    """True when `git push <rest>` would push or delete anything but `branch`: a flag that
    pushes every branch, ref or tag, or deletes; or a refspec whose destination is another
    ref, or a deletion. No refspec at all — `git push`, `git push origin` — is not judged
    here."""
    refspecs, wholesale = push_reading(rest)
    if wholesale:
        return True
    for refspec in refspecs:
        destination, deletes = refspec_destination(refspec, branch)
        if deletes or destination != branch:
            return True
    return False


def push_reaches_protected(rest, branch=None):
    """True when `git push <rest>` names GIT_PROTECTED_BRANCH as a destination — pushed to
    or deleted. `branch` is the current branch when it is known (the cloud): then `HEAD`/`@`
    and a push with no refspec resolve to it. Locally it is None, and only the words count."""
    refspecs, _ = push_reading(rest)
    if not refspecs:
        return branch == GIT_PROTECTED_BRANCH
    return any(refspec_destination(refspec, branch)[0] == GIT_PROTECTED_BRANCH
               for refspec in refspecs)


def names_protected_push(args):
    """True when these subcommand tokens are a push to GIT_PROTECTED_BRANCH, read from the
    words alone — the both-profile entry, decided with no git probe. Never raises."""
    if not args or GIT_HOOK_ONLY_RULE(args[0]) != PUSH_TO_PROTECTED:
        return False
    try:
        return push_reaches_protected(args[1:])
    except Exception:  # a reading that fails is today's answer, never a crash
        return False


def cloud_refuses(words, args, cwd):
    """True when, in the cloud, this git command is one of the table's cloud-only shapes
    for the branch its checkout is on. The current branch is read only here — for a
    switch, a checkout or a push — and a branch that cannot be read refuses nothing but,
    on a detached HEAD, a switch that would move the working tree off HEAD's commit."""
    rule = GIT_CLOUD_ONLY_RULE(args[0]) if args else None
    if rule is None:
        return False
    location = git_location(words, cwd)
    _, branch = checkout_state(location)
    if branch is None:
        return rule == CLOUD_SWITCH_AWAY and detached_switch_moves(args, location)
    rest = args[1:]
    if rule == CLOUD_PUSH_ELSEWHERE:
        # ... and, the both-profile entry resolved: a push whose target is the protected
        # branch because it is the current one (`git push` on `main`).
        return push_goes_elsewhere(rest, branch) or push_reaches_protected(rest, branch)
    if rule == CLOUD_SWITCH_AWAY:
        if args[0] == GIT_SWITCH:
            return switch_leaves(rest, branch)
        return checkout_leaves(rest, branch, location)
    return False


def repo_shape(root):
    """`(tool prefix, self arg, features dir)` for the repo `root` is: agentTooling's own
    checkout when this file's agentTooling directory IS the root, a consuming repo
    otherwise (session-start.sh's TOOL_PREFIX, SELF_ARG and FEATURES_LABEL)."""
    tooling = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    real_root = os.path.realpath(root) if root else None
    if real_root and tooling == real_root:
        return SELF_TOOL_PREFIX, SELF_ARG, SELF_FEATURES_DIR
    vendored = VENDORED_DIR_DEFAULT
    if real_root and tooling.startswith(real_root + os.sep):
        vendored = os.path.relpath(tooling, real_root)
    return TOOL_PREFIX_TEMPLATE % vendored, "", CONSUMER_FEATURES_DIR


def manifest_first_branch(path, slug):
    """The fence's `branches[0]`, or the slug when it names none — plan-runner-roots.sh's
    manifest_branch, read in Python."""
    with open(path, encoding="utf-8") as handle:
        return manifest_lines_first_branch(handle, slug)


def manifest_lines_first_branch(lines, slug):
    """manifest_first_branch over a manifest's lines, wherever they were read from."""
    fence, last, inside = [], None, False
    for line in lines:
        if MANIFEST_FENCE_OPEN_RE.match(line):
            fence, inside = [], True
        elif MANIFEST_FENCE_CLOSE_RE.match(line):
            if inside:
                last = "".join(fence)
            inside = False
        elif inside:
            fence.append(line if line.endswith("\n") else line + "\n")
    try:
        branches = json.loads(last).get(MANIFEST_BRANCHES_FIELD) if last else None
    except (ValueError, AttributeError):
        branches = None
    if isinstance(branches, list) and branches and isinstance(branches[0], str):
        return branches[0]
    return slug


def started_feature(toplevel, features_dir, branch, tree=None):
    """`(slug, manifest path)` of the tracked feature whose manifest names `branch` as
    branches[0], or `(None, None)` — session-start.sh's started_feature. With `tree` (a
    commit-ish), the manifests committed in that tree are read instead of the checkout's:
    the off-branch case, where the manifest lives on the feature's branch, not on `main`."""
    pattern = "%s/*/%s" % (features_dir, MANIFEST_NAME)
    where = (tree,) if tree else ()
    hits = git_probe(toplevel, *(GIT_PROBE_GREP + (branch,) + where + ("--", pattern))) or []
    tree_prefix = tree + GIT_TREE_PATH_SEPARATOR if tree else ""
    for hit in hits:
        if not hit.startswith(tree_prefix):
            continue
        rel = hit[len(tree_prefix):]
        parts = rel.split("/")
        if len(parts) != len(features_dir.split("/")) + 2:
            continue
        slug = parts[-2]
        try:
            if tree:
                lines = git_probe(toplevel, GIT_SHOW, tree + GIT_TREE_PATH_SEPARATOR + rel)
                found = manifest_lines_first_branch(lines or [], slug) if lines else None
            else:
                found = manifest_first_branch(os.path.join(toplevel, rel), slug)
            if found == branch:
                return slug, rel
        except (OSError, UnicodeDecodeError):
            continue
    return None, None


def switch_target_names(args):
    """Every branch name a `git switch`/`git checkout` names — its positionals before `--`
    and the value of a branch-creating flag (`-b x`, `-c=x`) — `refs/heads/` stripped;
    empty for any other subcommand. Read from the words alone."""
    if not args or args[0] not in (GIT_SWITCH, GIT_CHECKOUT):
        return []
    value_flags = GIT_SWITCH_VALUE_FLAGS | GIT_CHECKOUT_VALUE_FLAGS
    names, skip = [], False
    for token in args[1:]:
        if token == GIT_PATHSPEC_SEPARATOR:
            break
        if skip:
            names.append(token)
            skip = False
            continue
        if token.startswith(FLAG_PREFIX):
            name, separator, value = token.partition(FLAG_VALUE_SEP)
            if name in value_flags:
                if separator:
                    names.append(value)
                else:
                    skip = True
            continue
        names.append(token)
    return [branch_name(name, None) for name in names if name]


def off_branch_target(toplevel, features_dir, args, branch):
    """`(target, slug, manifest)` when this switch names a branch some tracked manifest
    records as `branches[0]` — the name as written, or a remote-tracking spelling
    (`origin/x`, which git knows as refs/remotes/origin/x) as its short name `x` — and
    that branch is not the current one; else None."""
    remote_refs = None
    for name in switch_target_names(args):
        # The commit the switch would land on, whose own tree holds the feature's manifest
        tree = name if git_probe(
            toplevel, *(GIT_PROBE_COMMIT + (name + GIT_COMMIT_PEEL,))) is not None else None
        candidates = [name]
        if GIT_REMOTE_SEPARATOR in name and git_probe(
                toplevel, *(GIT_PROBE_COMMIT + (GIT_REMOTE_REF_PREFIX + name,))) is not None:
            candidates.append(name.split(GIT_REMOTE_SEPARATOR, 1)[1])
        if tree is None:
            # `git checkout x` with only `origin/x`: git would create `x` from it
            if remote_refs is None:
                remote_refs = git_probe(toplevel, *GIT_PROBE_REMOTE_REFS) or []
            suffix = GIT_REMOTE_SEPARATOR + name
            tree = next((ref for ref in remote_refs if ref.endswith(suffix)
                         and ref[len(GIT_REMOTE_REF_PREFIX):].count(GIT_REMOTE_SEPARATOR)
                         == name.count(GIT_REMOTE_SEPARATOR) + 1), None)
        for candidate in candidates:
            if candidate == branch:
                continue
            for where in (None, tree) if tree else (None,):
                slug, manifest = started_feature(toplevel, features_dir, candidate, where)
                if slug:
                    return candidate, slug, manifest
    return None


def cloud_off_branch_reason(args, toplevel, branch, features_dir):
    """GIT_CLOUD_OFF_BRANCH_TEMPLATE filled, when the checkout is on GIT_PROTECTED_BRANCH
    or detached and `args` switches to a started feature's branch; else None."""
    if branch is not None and branch != GIT_PROTECTED_BRANCH:
        return None
    if not toplevel:
        return None
    found = off_branch_target(toplevel, features_dir, args, branch)
    if not found:
        return None
    target, slug, manifest = found
    here = BRANCH_QUOTE % branch if branch else OFF_BRANCH_DETACHED
    return GIT_CLOUD_OFF_BRANCH_TEMPLATE % {"target": target, "slug": slug,
                                            "manifest": manifest, "here": here,
                                            "protected": GIT_PROTECTED_BRANCH}


def commit_of(location, ref):
    """The commit `ref` names in the checkout at `location`, or None."""
    lines = git_probe(location, *(GIT_PROBE_COMMIT + (ref + GIT_COMMIT_PEEL,)))
    return lines[0] if lines else None


def detached_switch_moves(args, location):
    """True when, on a detached HEAD, this `git switch`/`git checkout` would put the
    working tree on a commit other than HEAD's: `-`, `--orphan`, or a target — a ref, a
    sha, or the short name of an origin/ branch git would create a local branch from —
    that resolves to another commit. A file checkout, a target git cannot resolve, and a
    switch landing on HEAD's own commit (re-attaching a branch already AT it) move
    nothing and are not refused."""
    rest = args[1:]
    if args[0] == GIT_SWITCH:
        leaves, value_flags = switch_leaves(rest, None), GIT_SWITCH_VALUE_FLAGS
    else:
        leaves, value_flags = checkout_leaves(rest, None, location), GIT_CHECKOUT_VALUE_FLAGS
    if not leaves:
        return False
    positionals, skip = [], False
    for token in rest:
        if skip:
            skip = False
            continue
        if token == GIT_PREVIOUS_BRANCH:
            return True
        if token.startswith(FLAG_PREFIX):
            name = token.split(FLAG_VALUE_SEP, 1)[0]
            if name == GIT_ORPHAN_FLAG:
                return True
            skip = name in value_flags and FLAG_VALUE_SEP not in token
            continue
        positionals.append(token)
    target = positionals[0] if positionals else GIT_HEAD
    head = commit_of(location, GIT_HEAD)
    there = commit_of(location, target) or commit_of(location,
                                                     GIT_ATTACH_REMOTE_PREFIX + target)
    return head is not None and there is not None and there != head


def attachable_branch(toplevel, features_dir):
    """`(branch, slug, manifest)` of the first branch a detached HEAD can be re-attached to
    moving nothing — plan-runner-roots.sh's attachable_branches: `origin/<branch>` IS
    HEAD's commit, a tracked manifest names <branch> as branches[0], and the local
    <branch> is absent or an ancestor of HEAD; else None."""
    names = git_probe(toplevel, *GIT_PROBE_ATTACH_CANDIDATES) or []
    for name in sorted(names):
        if not name or name == GIT_HEAD:
            continue
        slug, manifest = started_feature(toplevel, features_dir, name)
        if not slug:
            continue
        local = GIT_BRANCH_REF_PREFIX + name
        if commit_of(toplevel, local) is not None and git_probe(
                toplevel, *(GIT_PROBE_IS_ANCESTOR + (local, GIT_HEAD))) is None:
            continue
        return name, slug, manifest
    return None


def cloud_git_deny_reason(words, cwd, args=None):
    """The cloud reason for refusing `words`: the branch, and the started feature and its
    close when one exists, or the start to run here — or, on a detached HEAD at a started
    feature's origin tip, the attach reason; or, when `args` switches a checkout on `main`
    or detached to a started feature's branch, the off-branch reason. Never raises — what
    cannot be read is left out, and the reason is still a cloud one."""
    branch_text, feature_text = BRANCH_UNKNOWN, ""
    toplevel = branch = None
    try:
        toplevel, branch = checkout_state(git_location(words, cwd))
    except Exception:  # read as unreadable: the reason below still names what it can
        pass
    try:
        prefix, self_arg, features_dir = repo_shape(project_root())
        # Only a detached HEAD is probed for the attach: every other refusal pays nothing
        if toplevel and branch is None:
            found = attachable_branch(toplevel, features_dir)
            if found:
                attach, slug, manifest = found
                command = "%s%s %s%s" % (prefix, ATTACH_SCRIPT, self_arg, attach)
                return GIT_CLOUD_ATTACH_TEMPLATE % {"branch": attach, "slug": slug,
                                                    "manifest": manifest,
                                                    "command": command}
        # Only a switch/checkout naming a branch is probed for the off-branch reason
        if switch_target_names(args):
            off_branch = cloud_off_branch_reason(args, toplevel, branch, features_dir)
            if off_branch:
                return off_branch
    except Exception:  # the ordinary cloud reason, below, is owed either way
        pass
    try:
        root = project_root()
        prefix, self_arg, features_dir = repo_shape(root)
        fields = {"prefix": prefix, "self_arg": self_arg}
        feature_text = GIT_CLOUD_UNSTARTED_TEMPLATE % fields
        if branch:
            branch_text = BRANCH_QUOTE % branch
            slug, manifest = started_feature(toplevel, features_dir, branch)
            if slug:
                feature_text = GIT_CLOUD_STARTED_TEMPLATE % dict(fields, slug=slug,
                                                                 manifest=manifest)
    except Exception:  # a reason is owed either way; it just names less
        pass
    return GIT_CLOUD_DENY_REASON_TEMPLATE % {"branch": branch_text,
                                            "feature": feature_text}


def git_denial(command, cwd):
    """The git deny's reason when the line carries a git command to refuse, else None.
    Locally: the ref-moving shapes, with GIT_DENY_REASON, as before, and a push naming
    `main`, with GIT_PUSH_PROTECTED_DENY_REASON — no git probe on either. In the cloud: the
    same shapes and the table's cloud-only ones, with the cloud reason."""
    commands = git_commands(command)
    if not commands:
        return None
    mutating = [(words, args) for words, args in commands if git_mutates(args)]
    protected = [(words, args) for words, args in commands if names_protected_push(args)]
    if not profile_is_cloud():
        if mutating:
            return GIT_DENY_REASON
        return GIT_PUSH_PROTECTED_DENY_REASON if protected else None
    if mutating or protected:
        words, args = (mutating or protected)[0]
        return cloud_git_deny_reason(words, cwd, args)
    for words, args in commands:
        try:
            refused = cloud_refuses(words, args, cwd)
        except Exception:  # a reading that fails is today's answer, never a deny
            refused = False
        if refused:
            return cloud_git_deny_reason(words, cwd, args)
    return None


def assigned_names(command):
    """`{NAME: offset}` for every variable assigned at command position on this line.

    A command whose words are *all* assignments is an assignment command (`X=/p`,
    `export X=/p A=1`); one with anything else after them is a command with an
    environment prefix (`X=1 make`), which decides nothing the shell then re-reads on
    the same line and is never denied. The offset is where the assignment is spelled, so
    a use can be required to come after it.

    Empty when the line cannot be judged: `command_words` returns None for text that does
    not tokenize or that `never_judged` holds back (a comment and a heredoc's body are not
    read; what follows a body is), because a deny must not fire on a guess.
    """
    commands = command_words(command)
    if commands is None:
        return {}
    text = judged_text(command)         # offsets are the ones `uses_own_assignment` reads
    names = {}
    for words in commands:
        rest = list(words)
        while rest and rest[0] in ASSIGNMENT_BUILTINS:
            rest = rest[1:]
        matches = [ASSIGNMENT_RE.match(word) for word in rest]
        if not matches or not all(matches):
            continue
        for match in matches:
            names.setdefault(match.group(1), text.find(match.group(1) + FLAG_VALUE_SEP))
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
    """True when a name assigned at command position is dereferenced later on the line — in
    any reading `judged_texts` returns, each with its own offsets, as the assignment is found
    in any (escalations/02-audit-opus.md, R2-3: the use was looked for in the first reading
    alone, where a comment in doubt is dropped — `a=(x)#b; X=/p; cat $X/f`)."""
    names = assigned_names(command)
    if not names:
        return False
    for text in judged_texts(command):
        for name, offset in active_var_uses(text):
            if name in names and offset > text.find(name + FLAG_VALUE_SEP):
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


def piped_into_interpreter(sep, member):
    """True when this `redirect_members` member is the right-hand side of a pipe and is an
    interpreter with no script to run — `… | sh`, `… | python3`. `||` is not a pipe, and
    a lone `-` is not a script.

    It reads a member rather than an `opaque_segments` segment because a segment keeps a
    redirect's operator and target as words: `ls | sh > out` read as `sh` running a
    script named `>`, and printed nothing where the line without the redirect is this
    deny (self/features/hook-pipe-redirect). The member's words have every redirect taken
    out already. An input redirect from a file (REDIRECT_SCRIPT_OP) is the script, so
    `ls | python3 < a.py` stays readable, as it was."""
    if sep not in PIPE_SEPARATORS:
        return False
    head = program_words(member.words)
    if not head or command_name(head[0]) not in INTERPRETER_CODE_LETTER:
        return False
    if any(op == REDIRECT_SCRIPT_OP for op, _target in member.redirects):
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
    since a line that will not tokenize cannot be asked where its quotes are — which is
    why `never_judged` counts any `#` on a line whose quotes never close. Its other
    case matters most here: shlex refuses `echo $'\\''`, which the shell runs.

    One line they do not excuse: a reading the walk BUILT — the comment dropped, the body
    placed, as bash does — whose quotes then never close (`tears_a_reading`). Bash has run
    what came before the quote, no reader here can lex the reading, and a line that names
    no git has no other deny to take (escalations/03-audit-opus.md, R3-1).
    """
    if tears_a_reading(command):
        return True
    if HEREDOC_OPERATOR in command or never_judged(command):
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
    # The pipe is judged on redirect_members' members, whose words carry no redirect —
    # on a heredoc's first line only, the same cut segments_before_line_break makes.
    piped = any(piped_into_interpreter(sep, member) for sep, member
                in redirect_members(command, stop_at_line_break=bool(heredocs)))
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
        return piped or any(code_as_string(words)
                            for _sep, words in segments_before_line_break(segments))
    if piped:
        return True
    for _sep, words in segments:
        if (code_as_string(words)
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


def sleeps(words):
    """True when the member's program is `sleep`, bare or by path."""
    head = program_words(words)
    return bool(head) and command_name(head[0]) == SLEEP_PROGRAM


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
    if HEREDOC_OPERATOR in command or never_judged(command):
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
                                (relative_chdir, RELATIVE_CHDIR_REWRITE_REASON),
                                (sleeps, SLEEP_REWRITE_REASON)):
            if not fires(words):
                continue
            line = template % quoted
            if line not in lines:
                lines.append(line)
    if lines:
        return lines
    mixed = mixed_sequence_reason(segments, cwd, root)
    if mixed:
        return [mixed]
    alone = own_push_alone_reason(segments, cwd, root)
    return [alone] if alone else []


def own_push_alone_reason(segments, cwd, root):
    """The rewrite for a SEQUENCE (`&&`, `||`, `;`) that carries the own-branch push beside
    anything else, when the push alone would be approved: run it alone (item 4 of
    self/features/hook-silent-allow-sweep/). None otherwise — a pipeline (`… | tail`) is one
    command, as in `mixed_sequence_reason`, and a redirect is no second member — and the line
    then prompts."""
    if len(segments) < 2:
        return None
    if any(sep not in SEQUENCE_SEPARATORS for sep, _words in segments[1:]):
        return None
    for _sep, words in segments:
        text = member_text(words)
        if is_git_push(words) and member_allowed(text, cwd, root):
            return OWN_PUSH_ALONE_REWRITE_REASON % (MEMBER_QUOTE % text)
    return None


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
            flushed = len(members)
            flush(index)
            if stop_at_line_break:
                return members
            # `ls |` then a line break is still one pipeline, as bash reads it: a break
            # that ends no member keeps the pipe it follows as the next member's separator
            if not (len(members) == flushed and sep in PIPE_SEPARATORS):
                sep = ch
            start = index + 1
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
    A member `never_judged` holds back (an unquoted `#`, a `$'…'` escaping a quote) means
    the line is not judged, the guard every rewrite keeps.
    """
    members = redirect_members(command, stop_at_line_break=HEREDOC_OPERATOR in command)
    if any(never_judged(member.text) for _sep, member in members):
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


def entry_script(token, cwd, root, basename, spellings):
    """True when the token names `basename` and the file it spells is inside the root —
    resolved through symlinks, like every other path, and required to exist, so a
    basename on its own vouches for nothing.

    The token must carry a DIRECTORY COMPONENT (`./x`, `self/gate.sh`, an absolute path).
    A bare `check-plans.sh` is resolved by bash along `$PATH`, not from the cwd, so the
    file this function would find in the repo and the program bash would run are two
    different things — and the one bash runs is whatever `$PATH` names first. That form
    prompts (self/BACKLOG.md, raised by the permissions-policy-inherit review).

    And the path, relative to the root, must be one of `spellings` (ENTRY_GATE_SPELLINGS,
    ENTRY_CHECK_PLANS_SPELLINGS): `x/gate.sh` planted in the root is not the gate."""
    if os.path.basename(token) != basename or not os.path.dirname(token):
        return False
    path = token if token.startswith(os.sep) else os.path.join(cwd, token)
    if os.path.relpath(os.path.normpath(path), root) not in spellings:
        return False
    return (os.path.lexists(path) and inside(path, root)
            and symlink_free_below(path, root))


def symlink_free_below(path, root):
    """True when `path` is spelled inside the root and no component of it below the root
    is a symlink — the directories and the file itself. `inside` follows links, so a link
    to another in-root file passes it; this is what refuses one (self/features/
    runner-write-allows/, F9: a planted or linked file carrying a script's name)."""
    normalized = os.path.normpath(path)
    if not lexically_inside(normalized, root):
        return False
    current = root
    for part in os.path.relpath(normalized, root).split(os.sep):
        if part == os.curdir:
            continue
        current = os.path.join(current, part)
        if os.path.islink(current):
            return False
    return True


def hook_analysis_pins(root):
    """The pinned analysis directory beside the running hook, as a one-item tuple, or `()`:
    ENTRY_PINNED_OWN when this hook is `<root>/hooks/…`, ENTRY_PINNED_VENDORED when it is
    `<root>/agentTooling/hooks/…` — compared by realpath, as `orchestrator_tooling_file`
    pins — and nothing for a hook that lives anywhere else."""
    tooling = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    for pinned in (ENTRY_PINNED_OWN, ENTRY_PINNED_VENDORED):
        if os.path.realpath(os.path.join(root, os.path.dirname(pinned))) == tooling:
            return (pinned,)
    return ()


def pinned_entry_dir(token, cwd, root, basename):
    """The pinned directory (the one `hook_analysis_pins` names for this hook) when the token
    names `<root>/<dir>/<basename>` — exactly that lexical path, an existing regular file,
    no symlink below the root — else None. Like `entry_script`, the token needs a
    directory component, so bash's `$PATH` is never what it spells."""
    if os.path.basename(token) != basename or not os.path.dirname(token):
        return None
    path = os.path.normpath(token if token.startswith(os.sep) else os.path.join(cwd, token))
    for pinned in hook_analysis_pins(root):
        if path == os.path.join(root, pinned, basename):
            ok = (os.path.isfile(path) and symlink_free_below(path, root)
                  and os.path.realpath(path) == path)
            return pinned if ok else None
    return None


def report_shape(args, pinned):
    """`[--self] <slug>`, `[--self] --all`, `[--self] --rounds-md <slug>` or `[--self]
    --orchestration <slug>`. The checkout's own script (ENTRY_PINNED_NEEDS_SELF) also
    needs the `--self`."""
    selfed = args[:1] == [ENTRY_SELF_FLAG]
    args = without_self_flag(args)
    if pinned == ENTRY_PINNED_NEEDS_SELF and not selfed:
        return False
    if args == [REPORT_ALL_FLAG]:
        return True
    if len(args) == 2 and args[0] in (REPORT_ROUNDS_FLAG, REPORT_ORCHESTRATION_FLAG):
        return bool(ENTRY_SLUG_RE.fullmatch(args[1]))
    return len(args) == 1 and bool(ENTRY_SLUG_RE.fullmatch(args[0]))


def files_only(args):
    """True when every argument is a positional — a file, not a flag — and there is one. A
    `+` word is a flag too: `bash -n +n f` turns noexec back OFF and runs f (security audit
    round 2, N1), as does `+o noexec`."""
    return bool(args) and not any(a.startswith(OPTION_PREFIXES) for a in args)


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
    read-only scripts at its pinned path (`pinned_entry_dir`) in its exact shape."""
    while args and args[0] in PYTHON_INTERPRETER_FLAGS:
        args = args[1:]
    if not args:
        return False
    if tuple(args[:len(PYTHON_PY_COMPILE)]) == PYTHON_PY_COMPILE:
        return files_only(args[len(PYTHON_PY_COMPILE):])
    script, script_args = args[0], args[1:]
    pinned = pinned_entry_dir(script, cwd, root, ENTRY_REPORT)
    if pinned:
        return report_shape(script_args, pinned)
    if pinned_entry_dir(script, cwd, root, ENTRY_CAPTURE_PLANNING):
        return capture_listing_shape(script_args)
    if pinned_entry_dir(script, cwd, root, ENTRY_MANIFEST):
        return manifest_get_shape(script_args)
    return False


def without_self_flag(args):
    return args[1:] if args[:1] == [ENTRY_SELF_FLAG] else args


def capture_listing_shape(args):
    """`[--self] --list-sessions|--list-subagents` and then only that listing's own options
    (CAPTURE_LISTING_OPTIONS), each at most once, a value option followed by one word that
    is no flag. Shared with the orchestrator's allowlist."""
    args = without_self_flag(args)
    if not args or args[0] not in CAPTURE_LISTING_OPTIONS:
        return False
    allowed, rest, seen = CAPTURE_LISTING_OPTIONS[args[0]], args[1:], set()
    while rest:
        option, rest = rest[0], rest[1:]
        if option not in allowed or option in seen:
            return False
        seen.add(option)
        if option in CAPTURE_VALUE_OPTIONS:
            if not rest or rest[0].startswith(FLAG_PREFIX):
                return False
            rest = rest[1:]
    return True


def manifest_get_shape(args):
    """`[--self] [--orchestration] <slug> get <key>`, those words and no others."""
    args = without_self_flag(args)
    if args[:1] == [MANIFEST_ORCHESTRATION_SCOPE]:
        args = args[1:]
    return (len(args) == 3 and bool(ENTRY_SLUG_RE.fullmatch(args[0]))
            and args[1] == MANIFEST_READ_SUBCOMMAND and not args[2].startswith(FLAG_PREFIX))


def harness_entry_allowed(program_token, prog, args, cwd, root):
    """The harness's own entry points, above. Every argument has already been checked
    against the root by the caller; what is judged here is the script and the form."""
    if entry_script(program_token, cwd, root, ENTRY_GATE, ENTRY_GATE_SPELLINGS):
        return len(args) <= ENTRY_GATE_MAX_ARGS
    if entry_script(program_token, cwd, root, ENTRY_CHECK_PLANS, ENTRY_CHECK_PLANS_SPELLINGS):
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
    if args[0] == GIT_STASH:
        return len(args) >= 2 and args[1] in GIT_STASH_READ_ONLY
    if args[0] == "branch":
        return all(
            a in GIT_BRANCH_ALLOWED_FLAGS or a.startswith(GIT_BRANCH_ALLOWED_FLAG_PREFIXES)
            for a in args[1:]
        )
    return True


def own_checkout(root):
    """`(checkout directory, its git directory)` for the checkout holding `root`, found by
    walking the filesystem — never by asking git. The checkout is the nearest directory at
    or above `root` holding a `.git` entry; its git directory is that entry when it is a
    directory, or the path on the `gitdir:` line when it is a regular file (a linked
    worktree), resolved against the checkout when relative. None for anything else — a
    symlink, a file that does not read that way, no `.git` at all."""
    if not GIT_DOT_ENTRY:
        return None
    directory = root
    while not os.path.lexists(os.path.join(directory, GIT_DOT_ENTRY)):
        parent = os.path.dirname(directory)
        if parent == directory:
            return None
        directory = parent
    gitdir = dot_git_target(directory)
    return None if gitdir is None else (directory, gitdir)


def dot_git_target(directory):
    """The git directory the `.git` entry in `directory` names: the entry itself when it is a
    directory, the path on its `gitdir:` line when it is a regular file (resolved against
    `directory` when relative). None for anything else — a symlink, a file that does not
    read that way, no entry."""
    entry = os.path.join(directory, GIT_DOT_ENTRY)
    if os.path.islink(entry):
        return None
    if os.path.isdir(entry):
        return entry
    if not os.path.isfile(entry):
        return None
    with open(entry, encoding="utf-8") as handle:
        lines = handle.read(OWN_PUSH_GITFILE_MAX_BYTES).splitlines()
    found = OWN_PUSH_GITFILE_RE.match(lines[0]) if lines else None
    if not found:
        return None
    return os.path.join(directory, found.group(1))


def trusted_gitdirs(root):
    """`(git directories, worktrees directory)`, realpath'd, that a read in `root` may use:
    the root checkout's own git directory (`own_checkout`) and its common directory (the
    `commondir` file's path when the git directory holds one, as a linked worktree's does),
    and the common directory's `worktrees/`, whose direct children are the linked
    worktrees' git directories. None when the root's checkout cannot be found."""
    own = own_checkout(os.path.realpath(root))
    if own is None:
        return None
    gitdir = os.path.realpath(own[1])
    common = gitdir
    pointer = os.path.join(gitdir, GIT_COMMONDIR_FILE)
    if os.path.isfile(pointer):
        with open(pointer, encoding="utf-8") as handle:
            lines = handle.read(OWN_PUSH_GITFILE_MAX_BYTES).splitlines()
        if not lines or not lines[0]:
            return None
        common = os.path.realpath(os.path.join(gitdir, lines[0]))
    return frozenset([gitdir, common]), os.path.join(common, GIT_WORKTREES_DIR)


def discovered_gitdir(location):
    """`(found, git directory)` for a git command run in `location`, read from the
    filesystem the way git discovers one, but stopping no later than git does: walking up
    from `location`'s realpath, the first directory holding a `.git` entry gives that
    entry's target (`dot_git_target`, None when it does not read as one), and the first
    directory that is itself shaped like a git directory — it holds GIT_HEAD, as
    every git directory git accepts must — gives itself. Git stops only at a directory with
    one of the two, so it never stops before this walk does. `(False, None)` when nothing is
    found up to `/`: git then reads no repository's config."""
    directory = os.path.realpath(location)
    while True:
        if os.path.lexists(os.path.join(directory, GIT_DOT_ENTRY)):
            return True, dot_git_target(directory)
        if os.path.lexists(os.path.join(directory, GIT_HEAD)):
            return True, directory
        parent = os.path.dirname(directory)
        if parent == directory:
            return False, None
        directory = parent


def location_is_pattern(value):
    """True when bash would read a location value as a pattern: a glob character
    (GIT_LOCATION_PATTERN_CHARS) or an extglob group (EXTGLOB_RE) anywhere in it. What the
    pattern matches is not this side's to guess, so such a value approves nothing."""
    return bool(GIT_LOCATION_PATTERN_CHARS.intersection(value)) or bool(EXTGLOB_RE.search(value))


def read_location_options(args, cwd, root):
    """`(location, --git-dir value or None)` of a git command's global location options, read
    the way git reads them: each `-C <path>` moves the location from the payload's cwd (else
    the root), and `--git-dir`, the last one given, names a git directory relative to where
    every `-C` has left it. None for an attached `-C=` (not git's spelling), a missing value
    — `git_location_args` refuses those first — or any location value bash would expand as a
    pattern (`location_is_pattern`: `git -C plans/e?il status`)."""
    location = cwd if isinstance(cwd, str) and os.path.isabs(cwd) else root
    git_dir = None
    while args and args[0].startswith(FLAG_PREFIX):
        name, separator, value = args[0].partition(FLAG_VALUE_SEP)
        if separator:
            args = args[1:]
        elif len(args) > 1:
            value, args = args[1], args[2:]
        else:
            return None
        if location_is_pattern(value):
            return None
        if name == GIT_LOCATION_FLAG:
            if separator:
                return None
            location = os.path.join(location, value)
        elif name == GIT_DIR_FLAG:
            git_dir = value
    if git_dir is not None:
        git_dir = os.path.join(location, git_dir)
    return location, git_dir


def read_uses_own_gitdir(args, cwd, root):
    """True when a read-only git command (`args`, the words after `git`, already approved by
    `git_allowed` and confined to the root) would use the root checkout's own git directory
    or a linked worktree's (`trusted_gitdirs`), or no repository at all. A git directory
    planted in the tree as plain files — `HEAD`, `objects/`, `refs/` and a `config` naming
    `core.fsmonitor` or `diff.external` — is neither, so `git -C <plant> status`, a cwd in
    the plant, and `git --git-dir=<plant> log` prompt rather than run what it names. No git
    runs here: asking git would read the planted config. Any failure approves nothing.
    (self/features/hook-planted-gitdir/NOTES.md)"""
    read = read_location_options(args, cwd, root)
    if read is None:
        return False
    location, git_dir = read
    if git_dir is None:
        found, git_dir = discovered_gitdir(location)
        if not found:
            return True
        if git_dir is None:
            return False
    trusted = trusted_gitdirs(root)
    if trusted is None:
        return False
    gitdirs, worktrees = trusted
    real = os.path.realpath(git_dir)
    return real in gitdirs or os.path.dirname(real) == worktrees


def own_push_config_allows(root):
    """True when the effective config in `root` (`git config --list -z`: system, global, the
    repo's own, `config.worktree`, includes and the environment's command-line scope) holds
    no key of OWN_PUSH_PRESENT_KEYS, no `http.*` variable outside OWN_PUSH_HTTP_SAFE_VARS (in
    any `http.<url>.` form too), a `push.default` that is absent, `simple` or `current`,
    and exactly one `remote.origin.url`, http(s), that `remote get-url --push --all` prints
    unchanged — so a `url.*.insteadOf` or `pushInsteadOf` that applies to it is no approval
    and one that does not apply (the cloud injects two) is. Any read that fails, or a
    record that does not parse, is False. A non-empty GIT_ASKPASS or SSH_ASKPASS in the hook's
    environment is False too (OWN_PUSH_ASKPASS_ENVS): git would run it for a credential, as
    it runs the `credential.*.helper` and `core.askpass` keys that are listed; so is any
    OWN_PUSH_HELPER_ENVS name that is set at all. The probe runs without GIT_CONFIG
    (`git_probe_text`), so it reads the config the push reads."""
    if any(os.environ.get(name) for name in OWN_PUSH_ASKPASS_ENVS):
        return False
    if any(name in os.environ for name in OWN_PUSH_HELPER_ENVS):
        return False
    text = git_probe_text(root, *GIT_PROBE_CONFIG_LIST)
    if text is None:
        return False
    records = text.split(CONFIG_RECORD_SEPARATOR)
    if records.pop() != "":
        return False
    urls = []
    for record in records:
        key, separator, value = record.partition(CONFIG_VALUE_SEPARATOR)
        if not key:
            return False
        if key in OWN_PUSH_PRESENT_KEYS or any(r.match(key) for r in OWN_PUSH_PRESENT_KEY_RES):
            return False
        section, _, variable = key.partition(".")
        if section == OWN_PUSH_HTTP_SECTION and \
                variable.rpartition(".")[2] not in OWN_PUSH_HTTP_SAFE_VARS:
            return False
        if key == OWN_PUSH_DEFAULT_KEY and (not separator
                                            or value not in OWN_PUSH_DEFAULT_VALUES):
            return False
        if key == OWN_PUSH_URL_KEY:
            urls.append(value if separator else "")
    if len(urls) != 1 or not urls[0].startswith(OWN_PUSH_URL_SCHEMES):
        return False
    return git_probe(root, *GIT_PROBE_PUSH_URLS) == urls


def own_push_hooks_absent(root):
    """True when the common git directory's `hooks/` holds neither hook a push runs locally,
    as any file type; False when git cannot name it."""
    common = git_probe(root, *GIT_PROBE_COMMON_DIR)
    if not common or len(common) != 1:
        return False
    hooks = os.path.join(root, common[0], GIT_HOOKS_DIR)
    return not any(os.path.lexists(os.path.join(hooks, name)) for name in OWN_PUSH_HOOKS)


def own_push_allowed(args, cwd, root):
    """True when, in the cloud, `args` (the words after `git`, every one already confined to
    the root) are exactly a plain push of the started feature's own branch:

        push [-u | --set-upstream] origin <B>

    with nothing before `push` — no `-C`, `--git-dir`, `--work-tree`, `-c` or other global
    option, each of which moves the git directory — run from the project root (the payload's
    cwd), `<B>` a plain branch name, the checkout's current branch AND `branches[0]` of a
    manifest committed at `HEAD` (`started_feature`). Nothing else rides along: no other
    flag, no refspec spelling (`+`, `:`, `HEAD`, `refs/`), no second branch.

    The git directory git uses from the root must be the root checkout's own, which the
    filesystem walk (`own_checkout`) names, so a git directory planted in the tree as plain
    files is never one; the config must redirect and execute nothing
    (`own_push_config_allows`) and no push hook may exist (`own_push_hooks_absent`). The
    words are judged first, then the profile, the cwd, the walk and last the git probes, so
    no git runs for any other command; any probe that fails approves nothing. The deny paths
    ran before this and are unchanged — a force push, a push to `main` and a push to another
    branch never get here. (self/features/own-push-real-gitdir/NOTES.md rulings 1-5)"""
    # The probes below read objects AS COMMITTED: a `refs/replace/` entry would hand `git
    # grep` and `git show` another blob in the committed manifest's place, with no commit, so
    # git is told to ignore replace refs from here on (escalations/01-audit-opus.md)
    os.environ[GIT_NO_REPLACE_ENV] = GIT_NO_REPLACE_ON
    words = list(args)
    if not words or words[0] != GIT_PUSH:
        return False
    words = words[1:]
    if words[:1] and words[0] in OWN_PUSH_UPSTREAM_FLAGS:
        words = words[1:]
    if len(words) != 2 or words[0] != OWN_PUSH_REMOTE:
        return False
    branch = words[1]
    if not OWN_PUSH_BRANCH_RE.match(branch) or branch in GIT_HEAD_NAMES:
        return False
    if branch.startswith(GIT_BRANCH_REF_PREFIX) or branch == GIT_PROTECTED_BRANCH:
        return False
    if not profile_is_cloud():
        return False
    real_root = os.path.realpath(root)
    if not isinstance(cwd, str) or os.path.realpath(cwd) != real_root:
        return False
    own = own_checkout(real_root)
    if own is None:
        return False
    real_top, expected_gitdir = os.path.realpath(own[0]), os.path.realpath(own[1])
    # git, run from the root, must say the same: a planted bare-repo shape in the root, a
    # `core.worktree`, a `GIT_DIR` in the environment each give another pair
    reported = git_probe(real_root, *GIT_PROBE_GITDIR_AND_TOPLEVEL)
    if not reported or len(reported) != 2 \
            or os.path.realpath(reported[0]) != expected_gitdir \
            or os.path.realpath(reported[1]) != real_top:
        return False
    if not own_push_config_allows(real_root) or not own_push_hooks_absent(real_root):
        return False
    toplevel, current = checkout_state(real_root)
    if not toplevel or current != branch or os.path.realpath(toplevel) != real_top:
        return False
    _, _, features_dir = repo_shape(root)
    relative = os.path.relpath(root, real_top)
    if relative != os.curdir:
        features_dir = relative + "/" + features_dir
    # branches[0] is read from the manifest COMMITTED at HEAD, never the working tree: a
    # commit is a write the human approves and an edit is not, and HEAD is what the push
    # sends (self/features/hook-audit-gaps/NOTES.md ruling 1)
    slug, _ = started_feature(real_top, features_dir, branch, tree=GIT_HEAD)
    return slug is not None


def runner_config_file_ok(runner, value, cwd, root):
    """A `--config`/`--config-file` value: an existing regular file inside the root whose
    name, as written and as resolved, is one `runner` discovers on its own
    (RUNNER_CONFIG_NAMES). Anything else — an inline TOML override (`fix = true`), another
    name (`fix.toml`, `cfg.ini`), a file that is not there, one outside the tree — is not."""
    names = RUNNER_CONFIG_NAMES[runner]
    path = value if value.startswith(os.sep) else os.path.join(cwd, value)
    real = os.path.realpath(path)
    if os.path.basename(path) not in names or os.path.basename(real) not in names:
        return False
    return os.path.isfile(real) and inside(real, root)


def runner_value(runner, name, attached, rest, cwd, root):
    """The value of the value-taking flag `name` (its `=` part, else the next word taken
    off `rest`), or None when it is missing, empty, a flag or an `@file`, or a settings
    file `runner_config_file_ok` refuses."""
    value = attached if attached is not None else (rest.pop(0) if rest else None)
    if not value or value.startswith((FLAG_PREFIX, RUNNER_ARGFILE_PREFIX)):
        return None
    if name in RUNNER_CONFIG_FLAGS[runner] and not runner_config_file_ok(runner, value, cwd, root):
        return None
    return value


def runner_words(runner, args, cwd, root):
    """(the flags seen, the positionals) of a runner invocation, or None as soon as one
    word is outside the allowlists above. Positionals are files and node ids, which the
    caller has path-checked already; an `@file` is never one."""
    bare, valued = RUNNER_BARE_FLAGS[runner], RUNNER_VALUE_FLAGS[runner]
    config_flags, bundles = RUNNER_CONFIG_FLAGS[runner], RUNNER_SHORT_BUNDLES[runner]
    flags, positionals, rest = set(), [], list(args)
    while rest:
        word = rest.pop(0)
        if word.startswith(RUNNER_ARGFILE_PREFIX):
            return None
        if not word.startswith(FLAG_PREFIX):
            positionals.append(word)
            continue
        # only a long flag spells its value after an `=`
        if word.startswith(RUNNER_LONG_PREFIX):
            name, sep, attached = word.partition(FLAG_VALUE_SEP)
            attached = attached if sep else None
        else:
            name, attached = word, None
        if name in valued or name in config_flags:
            if runner_value(runner, name, attached, rest, cwd, root) is None:
                return None
        elif attached is not None or not (
                name in bare or any(b.fullmatch(word) for b in bundles)):
            return None
        flags.add(name)
    return flags, positionals


def ruff_form_allowed(flags, positionals):
    """`ruff check [paths]`, `ruff format --check|--diff [paths]`, `ruff version`,
    `ruff rule <code>`, and the information flags on their own. Every other subcommand
    prompts: `clean` deletes the cache, `server` and `analyze` are not a lint."""
    if not positionals:
        return bool(flags & RUNNER_INFO_FLAGS)
    subcommand = positionals[0]
    if subcommand == RUNNER_RUFF_CHECK:
        return True
    if subcommand == RUNNER_RUFF_FORMAT:
        return bool(flags & RUNNER_RUFF_FORMAT_REPORT_FLAGS)
    if subcommand == RUNNER_RUFF_VERSION:
        return len(positionals) == 1
    return subcommand == RUNNER_RUFF_RULE and len(positionals) == RUNNER_RUFF_RULE_WORDS


def runner_form_allowed(runner, args, cwd, root):
    """The runner is allowlisted; this judges the FORM of the invocation. ruff, mypy and
    pytest are approved only in the exact words of their allowlists; `ruff --fix`, a bare
    `ruff format`, `mypy --python-executable`, `pytest --basetemp` and every flag that
    writes a file, installs a package or runs an interpreter are none of them the repo's
    own code running. The other runners (`npm run …`, `playwright test`) are as before."""
    if runner not in RUNNER_BARE_FLAGS:
        return True
    words = runner_words(runner, args, cwd, root)
    if words is None:
        return False
    return ruff_form_allowed(*words) if runner == RUNNER_RUFF else True


def runner_allowed(head, cwd, root):
    for prefix in RUNNER_PREFIXES:
        if len(head) >= len(prefix) and tuple(head[:len(prefix)]) == prefix:
            return runner_form_allowed(prefix[-1], head[len(prefix):], cwd, root)
    return False


def subcommand_allowed(parts, cwd, root):
    if not parts or any(all(ch in PUNCTUATION for ch in p) for p in parts):
        return False

    # An assignment at command position is an ENVIRONMENT PREFIX: bash runs the NEXT
    # word as the program. program_name() would take this word's basename instead, so
    # `X=/tmp/e/pytest src/a.py` read `src/a.py` as an argument to an allowlisted runner
    # while bash executed it. The analysis does not follow a prefix, so it refuses one.
    if ASSIGNMENT_RE.match(parts[0]):
        return False

    program_token = parts[0]
    prog = program_name(program_token)
    args = parts[1:]

    if prog == "cd":
        # A bare `cd` goes home; a relative target resolves somewhere we cannot see.
        return len(args) == 1 and args[0].startswith(os.sep) and inside(args[0], root)

    if program_token.startswith(os.sep) and not (
        lexically_inside(program_token, root) or inside(program_token, root)
    ):
        return False

    if prog == "sed":
        allowed, files = sed_allowed(args)
        return allowed and all(token_confined(a, cwd, root) for a in files)

    # Before the root check, and the only rule that reaches past it: the runners' own
    # per-pass scratch directory is under $TMPDIR by construction, so a script written
    # there can never be confined to the project root.
    if scratch_entry_allowed(prog, args, cwd, root):
        return True

    if not all(token_confined(a, cwd, root) for a in args):
        return False

    if harness_entry_allowed(program_token, prog, args, cwd, root):
        return True

    if prog == "git":
        if git_allowed(args):
            try:
                return read_uses_own_gitdir(args, cwd, root)
            except Exception:   # a read of the tree that fails approves nothing
                return False
        try:
            return own_push_allowed(args, cwd, root)
        except Exception:   # a probe that fails approves nothing
            return False
    if prog in READ_ONLY_PROGRAMS:
        return not any(flag_forbidden(prog, a) for a in args)
    return runner_allowed([prog] + args, cwd, root)


def expansion_allowed(parts, cwd, root):
    """Both the literal tokens and their brace expansion must pass: the literal pass
    keeps a quoted `'{-a,-v}'` from approving what its expansion would, and the expanded
    pass checks every word bash will see, including a `~` that only appears after
    expansion."""
    expanded = expanded_argv(parts)
    if not expanded or any(w.startswith(TILDE) for w in expanded):
        return False
    return subcommand_allowed(parts, cwd, root) and subcommand_allowed(expanded, cwd, root)


def quoted_separator_word(text):
    """True when a quoted or escaped word is nothing but operator characters (`';'`, `"|"`,
    `\\&`). Bash hands that to the program as an argument; shlex, with the quoting gone,
    reads it as a separator, so the words after it would be judged as a command of their
    own — `git push origin <current> ';' ls :main` allowed as two reads while bash runs one
    push of `:main` (the audit's bypass 1, self/features/orchestration-record-fixes/
    NOTES.md). Such a line is never approved; it goes to the human. The word is read the way
    shlex de-quotes it, so `'\\('` and `'\\|'` (a backslash, then the character: a grep
    pattern) are ordinary words and stay approved (the audit's F6)."""
    return any(isinstance(token, QuotedWord) for token in chain_tokens(text) or [])


def fails_closed(command):
    """The fail-closed rule: True when the line holds a git word and a `$(…)`, a backtick, a
    `<(`/`>(`, a `<<` (heredoc or herestring) or the word `case` — anywhere, quoted or not.
    Such a line is not read finely: it is never approved, and the deny side refuses only what
    `command_words`' one plain reading finds, so what that reading misses is a prompt. The
    outcome is a prompt rather than a rewrite deny so that `git commit -m "$(cat <<'EOF' …
    EOF)"` keeps working (self/features/orchestration-record-fixes/NOTES.md); a push names
    its branch as a literal (`git push -u origin <branch>`), and `git push -u origin "$(git
    branch --show-current)"` is this prompt locally and the cloud's push deny, which reads
    the words. The git word is looked for
    with quotes and backslashes deleted (`g""it`, `g\\it`); an over-match only prompts more."""
    if not GIT_WORD_RE.search(command.translate(GIT_WORD_DROPPED_CHARS)):
        return False
    return (any(marker in command for marker in FAIL_CLOSED_MARKERS)
            or bool(CASE_WORD_RE.search(command)))


def is_git_push(parts):
    """True when `parts`, as written or brace-expanded, is `git push …` with nothing between —
    the only spelling `own_push_allowed` approves."""
    for words in (parts, expanded_argv(parts) or []):
        if words and program_name(words[0]) == GIT_PROGRAM and words[1:2] == [GIT_PUSH]:
            return True
    return False


def command_allowed(command, cwd, root):
    if any(bad in command for bad in UNANALYSABLE):
        return False
    if fails_closed(command):
        return False
    stripped = HARMLESS_REDIRECT_RE.sub("", command)
    if shell_active_outside_quotes(stripped) or not braces_simple(stripped):
        return False
    if quoted_separator_word(stripped):
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
    # A cd is approved only on its own. Claude Code re-checks every path a hook-approved
    # command reads against the reads fence, which cannot follow a cd, so approving a
    # chain approves nothing: it stops for the human anyway, and the model is never told
    # the rewrite. Refusing it here sends every chain `chains_chdir` cannot judge to the
    # ordinary flow instead, whichever guard let it through.
    if len(groups) > 1 and any(parts[0] in CHDIR_PROGRAMS for parts in groups):
        return False
    # The own-branch push is a write, approved only as the whole command: one write per Bash
    # call, nothing else on the line (self/features/hook-silent-allow-sweep/, item 4)
    if len(groups) > 1 and any(is_git_push(parts) for parts in groups):
        return False
    for parts in groups:
        if not expansion_allowed(parts, cwd, root):
            return False
    return True


def names_build_script(word):
    """True when `word` contains one of BUILD_SCRIPTS literally (`./x/run-plans.sh`,
    `--exec=./run-plans.sh`, `R=run-plans.sh`)."""
    folded = word.lower()          # a case-insensitive filesystem runs ./Run-Plans.sh too
    return any(name in folded for name in BUILD_SCRIPTS)


def pattern_matches_build_script(word):
    """True when `word` names a build script or is a pattern — a glob, or a brace group or
    substitution, each read as `*`, a bracket expression read as `?` — whose last path
    component could match one."""
    if names_build_script(word):
        return True
    pattern = BUILD_SCRIPT_EXPANSION_RE.sub(BUILD_SCRIPT_WILDCARD, word)
    pattern = BUILD_SCRIPT_BRACKET_RE.sub(BUILD_SCRIPT_ANY_CHARACTER, pattern)
    if not any(ch in BUILD_SCRIPT_GLOB_CHARS for ch in pattern):
        return False
    tail = pattern.rsplit(os.sep, 1)[-1]
    return any(fnmatch.fnmatchcase(name, tail.lower()) for name in BUILD_SCRIPTS)


def mentions_build_script_pattern(word):
    """True when `word`, or a blank-separated piece of it (a `-c` script, an `alias.x=!…`
    value), names a build script or is a pattern that could expand to one — the pieces also
    tried as the value after a `=` (`GIT_EDITOR=run-p*.sh`, `--exec=run-p*.sh`) and with the
    quote, paren and brace characters that glue them to code stripped, and find's own `{}`
    left out (`pattern_matches_build_script` reads it as a glob)."""
    pieces = [word] + word.split()
    pieces += [piece.split(FLAG_VALUE_SEP, 1)[1] for piece in pieces if FLAG_VALUE_SEP in piece]
    pieces += [piece.strip(BUILD_SCRIPT_PIECE_STRIP) for piece in pieces]
    return any(piece != FIND_PLACEHOLDER and pattern_matches_build_script(piece)
               for piece in pieces)


def exempt_from_build_judge(words):
    """True for a command that launches nothing it names: a reader (without an exec flag),
    git's read and record subcommands (no global option before them, no flag that runs a
    program — spelled out, abbreviated as git accepts it (`--open=…`, `--receive=…`), or `-O`
    inside a cluster of short flags), gh's pr/issue/api/repo/release, `sed -n <addr>p <file…>`
    and `bash -n <file>`."""
    if not words:
        return True
    program, rest = os.path.basename(words[0]), words[1:]
    if program in BUILD_SCRIPT_READERS:
        return not any(w.startswith(BUILD_SCRIPT_READER_EXEC_FLAGS) for w in rest)
    if program == "git":
        return (bool(rest) and rest[0] in BUILD_SCRIPT_GIT_EXEMPT
                and not any(w.startswith(BUILD_SCRIPT_GIT_EXEC_FLAGS) for w in rest)
                and not orchestrator_option_hits(rest, BUILD_SCRIPT_GIT_EXEC_FLAGS,
                                                 BUILD_SCRIPT_GIT_EXEC_SHORT))
    if program == "gh":
        return bool(rest) and rest[0] in BUILD_SCRIPT_GH_EXEMPT
    if program == "sed":
        return (len(rest) >= 2 and rest[0] == SYNTAX_ONLY_FLAG
                and bool(SED_PRINT_ONLY_RE.match(rest[1]))
                and not any(w.startswith(OPTION_PREFIXES) for w in rest[2:]))
    if program in SYNTAX_ONLY_SHELLS:
        return rest[:1] == [SYNTAX_ONLY_FLAG] and files_only(rest[1:])
    return False


def launch_positions(words):
    """The words of a command that name a program to launch: its program, and every argument
    of a known launcher (`find`'s after -exec/-execdir/-ok/-okdir only)."""
    program = os.path.basename(words[0])
    if program not in BUILD_SCRIPT_LAUNCHERS:
        return words[:1]
    if program == "find":
        # Each -exec's command is a command of its own: judged like one, so `-exec grep -l x
        # {} ;` launches grep (a reader) and `-exec {} x ;` launches whatever {} expands to.
        launched, current, inside = [], [], False
        for word in words[1:] + [FIND_EXEC_END[0]]:
            if word in FIND_LAUNCH_FLAGS:
                inside, current = True, []
            elif inside and word in FIND_EXEC_END:
                if current and not exempt_from_build_judge(current):
                    launched.extend(launch_positions(current))
                inside, current = False, []
            elif inside:
                current.append(word)
        return words[:1] + launched
    return words


def fed_files(line):
    """The words an input redirect feeds a command on the line as a FILE — the target of a
    `<` or `<>`, its descriptor dropped (`chain_tokens`), comments and heredoc bodies left out
    (`judged_texts`, every reading). Empty when the line does not tokenize."""
    fed, feeds = [], False
    for token in [t for text in judged_texts(line) for t in (chain_tokens(text) or [])]:
        if is_operator_token(token):
            kind, operator = punctuation_pieces(token)[-1]
            feeds = kind == OPERATOR_KIND_REDIRECT and operator in REDIRECT_INPUT_FILE_OPS
        elif feeds:
            fed.append(token)
            feeds = False
    return fed


def invokes_build_script(command, as_written=False):
    """True when the line may run one of BUILD_SCRIPTS (the reading is set out above
    BUILD_SCRIPT_READERS). A line that does not tokenize even after its whole-argument
    heredocs are read as text, or another heredoc, is read as text with its quoting removed,
    any name in it a run.

    The line is judged twice, and is a run when either reading is one: with every line
    continuation deleted, as bash deletes it (`./run-pla\\⏎ns.sh` names the script;
    hook-audit-gaps, B), and `as_written` — inside a comment bash deletes none, so the line
    after `ls # x \\⏎` is a command, and deleting the break first hid it in the comment
    (escalations/01-audit-opus.md, E2). Which backslash sits in a comment is not asked."""
    if not as_written:
        return any(invokes_build_script(text, as_written=True) for text in
                   dict.fromkeys((command.replace(LINE_CONTINUATION, ""), command)))
    bodies = []
    token = secrets.token_hex(HEREDOC_TOKEN_BYTES)
    placeholder_re = re.compile(HEREDOC_PLACEHOLDER_RE_TEMPLATE % token)

    def keep_body(body):
        bodies.append(body)
        return "\"%s\"" % (HEREDOC_PLACEHOLDER % (token, len(bodies) - 1))

    line = replace_heredoc_arguments(command, keep_body)
    line = ANSI_C_QUOTE_RE.sub(BUILD_SCRIPT_WILDCARD, line)
    line = EXTGLOB_RE.sub(BUILD_SCRIPT_WILDCARD, line)
    # A heredoc left on the line is read as text, as `command_words` once refused it: that
    # reading stops at a heredoc's body, and a build script after the body would go unread
    # (round 9's audit: `cat <<EOF⏎x⏎EOF⏎./run-plans.sh …`). Only a real `<<` operator is one —
    # a quoted `'a<<'` or a `<<<` keeps the tokenized reading, which catches a glob the text
    # scan cannot (round 10's audit: `echo 'a<<' ; ./run-p*.sh`); a line that does not lex
    # takes the text scan
    tokens = chain_tokens(line)
    heredoc = tokens is None or any(is_heredoc_operator(t) for t in tokens)
    groups = None if heredoc else command_words(line)
    if groups is None:
        # The text scan reads a pattern as a run when it is the ANSI-C reading's, or when the
        # line holds no heredoc — a line that does not lex (`./run-p*.sh --self x \`, a quote
        # in a comment) is no reason to let a glob through (hook-audit-gaps, A and B); after a
        # real heredoc's body a glob is still not read (self/tests/hook-cloud-profile.sh, H4)
        patterns = bool(ANSI_C_QUOTE_RE.search(command)) or HEREDOC_OPERATOR not in command
        text = BUILD_SCRIPT_QUOTING_RE.sub("", ANSI_C_QUOTE_RE.sub(BUILD_SCRIPT_WILDCARD, command))
        # ... word by word, an operator ending a word as a blank does: `true;./run-p*.sh;true # '`
        return any(names_build_script(word) or (patterns and pattern_matches_build_script(word))
                   for word in BUILD_SCRIPT_TEXT_SPLIT_RE.split(text))

    def body_of(word):
        def body(match):
            index = int(match.group(1))
            return bodies[index] if index < len(bodies) else match.group(0)
        return placeholder_re.sub(body, word)

    # A file an input redirect FEEDS a command (`bash < run-plans.sh`, `<>`, `N<`, before the
    # program or after it) is read like a name in an exempt reader: text to `cat < run-plans.sh`
    # and `bash -n < run-plans.sh`, a run as soon as the line holds a command that may launch —
    # the same script piped in (`cat run-plans.sh | bash`) is the same run (hook-audit-gaps,
    # phase 3 (a)). `command_words` drops every redirect's target, so they are read here.
    named_in_exempt = any(mentions_build_script_pattern(w) for w in fed_files(line))
    launches = False
    for words in groups:
        words = list(words)
        assignments = []
        while words and ENV_ASSIGNMENT_RE.match(words[0]):
            assignments.append(words.pop(0))
        while words and words[0] in BUILD_SCRIPT_LEAD_KEYWORDS:
            words.pop(0)
        # GIT_EXTERNAL_DIFF=./run-plans.sh git diff — and a pattern, which the shell git hands
        # the value to expands: GIT_EDITOR='./run-p*.sh' git commit
        if any(mentions_build_script_pattern(w) for w in assignments):
            return True
        if not words:
            continue
        if exempt_from_build_judge(words):
            named_in_exempt = named_in_exempt or any(
                names_build_script(body_of(w)) or mentions_build_script_pattern(w) for w in words)
            continue
        # Any command that is neither exempt nor a plain filter may launch what a reader
        # beside it names: the launcher list cannot be complete on this side of a pipe either
        # (`cat run-plans.sh | unshare sh`, `| ash`, `| prlimit sh`; hook-audit-gaps, C)
        if words[0] not in BUILD_SCRIPT_FILTERS or any(
                w.startswith(BUILD_SCRIPT_FILTER_EXEC_FLAGS) for w in words[1:]):
            launches = True
        if any(names_build_script(body_of(w)) for w in words):
            return True
        if any(pattern_matches_build_script(w) for w in launch_positions(words)):
            return True
        # The coarse closure of the launcher denylist (hook-audit-gaps, C): a command this
        # list does not know (`unshare`, `setpriv`, `prlimit`, awk's `system()`, sed's `e`,
        # `git -c alias.x=!…`) can run anything it is handed, so a pattern for a build script in
        # ANY argument of a non-exempt command is a run. This judge speaks only for a checkout
        # whose orchestrator ledger cannot be read, where every session is already refused
        # building; hooks/README.md → "The orchestrator role" names what it over-denies.
        if any(mentions_build_script_pattern(w) for w in words):
            return True
    return named_in_exempt and launches


def orchestrator_record(payload):
    """The orchestration record path that makes this payload's session an orchestrator (the
    record under THIS checkout's agentTooling, orchestrator_role.record_for_session's three
    sources), orchestrator_role.LEDGER_UNREADABLE when that cannot be told, or None. Silent
    without the module or a session id; any failure reading it is no record."""
    session = payload.get(SESSION_FIELD)
    if orchestrator_role is None or not isinstance(session, str) or not session:
        return None
    tooling = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    try:
        return orchestrator_role.record_for_session(tooling, session)
    except Exception:  # a rule that cannot be read is never a deny
        return None


def orchestrator_reason(payload):
    """The orchestrator-role reason when this payload's session is an orchestrator, else
    None (orchestrator_record)."""
    record = orchestrator_record(payload)
    try:
        return orchestrator_role.refusal_reason(record) if record else None
    except Exception:
        return None


# ── The orchestrator allowlist (security audit round 3; hooks/README.md → "The orchestrator
# role") ───────────────────────────────────────────────────────────────────────
# An orchestrator session runs only these shapes. Every command on the line — a pipeline or
# a `&&` / `||` / `;` list — must match one; anything else is denied with the role reason and
# this list. Every word must be a plain literal: no `$`, backtick, glob, brace, tilde,
# backslash, process substitution or redirect outside quotes, except `2>&1` and `> /dev/null`.
# Two expansions are recognised BY THE TOKENIZER, never by a search of the raw line (round 4
# of the audit's findings, R1): a quoted-delimiter heredoc substitution and the quoted
# `"$(git branch --show-current)"`, each only where an unquoted `"` starts a fresh word and the
# closing `)"` ends it, and each standing as one placeholder word, valid only as a commit
# message / PR title or body and as the pushed branch.
ORCHESTRATOR_READERS = frozenset([
    "ls", "cat", "head", "tail", "wc", "grep", "rg", "find", "sed", "stat", "du", "jq",
    "diff", "sort", "uniq", "cut", "tr", "date", "pwd", "echo", "printf",
])
# Reader options that run a program, write a file, read a program from one, or never end:
# (long options, matched by any unique prefix; short letters, matched in any cluster)
ORCHESTRATOR_READER_FORBIDDEN = {
    "rg": (("--pre", "--hostname-bin", "--search-zip"), "z"),
    "jq": (("--from-file",), "f"),
    "sort": (("--output", "--compress-program"), "o"),
    "date": (("--set",), "s"),
    "tail": (("--follow", "--pid"), "fF"),
    "diff": (("--paginate",), "l"),
    # bash's printf builtin: `-v NAME` assigns, and a subscripted NAME (`x[$(cmd)]`) is
    # evaluated arithmetically, which runs the substitution (security audit round 4)
    "printf": ((), "v"),
}
# The other allowlisted readers that are bash builtins — `echo` (-n/-e/-E only) and `pwd`
# (-L/-P only) — evaluate no option or argument as arithmetic or code; printf's FORMAT and
# ARGUMENTS are not evaluated either (`%d` takes a plain number). See the feature's NOTES.md.
ORCHESTRATOR_FIND_FORBIDDEN = frozenset(["-exec", "-execdir", "-ok", "-okdir", "-delete",
                                         "-fprint", "-fprint0", "-fprintf", "-fls"])
ORCHESTRATOR_UNIQ_MAX_PATHS = 1
# date: options whose value is the next word, and the one operand that only reads
ORCHESTRATOR_DATE_VALUE_SHORT = "dfr"
# GNU date's one short option with an optional attached argument (`d:f:I::r:Rs:u`)
ORCHESTRATOR_DATE_OPTIONAL_ATTACHED = "I"
ORCHESTRATOR_DATE_VALUE_LONG = ("--date", "--file", "--reference")
ORCHESTRATOR_DATE_FORMAT_PREFIX = "+"
ORCHESTRATOR_SED_PRINT_RE = re.compile(r"^[0-9]+(,[0-9]+)?p$")
ORCHESTRATOR_SED_FLAG = "-n"
ORCHESTRATOR_END_OF_OPTIONS = "--"
ORCHESTRATOR_STDIN_OPERAND = "-"
# git: the subcommand comes first (no global option, no GIT_* prefix), and none of these
# options, by any unique prefix, nor `-O` in a short cluster, nor a `%G` signature format
ORCHESTRATOR_GIT_READ = frozenset(["status", "log", "diff", "show", "rev-parse", "ls-files"])
ORCHESTRATOR_GIT_EXACT = {"branch": ["--show-current"], "remote": ["-v"], "worktree": ["list"]}
ORCHESTRATOR_GIT_FORBIDDEN_LONG = ("--ext-diff", "--textconv", "--output",
                                   "--open-files-in-pager", "--upload-pack", "--receive-pack",
                                   "--exec", "--run", "--show-signature")
ORCHESTRATOR_GIT_FORBIDDEN_SHORT = "O"
ORCHESTRATOR_GIT_SIGNATURE_FORMAT = "%G"
ORCHESTRATOR_LONG_PREFIX_MIN = 3        # `--x`: the shortest prefix git would accept
ORCHESTRATOR_REMOTE = "origin"
# A branch name as push and fetch take it: no refspec (`+`, `:`), no glob, no `..` (R3)
ORCHESTRATOR_BRANCH_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")
ORCHESTRATOR_BRANCH_FORBIDDEN = ".."
# A path `git add` refuses: one holding a `.git` entry (a planted repository whose config
# git would honour, R7)
GIT_DIR_ENTRY = ".git"
GIT_PATHSPEC_MAGIC = ":"
ORCHESTRATOR_GLOB_CHARS = frozenset("*?[")
# `git mv` of the session's OWN record from the old vendored place to the consuming repo's
# records folder, the move shared_rules.LEGACY_RECORD_REFUSAL names, and nothing else
# (self/features/orchestration-start-branch-v2/): exactly two operands, run from the consuming
# repo's root, the source the vendored `<tooling>/self/orchestrations/<slug>` holding the record
# that names this session, the destination `plans/orchestrations/<slug>`, not yet there, and no
# symlink anywhere on the record's own path or the destination's parents (round 1's audit: a
# symlinked `plans` moved the record out of the repository, a symlinked README named another
# session's directory). That one shape is approved outright — alone, or after exactly
# `shared_rules.LEGACY_RECORD_MKDIR &&` (git tracks no empty directory, so the folder may not
# exist yet; round 1's review) — and any other `git mv` is the allowlist denial.
ORCHESTRATOR_MOVE_SUB = "mv"
ORCHESTRATOR_MOVE_OPERANDS = 2
ORCHESTRATOR_MOVE_MKDIR_LEAD = (shared_rules.LEGACY_RECORD_MKDIR + " && "
                                if shared_rules is not None else None)
ORCHESTRATOR_MOVE_REASON = (
    "allow-repo-commands: the orchestrator's move of its own record from the old vendored "
    "place to the consuming repo's records folder")
# ... and the source must BE that record, read at judgment time (a consuming repo's
# propagation audit of #169, B1; self/features/orchestrator-record-move-guard/): the role
# lookup's slug can come from the ledger alone, which reads no record. So the folder's
# README must be a regular file, no symlink, naming THIS session as an orchestrator
# (orchestrator_role.names_role), and the record must be the consuming repo's stranded one,
# not agentTooling's shipped one — analysis/roots.py's is_stranded_record, asked through
# the CLI orchestration-start.sh asks (`roots.py stranded <slug>`, exit 0 for stranded),
# because the hook imports nothing from analysis/. `-E -s` keeps PYTHON* variables and the
# user site out of it, and `-B` writes no bytecode. A missing or symlinked classifier, a
# non-zero exit, a timeout or any failure means no approval.
ORCHESTRATOR_MOVE_CLASSIFIER = ("analysis", "roots.py")
ORCHESTRATOR_MOVE_CLASSIFIER_ARGV = "stranded"
ORCHESTRATOR_MOVE_PYTHON_FLAGS = ("-B", "-E", "-s")
ORCHESTRATOR_MOVE_STRANDED_RC = 0
ORCHESTRATOR_MOVE_CLASSIFIER_TIMEOUT_SECONDS = 15
# gh
ORCHESTRATOR_GH_PR_READ = frozenset(["view", "list", "checks"])
ORCHESTRATOR_GH_FORBIDDEN_LONG = ("--web", "--watch", "--repo")
ORCHESTRATOR_GH_FORBIDDEN_SHORT = "wR"
ORCHESTRATOR_GH_PR_CREATE_FIELDS = ("--title", "--body")
# The orchestration entry points: resolved against the command's cwd and required to BE this
# hook's own tooling files (R2), so a planted `analysis/report.py` elsewhere is not one
ORCHESTRATOR_SCRIPTS = ("orchestration-start.sh", "orchestration-capture.sh")
ORCHESTRATOR_START_SCRIPT = "orchestration-start.sh"
ORCHESTRATOR_START_FORBIDDEN = "--session"
ORCHESTRATOR_PYTHON = "python3"
ORCHESTRATOR_PYTHON_FLAGS = frozenset(["-B"])
ORCHESTRATOR_MANIFEST = "analysis/manifest.py"
ORCHESTRATOR_MANIFEST_SCOPE = "--orchestration"
ORCHESTRATOR_REPORT = "analysis/report.py"
ORCHESTRATOR_REPORT_SCOPE = "--orchestration"
ORCHESTRATOR_REPORT_CHECKOUT = "--checkout"
# The record tools' mode word (self/features/orchestration-records-in-repo/, rulings 2 and 8):
# `manifest.py --self --orchestration …` and `report.py --self --orchestration <slug>` read
# agentTooling's own `self/orchestrations/`, the no-flag form the consuming repo's
# `plans/orchestrations/`. Admitted once, as the first argument only — the spelling the docs
# and the start's next steps print.
ORCHESTRATOR_SELF_FLAG = ENTRY_SELF_FLAG
# The slug is the lifecycle's one pattern (shared_rules.SLUG_RE). With no shared_rules.py the
# pattern matches nothing, so a record tool is handed to the human rather than approved.
ORCHESTRATOR_SLUG_RE = ENTRY_SLUG_RE
# manifest.py [--self] --orchestration <slug> <subcommand> <operands>: no word after the
# scope's own may be a flag (python-entry-exact: `--orchestration a --orchestration=b …`
# hands argparse the last one)
ORCHESTRATOR_MANIFEST_ONE_OPERAND = frozenset(["get", "set-window-to"])
ORCHESTRATOR_MANIFEST_PAIRS = frozenset(["add-feature", "set-feature"])
# capture_planning.py in the plain session's exact listing shape (capture_listing_shape)
ORCHESTRATOR_CAPTURE = "analysis/capture_planning.py"
# The line, read
ORCHESTRATOR_MAX_LINE_CHARS = 20000     # past this the line is refused unread (R1)
ORCHESTRATOR_HARMLESS_REDIRECT_RE = re.compile(r"(?<!\S)(?:2>&1|>\s*/dev/null)(?!\S)")
ORCHESTRATOR_BRANCH_SUBSTITUTION = "\"$(git branch --show-current)\""
ORCHESTRATOR_WORD_END = " \t|;&"
ORCHESTRATOR_PLACEHOLDER = "__orchestrator_%s_%s__"
ORCHESTRATOR_TOKEN_BYTES = 8
ORCHESTRATOR_UNQUOTED_FORBIDDEN = frozenset("$`*?[]{}\\<>()&#")
# Unquoted only at a word's start: tilde expansion, `!` negation; and an assignment word
# (`NAME=…`, a GIT_* prefix included) standing first in a command
ORCHESTRATOR_WORD_START_FORBIDDEN = frozenset("~!")
ORCHESTRATOR_QUOTED_FORBIDDEN = frozenset("$`\\")
ORCHESTRATOR_ALLOWLIST_TEXT = (
    "an orchestrator session runs only: readers (ls, cat, head, tail, wc, grep, rg, find, "
    "sed -n '<N>p', stat, du, jq, diff, sort, uniq, cut, tr, date, pwd, echo, printf) over "
    "literal paths; git status|log|diff|show|rev-parse|ls-files, git branch --show-current, "
    "git remote -v, git worktree list, git fetch origin <branch>, git add <paths>, "
    "[mkdir -p plans/orchestrations && ] git mv <tooling>/self/orchestrations/<slug> "
    "plans/orchestrations/<slug> of this session's own record from the consuming repo's root, "
    "git commit "
    "-m \"<literal>\" or -m \"$(cat <<'EOF' … EOF)\", git push -u origin <branch> with the "
    "branch's name written out — no global git options; gh pr create --title … --body …, "
    "gh pr view|list|checks; this checkout's own orchestration-start.sh, "
    "orchestration-capture.sh, analysis/manifest.py [--self] --orchestration …, "
    "analysis/report.py [--self] --orchestration <slug>, analysis/capture_planning.py --list-sessions|--list-subagents; "
    "joined by |, &&, || or ;, every word a plain literal, no redirect but 2>&1 and > "
    "/dev/null. Any other work goes to a SEPARATE session (create_session, or send_message "
    "to an implementer session) or to the human — an in-process subagent shares this "
    "session's id, so it has the Read, Grep and Edit tools but this same Bash list")


def orchestrator_words(line, token):
    """(commands, heredocs, branch) for the line, or None when some word is not a plain
    literal. Each command is a list of words; `heredocs` the placeholder words standing for
    quoted-delimiter heredoc substitutions, `branch` the one standing for
    `"$(git branch --show-current)"` — still read as a pushed branch here, but not the push
    the allowlist's text or the docs name: the push rules judge the words, so in the cloud
    that spelling is refused as a push of another ref, and the documented push is `git push
    -u origin <branch>` with the name written out. Single quotes are literal; double quotes
    may hold no
    `$`, backtick or backslash; outside quotes a word holds none of
    ORCHESTRATOR_UNQUOTED_FORBIDDEN; separators split commands; a newline outside a quote or
    an expansion is refused. An expansion is recognised only where an unquoted `"` begins a
    fresh word and its closing `)"` is followed by the end, a blank or a separator (R1)."""
    commands, words, word, i = [], [], None, 0
    heredocs, branch = set(), ORCHESTRATOR_PLACEHOLDER % (token, "branch")

    def end_word():
        nonlocal word
        if word is not None:
            words.append(word)
        word = None

    def ends_word(at):
        return at == len(line) or line[at] in ORCHESTRATOR_WORD_END

    while i < len(line):
        ch = line[i]
        if ch == '"' and word is None:
            if line.startswith(ORCHESTRATOR_BRANCH_SUBSTITUTION, i):
                end = i + len(ORCHESTRATOR_BRANCH_SUBSTITUTION)
                if not ends_word(end):
                    return None
                word, i = branch, end
                continue
            expansion = heredoc_argument_at(line, i, strict=True)
            if expansion:
                if not ends_word(expansion[1]):
                    return None
                word = ORCHESTRATOR_PLACEHOLDER % (token, len(heredocs))
                heredocs.add(word)
                i = expansion[1]
                continue
        if word in heredocs or word == branch:
            return None          # an expansion is a whole word: nothing may follow it
        if ch == "'":
            close = line.find("'", i + 1)
            if close < 0:
                return None
            word = (word or "") + line[i + 1:close]
            i = close + 1
            continue
        if ch == '"':
            close = line.find('"', i + 1)
            if close < 0:
                return None
            inner = line[i + 1:close]
            if any(c in ORCHESTRATOR_QUOTED_FORBIDDEN for c in inner):
                return None
            word = (word or "") + inner
            i = close + 1
            continue
        if ch in " \t":
            end_word()
            i += 1
            continue
        if ch == "\n":
            return None
        two = line[i:i + 2]
        if two in ("&&", "||") or ch in "|;":
            end_word()
            if not words:
                return None
            commands.append(words)
            words = []
            i += 2 if two in ("&&", "||") else 1
            continue
        if ch in ORCHESTRATOR_UNQUOTED_FORBIDDEN or \
                (word is None and ch in ORCHESTRATOR_WORD_START_FORBIDDEN):
            return None
        word = (word or "") + ch
        i += 1
    end_word()
    if words:
        commands.append(words)
    elif commands:
        return None              # a trailing separator
    return commands, heredocs, branch


def orchestrator_option_hits(words, forbidden_long, forbidden_short):
    """True when some option word is a forbidden long option or a unique-prefix of one
    (`--out` for `--output`), or a short cluster holding a forbidden letter. Words after a
    `--` are operands, not options."""
    for word in words:
        if word == ORCHESTRATOR_END_OF_OPTIONS:
            return False
        if word.startswith("--"):
            name = word.split("=", 1)[0]
            if len(name) >= ORCHESTRATOR_LONG_PREFIX_MIN and any(f.startswith(name) or name.startswith(f)
                                                                 for f in forbidden_long):
                return True
        elif word.startswith("-") and len(word) > 1 and forbidden_short and \
                any(letter in word[1:] for letter in forbidden_short):
            return True
    return False


def is_orchestrator_operand(word):
    """True for an operand: a word not starting with `-`, or the bare `-` (stdin, an input
    operand — feature review round 1, B1: `uniq - OUT` named one operand and wrote OUT)."""
    return word == ORCHESTRATOR_STDIN_OPERAND or not word.startswith("-")


def orchestrator_operands(words):
    """The words that are operands: is_orchestrator_operand ones before a `--`, and every word
    after it (R7: `uniq -- - -out` names an output file)."""
    if ORCHESTRATOR_END_OF_OPTIONS in words:
        at = words.index(ORCHESTRATOR_END_OF_OPTIONS)
        return [w for w in words[:at] if is_orchestrator_operand(w)] + words[at + 1:]
    return [w for w in words if is_orchestrator_operand(w)]


def orchestrator_reader_allowed(words):
    program, rest = words[0], words[1:]
    if program in ORCHESTRATOR_READER_FORBIDDEN:
        forbidden_long, forbidden_short = ORCHESTRATOR_READER_FORBIDDEN[program]
        if orchestrator_option_hits(rest, forbidden_long, forbidden_short):
            return False
    if program == "find":
        return not any(w in ORCHESTRATOR_FIND_FORBIDDEN or w.startswith("-fprint") for w in rest)
    if program == "sed":
        return (len(rest) >= 2 and rest[0] == ORCHESTRATOR_SED_FLAG
                and bool(ORCHESTRATOR_SED_PRINT_RE.match(rest[1]))
                and not any(w.startswith(OPTION_PREFIXES) for w in rest[2:]))
    if program == "uniq":
        return len(orchestrator_operands(rest)) <= ORCHESTRATOR_UNIQ_MAX_PATHS
    if program == "date":
        return orchestrator_date_reads_only(rest)
    return True


def orchestrator_date_reads_only(args):
    """True when `date` only reads the clock: every operand is a `+FORMAT`, the values of
    -d/--date, -f/--file and -r/--reference taken as theirs (lifecycle round 2's audit, A2:
    GNU date's `MMDDhhmm[[CC]YY][.ss]` operand SETS the clock, like `-s`)."""
    takes_value = False
    for word in args:
        if takes_value:
            takes_value = False
            continue
        if word.startswith("--"):
            name = word.split("=", 1)[0]
            if "=" not in word and any(o.startswith(name) for o in ORCHESTRATOR_DATE_VALUE_LONG) \
                    and len(name) >= ORCHESTRATOR_LONG_PREFIX_MIN:
                takes_value = True
            continue
        if word.startswith("-") and len(word) > 1:
            letters = word[1:]
            for at, letter in enumerate(letters):
                # `-I` takes the rest of the word as its OPTIONAL argument (`-Id` is
                # `--iso-8601=date`), so nothing after it is an option that takes the next word
                # (lifecycle round 3's audit, C1: `date -Id MMDDhhmm` set the clock)
                if letter in ORCHESTRATOR_DATE_OPTIONAL_ATTACHED:
                    takes_value = False
                    break
                if letter in ORCHESTRATOR_DATE_VALUE_SHORT:
                    takes_value = at == len(letters) - 1
                    break
            continue
        if not word.startswith(ORCHESTRATOR_DATE_FORMAT_PREFIX):
            return False
    return True


def orchestrator_branch_word(word, branch):
    """A pushable or fetchable branch: the branch substitution, or a plain branch name (R3)."""
    return word == branch or (bool(ORCHESTRATOR_BRANCH_RE.match(word))
                              and ORCHESTRATOR_BRANCH_FORBIDDEN not in word)


def orchestrator_stranded_own_record(legacy, slug, session, tooling, consumer):
    """True when the vendored record folder `legacy` (`<tooling>/self/orchestrations/<slug>`,
    already checked to be a real directory) holds a README that is a regular file, no symlink,
    naming `session` as an orchestrator, and the consuming repo's stranded record by
    analysis/roots.py's classifier (ORCHESTRATOR_MOVE_CLASSIFIER). Anything else, a failure
    included, is False."""
    if not isinstance(session, str) or not session:
        return False
    readme = os.path.join(legacy, orchestrator_role.RECORD_NAME)
    if os.path.islink(readme) or not os.path.isfile(readme) or \
            not orchestrator_role.names_role(readme, session):
        return False
    classifier = os.path.join(tooling, *ORCHESTRATOR_MOVE_CLASSIFIER)
    if os.path.islink(classifier) or not os.path.isfile(classifier) or not sys.executable:
        return False
    try:
        done = subprocess.run((sys.executable,) + ORCHESTRATOR_MOVE_PYTHON_FLAGS +
                              (classifier, ORCHESTRATOR_MOVE_CLASSIFIER_ARGV, slug),
                              stdin=subprocess.DEVNULL, capture_output=True, cwd=consumer,
                              timeout=ORCHESTRATOR_MOVE_CLASSIFIER_TIMEOUT_SECONDS)
    except (OSError, subprocess.SubprocessError, ValueError):
        return False
    return done.returncode == ORCHESTRATOR_MOVE_STRANDED_RC


def orchestrator_record_move(args, cwd, record, session=None):
    """True when `args` — the words after `git mv` — are exactly the move of `record`, this
    session's own record, out of a vendored copy's `self/orchestrations/<slug>` into the
    consuming repo's `plans/orchestrations/<slug>`, from that repo's root
    (ORCHESTRATOR_MOVE_SUB). False in a standalone checkout (its records stay where they are),
    for a record found anywhere else, for any other source, destination or word, a source that
    is a symlink or no directory, and a destination already there. The record's path is taken
    as the role lookup returned it, never resolved: it and every directory above it must be no
    symlink (round 1's audit, M71), and the destination's parents must resolve to themselves —
    no symlinked `plans` or `plans/orchestrations` (M65, M66, M72). Last, the folder must
    really hold `session`'s stranded record (orchestrator_stranded_own_record): the role
    lookup may name the slug from the ledger alone, which reads no record (B1: another
    session's record, agentTooling's shipped one, an empty folder)."""
    if len(args) != ORCHESTRATOR_MOVE_OPERANDS or not cwd or not isinstance(record, str) \
            or orchestrator_role is None or record == orchestrator_role.LEDGER_UNREADABLE:
        return False
    tooling = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    if os.path.lexists(os.path.join(tooling, GIT_DIR_ENTRY)):
        return False
    consumer = os.path.dirname(tooling)
    if os.path.realpath(cwd) != consumer:
        return False
    record_path = os.path.abspath(record)
    if os.path.realpath(record_path) != record_path:
        return False
    record_dir = os.path.dirname(record_path)
    slug = os.path.basename(record_dir)
    legacy = os.path.join(tooling, *orchestrator_role.ORCHESTRATIONS_SELF_REL.split("/"), slug)
    if not ORCHESTRATOR_SLUG_RE.fullmatch(slug) or record_dir != legacy:
        return False
    source = os.path.relpath(legacy, consumer).replace(os.sep, "/")
    destination = "/".join([orchestrator_role.ORCHESTRATIONS_CONSUMER_REL, slug])
    if list(args) != [source, destination]:
        return False
    records_root = os.path.join(consumer, *orchestrator_role.ORCHESTRATIONS_CONSUMER_REL.split("/"))
    return (os.path.isdir(legacy)
            and os.path.realpath(legacy) == legacy
            and os.path.realpath(records_root) == records_root
            and not os.path.lexists(os.path.join(records_root, slug))
            and orchestrator_stranded_own_record(legacy, slug, session, tooling, consumer))


def orchestrator_moves_own_record(command, cwd, record, session=None):
    """True when the whole line is `git mv` with exactly the operands orchestrator_record_move
    admits, alone or after exactly ORCHESTRATOR_MOVE_MKDIR_LEAD (the remedy
    shared_rules.LEGACY_RECORD_MOVE prints) — the one orchestrator write the hook approves
    outright."""
    line = ORCHESTRATOR_HARMLESS_REDIRECT_RE.sub(" ", command).strip()
    if ORCHESTRATOR_MOVE_MKDIR_LEAD and line.startswith(ORCHESTRATOR_MOVE_MKDIR_LEAD):
        line = line[len(ORCHESTRATOR_MOVE_MKDIR_LEAD):]
    read = orchestrator_words(line, secrets.token_hex(ORCHESTRATOR_TOKEN_BYTES))
    if not read or len(read[0]) != 1:
        return False
    words = read[0][0]
    return words[:2] == ["git", ORCHESTRATOR_MOVE_SUB] and \
        orchestrator_record_move(words[2:], cwd, record, session)


def orchestrator_git_allowed(words, heredocs, branch, cwd, record=None, session=None):
    rest = words[1:]
    if not rest:
        return False
    sub, args = rest[0], rest[1:]
    if any(w in heredocs or w == branch for w in args) and sub not in ("commit", "push"):
        return False
    if orchestrator_option_hits(args, ORCHESTRATOR_GIT_FORBIDDEN_LONG, ORCHESTRATOR_GIT_FORBIDDEN_SHORT):
        return False
    if any(ORCHESTRATOR_GIT_SIGNATURE_FORMAT in w for w in args):
        return False
    if sub in ORCHESTRATOR_GIT_READ:
        return True
    if sub in ORCHESTRATOR_GIT_EXACT:
        return args == ORCHESTRATOR_GIT_EXACT[sub]
    if sub == "fetch":
        return (len(args) == 2 and args[0] == ORCHESTRATOR_REMOTE
                and args[1] != branch and orchestrator_branch_word(args[1], branch))
    if sub == "add":
        # Each argument an existing regular file, named plainly (lifecycle round 2's audit,
        # A1): pathspec magic (`:/sub`), a glob (`'s*'`, quoted or not) or a directory could
        # stage a planted nested repository, whose config `git status` then honours.
        if not args or not cwd:
            return False
        return all(not w.startswith(("-", GIT_PATHSPEC_MAGIC))
                   and not any(c in ORCHESTRATOR_GLOB_CHARS for c in w)
                   and GIT_DIR_ENTRY not in w.split(os.sep)
                   and not os.path.islink(os.path.join(cwd, w))
                   and os.path.isfile(os.path.join(cwd, w)) for w in args)
    if sub == ORCHESTRATOR_MOVE_SUB:
        # The record move is approved only as the whole line (orchestrator_moves_own_record,
        # checked before this loop); a `git mv` read here is on a line that is not that, so it
        # is the allowlist denial, as on the base (own-push-transport-keys, orchestrator addendum)
        return False
    if sub == "commit":
        return len(args) == 2 and args[0] == "-m" and args[1] != branch
    if sub == "push":
        return (len(args) == 3 and args[:2] == ["-u", ORCHESTRATOR_REMOTE]
                and args[2] not in heredocs and orchestrator_branch_word(args[2], branch))
    return False


def orchestrator_gh_allowed(words, heredocs, branch):
    rest = words[1:]
    if len(rest) < 2 or rest[0] != "pr" or branch in rest:
        return False
    action, args = rest[1], rest[2:]
    if action in ORCHESTRATOR_GH_PR_READ:
        return not any(w in heredocs for w in args) and \
            not orchestrator_option_hits(args, ORCHESTRATOR_GH_FORBIDDEN_LONG,
                                         ORCHESTRATOR_GH_FORBIDDEN_SHORT)
    if action != "create" or len(args) % 2:
        return False
    fields = dict(zip(args[0::2], args[1::2]))
    return (sorted(fields) == sorted(ORCHESTRATOR_GH_PR_CREATE_FIELDS)
            and len(fields) * 2 == len(args))


def orchestrator_tooling_file(word, cwd, name):
    """True when `word`, resolved against `cwd`, IS this hook's own `<tooling>/<name>` (R2) —
    and is no symlink itself (round 4: a link resolves to the real script, which would then
    source its library through the link's own directory)."""
    if not cwd or not word or os.path.islink(os.path.join(cwd, word)):
        return False
    tooling = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    return os.path.realpath(os.path.join(cwd, word)) == os.path.realpath(os.path.join(tooling, name))


def orchestrator_tool_allowed(words, cwd):
    for name in ORCHESTRATOR_SCRIPTS:
        if words[0].startswith("./") and orchestrator_tooling_file(words[0], cwd, name):
            return not (name == ORCHESTRATOR_START_SCRIPT and ORCHESTRATOR_START_FORBIDDEN in words[1:])
    if words[0] != ORCHESTRATOR_PYTHON:
        return False
    rest = list(words[1:])
    while rest and rest[0] in ORCHESTRATOR_PYTHON_FLAGS:
        rest.pop(0)
    if not rest:
        return False
    script, args = rest[0], rest[1:]
    if args[:1] == [ORCHESTRATOR_SELF_FLAG] and (
            orchestrator_tooling_file(script, cwd, ORCHESTRATOR_MANIFEST) or
            orchestrator_tooling_file(script, cwd, ORCHESTRATOR_REPORT)):
        args = args[1:]
    if orchestrator_tooling_file(script, cwd, ORCHESTRATOR_MANIFEST):
        if args[:1] != [ORCHESTRATOR_MANIFEST_SCOPE] or len(args) < 4 or \
                not ORCHESTRATOR_SLUG_RE.fullmatch(args[1]) or \
                any(w.startswith(FLAG_PREFIX) for w in args[3:]):
            return False
        if args[2] in ORCHESTRATOR_MANIFEST_ONE_OPERAND:
            return len(args) == 4
        return args[2] in ORCHESTRATOR_MANIFEST_PAIRS
    if orchestrator_tooling_file(script, cwd, ORCHESTRATOR_REPORT):
        if args[:1] != [ORCHESTRATOR_REPORT_SCOPE] or len(args) < 2 or \
                not ORCHESTRATOR_SLUG_RE.match(args[1]):
            return False
        extra = args[2:]
        return (len(extra) % 2 == 0
                and all(flag == ORCHESTRATOR_REPORT_CHECKOUT for flag in extra[0::2])
                and not any(value.startswith(FLAG_PREFIX) for value in extra[1::2]))
    if orchestrator_tooling_file(script, cwd, ORCHESTRATOR_CAPTURE):
        return capture_listing_shape(args)
    return False


def orchestrator_command_allowed(command, cwd=None, record=None, session=None):
    """True when every command on the line is one of the orchestrator's shapes (the table
    above), read by orchestrator_words with a per-call random token for its placeholders.
    `record` is the session's own record, the one path a `git mv` may name, and `session` the
    id that record must name; the move's line (orchestrator_moves_own_record) is admitted
    whole, its `mkdir -p` lead included — no other `mkdir` is on the list."""
    if len(command) > ORCHESTRATOR_MAX_LINE_CHARS:
        return False
    if orchestrator_moves_own_record(command, cwd, record, session):
        return True
    line = ORCHESTRATOR_HARMLESS_REDIRECT_RE.sub(" ", command)
    read = orchestrator_words(line, secrets.token_hex(ORCHESTRATOR_TOKEN_BYTES))
    if not read or not read[0]:
        return False
    commands, heredocs, branch = read
    for words in commands:
        program = words[0]
        if ENV_ASSIGNMENT_RE.match(program):
            return False
        if program in ORCHESTRATOR_READERS:
            if any(w in heredocs or w == branch for w in words) or \
                    not orchestrator_reader_allowed(words):
                return False
        elif program == "git":
            if not orchestrator_git_allowed(words, heredocs, branch, cwd, record, session):
                return False
        elif program == "gh":
            if not orchestrator_gh_allowed(words, heredocs, branch):
                return False
        elif any(w in heredocs or w == branch for w in words) or \
                not orchestrator_tool_allowed(words, cwd):
            return False
    return True


def orchestrator_allowlist_reason(record):
    """The deny for a command outside the allowlist: the role's own reason, then the list."""
    try:
        role = orchestrator_role.refusal_reason(record)
    except Exception:
        role = ""
    return "allow-repo-commands: %s — and %s." % (role, ORCHESTRATOR_ALLOWLIST_TEXT)


def unreadable_ledger_refuses(command):
    """True when the RAW command holds any of UNREADABLE_LEDGER_MARKERS — read before any
    rewrite, so no heredoc placeholder, ANSI-C or extglob substitution can hide one, and again
    with every line continuation deleted, so none splits one (`$\\⏎(`, `<\\⏎<`). Each of
    rounds 12 and 13 met a finer build-script reading with a new spelling; on a checkout whose
    ledger cannot be read, such a line is refused outright instead."""
    return any(marker in text for marker in UNREADABLE_LEDGER_MARKERS
               for text in (command, command.replace(LINE_CONTINUATION, "")))


def build_script_denial(command, payload):
    """The orchestrator-role reason for a command that runs a build script, else None. Since
    the allowlist (round 3) an orchestrator never reaches this: main() calls it only for a
    checkout whose role cannot be read (LEDGER_UNREADABLE), where every session is refused
    building and nothing else — the name-matching reading below is that deny. A reading that
    FAILS is a run for a session with a record (security audit round 2, N4: the caller
    treats an exception as no deny, so the failure must be decided here). A raw command
    holding a substitution, a heredoc or a quoting/expansion form is refused before any
    reading (`unreadable_ledger_refuses`): finer readings on this path are out of scope by
    design (self/features/orchestration-record-fixes/NOTES.md, rounds 12-13)."""
    if unreadable_ledger_refuses(command):
        return UNREADABLE_LEDGER_REASON
    try:
        runs = invokes_build_script(command)
    except Exception:
        runs = True
    return orchestrator_reason(payload) if runs else None


def judge_agent(payload):
    """An `Agent` call. First the orchestrator role: denied when the session is an
    orchestrator and the prompt opens with an implementer brief, with the role's reason.
    Then the brief header: denied when the prompt's first non-empty line is not a header
    (brief_header.py), naming the line to put first. A call with no string prompt is not
    judged; otherwise nothing is printed (never an allow).

    The prompt is parsed once, and both rules read that one parse: an implementer brief is
    a `feature: <repo>/<slug>` header, so `feature: none — <reason>` — the form an
    orchestrator's own analysis delegates carry — is not one, and a header behind leading
    blank lines is one for the role check exactly as it is for the header check. Without
    brief_header.py the role check falls back to the bare marker at the prompt's start and
    the header check is skipped."""
    tool_input = payload.get("tool_input")
    prompt = tool_input.get(AGENT_PROMPT_FIELD) if isinstance(tool_input, dict) else None
    if not isinstance(prompt, str):
        return
    header = brief_header.parse(prompt) if brief_header is not None else None
    if brief_header is not None:
        builds = header is not None and header[0] == brief_header.KIND_FEATURE
    else:
        builds = prompt.startswith(BUILD_BRIEF_MARKER)
    if builds:
        reason = orchestrator_reason(payload)
        if reason:
            emit(DECISION_DENY, reason)
            return
    if brief_header is not None and header is None:
        emit(DECISION_DENY, BRIEF_HEADER_DENY_TEMPLATE % {
            "feature": brief_header.REQUIRED_FEATURE_HEADER,
            "none": brief_header.REQUIRED_NONE_HEADER,
        })


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
    if not isinstance(payload, dict):
        return
    if payload.get("tool_name") == AGENT_TOOL:
        try:
            judge_agent(payload)
        except Exception:  # an analysis failure is never a deny
            pass
        return
    if payload.get("tool_name") != MATCHED_TOOL:
        return

    tool_input = payload.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str) or not command.strip():
        return

    state = state_path(payload.get(SESSION_FIELD), payload.get(AGENT_FIELD))

    # The three shape denies go first. None of them needs a root or a cwd — each shape is
    # wrong wherever it runs — and each names a mechanical fix for a command this
    # analysis CAN read, so a specific reason beats the general one below. A command that
    # gets one of them is a command the model spelled readably, which is what the
    # escalation counter is counting, so each clears it. The git deny's reason is chosen
    # by profile, and under `cloud` it also covers the table's cloud-only shapes
    # (`git_denial`); each judge answers its reason, or None.
    cwd = payload.get("cwd")
    # An orchestrator session runs only the allowlist's shapes (security audit round 3; the
    # table above orchestrator_command_allowed). One that matches goes on to every judge below
    # like any command — the git push rules, the shape denies, the approval — and anything
    # else is denied here, with the role's reason and the list. A record that cannot be read
    # (LEDGER_UNREADABLE) is no allowlist: that checkout keeps the build-script deny below,
    # so a broken `.git` refuses building, never every command.
    record = orchestrator_record(payload)
    if record and orchestrator_role is not None and record != orchestrator_role.LEDGER_UNREADABLE:
        session = payload.get(SESSION_FIELD)
        try:
            cwd_text = cwd if isinstance(cwd, str) else None
            # The one write approved outright: the move of its own stranded record, judged
            # once here (its classifier is a subprocess); any other line goes to the allowlist
            moves = orchestrator_moves_own_record(command, cwd_text, record, session)
            allowed = moves or orchestrator_command_allowed(command, cwd_text, record, session)
        except Exception:  # a line the allowlist cannot read is not on it
            allowed = moves = False
        if not allowed:
            clear_attempts(state)
            emit(DECISION_DENY, orchestrator_allowlist_reason(record))
            return
        if moves:
            clear_attempts(state)
            emit(DECISION_ALLOW, ORCHESTRATOR_MOVE_REASON)
            return
    # The build-script judge: for an orchestrator, the allowlist above has already refused
    # every build script; it stays for the fail-closed case, a checkout whose orchestrator
    # ledger or record history cannot be read, where it is the one deny every session gets.
    unreadable = bool(record) and orchestrator_role is not None and \
        record == orchestrator_role.LEDGER_UNREADABLE
    for judge in (lambda: build_script_denial(command, payload) if unreadable else None,
                  lambda: DENY_REASON if chains_chdir(command) else None,
                  lambda: git_denial(command, cwd),
                  lambda: ASSIGN_DENY_REASON if uses_own_assignment(command) else None):
        try:
            reason = judge()
        except Exception:  # an analysis failure is never a deny
            reason = None
        if reason:
            clear_attempts(state)
            emit(DECISION_DENY, reason)
            return

    root = project_root()
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
