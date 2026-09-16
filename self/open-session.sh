#!/usr/bin/env bash
set -euo pipefail
# template-version: 2

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
# call and is never run by this script or by any test: it is text handed to Terminal.app,
# which reads it as a human would type it into a fresh shell with no starting directory of
# its own. Everywhere else a chained `cd` is refused (../CONVENTIONS.md § Shell commands,
# and ../hooks/allow-repo-commands.sh denies it).
#
# The path is single-quoted INSIDE that string: the shell Terminal.app starts word-splits
# what it is handed, so a checkout under `~/My Projects` would otherwise `cd` to the first
# word and run `claude` in the wrong directory — which silently bills the coordinator
# session to whatever branch that directory is on.

WORKTREE="${1:?usage: open-session.sh <worktree path>}"
TERMINAL_APP="Terminal"
SESSION_COMMAND="claude"

osascript \
  -e "tell application \"$TERMINAL_APP\" to do script \"cd '$WORKTREE' && $SESSION_COMMAND\"" \
  -e "tell application \"$TERMINAL_APP\" to activate" >/dev/null
echo "  open  a $TERMINAL_APP window running $SESSION_COMMAND in $WORKTREE"
