#!/usr/bin/env bash
set -euo pipefail
# template-version: 2

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
# call and is never run by this script or by any test: it is text handed to Terminal.app,
# which reads it as a human would type it into a fresh shell with no starting directory of
# its own. Everywhere else — in this repo's scripts, in a brief, in a Bash tool call — a
# chained `cd` is refused (CONVENTIONS.md § Shell commands, and
# agentTooling/hooks/allow-repo-commands.sh denies it).
#
# The path is single-quoted INSIDE that string: the shell Terminal.app starts word-splits
# what it is handed, so a checkout under `~/My Projects` would otherwise `cd` to the first
# word and run `claude` in the wrong directory — which silently bills the coordinator
# session to whatever branch that directory is on. Keep the quoting in whatever body
# replaces this one.
#
# Swap the body for whatever this repo opens a session with: a tmux window, an iTerm
# profile, an editor, `claude` under a different launcher.

WORKTREE="${1:?usage: open-session.sh <worktree path>}"
TERMINAL_APP="Terminal"
SESSION_COMMAND="claude"

osascript \
  -e "tell application \"$TERMINAL_APP\" to do script \"cd '$WORKTREE' && $SESSION_COMMAND\"" \
  -e "tell application \"$TERMINAL_APP\" to activate" >/dev/null
echo "  open  a $TERMINAL_APP window running $SESSION_COMMAND in $WORKTREE"
