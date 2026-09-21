#!/usr/bin/env bash
set -euo pipefail
# template-version: 3

# This is what `sync-plans.sh --check` compares a seeded copy against to report drift.
# Bump it whenever the body below changes in a way seeded copies must merge by hand.
#
# Runs when ../agentTooling/feature-start.sh is given --open, with the new worktree's
# absolute path as its ONLY argument. Its job is to put a coordinator session inside that
# worktree, because a session is billed to the branch of the directory it was launched in
# (../agentTooling/LIFECYCLE.md, rule 1) and the worktree is the one place a feature's
# work is claimed with no pin. Seeded once from
# agentTooling/templates/plans/open-session.sh by sync-plans.sh, then REPO-OWNED and never
# overwritten — put this repo's way of opening a session here.
#
# cwd is wherever feature-start.sh was run from, so use "$1" and never a relative path.
# Advisory: a non-zero exit is reported and does not unwind the start, which has already
# committed the feature.
#
# THE ONE PLACE `cd <path> && <command>` MAY APPEAR. The string below is not a Bash tool
# call and is never run by this script: it is text handed to Terminal.app, which reads it
# as a human would type it into a fresh shell with no starting directory of its own.
# Everywhere else — in this repo's scripts, in a brief, in a Bash tool call — a chained
# `cd` is refused (CONVENTIONS.md § Shell commands, and
# agentTooling/hooks/allow-repo-commands.sh denies it).
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
# (agentTooling/self/DESIGN-2026-09-18-minutes-slug-and-quoting.md §3). Whatever body
# replaces this one, keep both layers: whichever launcher a repo uses, the path reaches
# it through somebody's quoting.
#
# Swap the body for whatever this repo opens a session with: a tmux window, an iTerm
# profile, an editor, `claude` under a different launcher.

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
