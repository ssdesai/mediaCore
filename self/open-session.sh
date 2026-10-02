#!/usr/bin/env bash
set -euo pipefail
# template-version: 3

# agentTooling's own session-opening hook, run inside — for — a new feature worktree by
# ../feature-start.sh --self --open, with the worktree's absolute path as its only
# argument. The consuming-repo counterpart is templates/plans/open-session.sh, seeded into
# plans/; this copy is hand-maintained and carries the same template-version, which
# self/tests/sync-check.sh asserts.
#
# A coordinator session belongs inside the worktree: a session is billed to the branch of
# the directory it was launched in (../LIFECYCLE.md, rule 1), so a session launched here
# is claimed by the feature's branch with no pin, while the session that ran
# feature-start.sh stays a router and is never pinned.
#
# THE ONE PLACE `cd <path> && <command>` MAY APPEAR. The string below is not a Bash tool
# call and is never run by this script: it is text handed to Terminal.app, which reads it
# as a human would type it into a fresh shell with no starting directory of its own.
# Everywhere else a chained `cd` is refused (../CONVENTIONS.md § Shell commands, and
# ../hooks/allow-repo-commands.sh denies it).
#
# THE PATH CROSSES TWO ESCAPING LAYERS, and it needs both. The worktree path is written
# into a shell command line, and that command line is written into an AppleScript string
# literal, so each layer's own metacharacters have to be neutralised in turn:
#
#   1. shell_single_quote — the shell Terminal.app starts word-splits what it is handed,
#      so a checkout under `~/My Projects` would otherwise `cd` to the first word and run
#      the session in the wrong directory. Single quotes stop the splitting; a `'` inside
#      the path would end them early, so each one is spelled `'\''`.
#   2. applescript_escape — AppleScript reads `\` and `"` inside a string literal as
#      escapes, so a path holding either would be silently mangled or would close the
#      literal and break the whole `osascript` argument.
#
# Version 2 had layer 1 only, as a bare pair of quotes: a path holding `'`, `"` or `\`
# opened the session in the wrong directory, or in none, and a session is billed to the
# branch of the directory it was launched in — so the mistake was silent and landed in
# the ledger as somebody else's money
# (../self/DESIGN-2026-09-18-minutes-slug-and-quoting.md §3). Keep both layers in any
# replacement body. self/tests/open-session.sh runs this file and checks the path
# survives them; self/tests/feature-lifecycle.sh S5 reads it as text.

WORKTREE="${1:?usage: open-session.sh <worktree path>}"
TERMINAL_APP="Terminal"
SESSION_COMMAND="claude"

# Layer 1's characters. A single quote inside a single-quoted word is spelled by closing
# the quote, escaping one, and reopening: `'\''`.
SHELL_QUOTE="'"
SHELL_QUOTE_ESCAPED="'\\''"

shell_single_quote() {                 # one shell word, whatever the text holds
  local text="$1"
  printf '%s' "$SHELL_QUOTE${text//$SHELL_QUOTE/$SHELL_QUOTE_ESCAPED}$SHELL_QUOTE"
}

# Layer 2. The two patterns are written as literals rather than read from constants
# because a `\` expanded from a variable is taken as a pattern escape by bash's own
# substitution and matches nothing — the one place in this file where naming the value
# would stop it working.
applescript_escape() {                 # one AppleScript string literal's contents
  local text="$1"
  text="${text//\\/\\\\}"              # backslash first, or it would double the next pass
  printf '%s' "${text//\"/\\\"}"
}

SESSION_LINE="cd $(shell_single_quote "$WORKTREE") && $SESSION_COMMAND"
DO_SCRIPT="$(applescript_escape "$SESSION_LINE")"

osascript \
  -e "tell application \"$TERMINAL_APP\" to do script \"$DO_SCRIPT\"" \
  -e "tell application \"$TERMINAL_APP\" to activate" >/dev/null
echo "  open  a $TERMINAL_APP window running $SESSION_COMMAND in $WORKTREE"
