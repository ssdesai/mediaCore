#!/usr/bin/env bash
set -euo pipefail
# template-version: 1

# This is what `sync-plans.sh --check` compares a seeded copy against to report drift.
# Bump it whenever the body below changes in a way seeded copies must merge by hand.
#
# Runs INSIDE a freshly created feature worktree, by ../agentTooling/feature-start.sh,
# after `git worktree add` and before the gate rehearsal. Seeded once from
# agentTooling/templates/plans/worktree-setup.sh by sync-plans.sh, then REPO-OWNED and
# never overwritten — put this repo's per-worktree setup here.
#
# cwd is the worktree root. Exit non-zero to stop the start (the worktree is left in
# place for inspection). Print anything the human launching a session there needs to
# know. Typical contents, each on its own because every repo differs:
#
#   # A venv per worktree — never share one across worktrees: an editable install
#   # points at whichever tree ran `pip install -e` last.
#   python3 -m venv .venv
#   .venv/bin/python -m pip install -q -e ".[dev]"
#
#   npm install --silent
#
#   # A dev server on the default port makes two worktrees' browser suites drive the
#   # same app. Name the variable this repo's dev server reads.
#   echo "  hook  run the dev server with MYAPP_DEV_PORT set to a port no other worktree uses"

echo "  hook  plans/worktree-setup.sh has nothing configured — edit it for this repo's venv, npm install and dev port"
