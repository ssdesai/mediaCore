#!/usr/bin/env bash
set -uo pipefail
# template-version: 3

# This is what `sync-plans.sh --check` compares a seeded copy against to report drift.
# Bump it whenever ANY line of this template changes, comments included —
# agentTooling/self/tests/template-versions.sh refuses an unbumped edit. Version 3 added
# the `--wait` contract and `setup_in_background` below (agentTooling/README.md →
# "Adopting cloud-setup.sh version 3"); version 2 changed only this header.
#
# The once-per-container step for a Claude Code cloud container
# (agentTooling/self/DESIGN-2026-10-05-cloud-execution.md §7): start what this repo's gate
# and tests need that a fresh container lacks, and write what plans/environment.sh reads.
# A red base gate in the cloud means this file is unfinished — finishing it is a feature
# in this repo, not an exception in the gate.
#
# Run by agentTooling/session-start.sh — the `SessionStart` hook agentTooling/sync-plans.sh
# wires into .claude/settings.json (agentTooling/hooks/wire-settings.py) — after it prints
# the session's orientation, in the cloud profile only, on EVERY session start. A session
# starts again on resume and after compaction, so every step below must be idempotent:
# start a server only when it is not up, create a role only when it is missing. Its
# stdout reaches the session's context, so print one line per thing done. What every repo
# needs at session start lives in session-start.sh and ships with the subtree; only what
# THIS repo needs goes here.
#
# **A slow step goes in the background, through setup_in_background, and nowhere else.**
# The hook holds the session up until it exits, so a venv build or an `npm install` is
# better started detached — but then the session's first command can run before it is
# done, and agentTooling/feature-start.sh's base gate did exactly that (a venv still
# installing: "fastapi missing"), and its setup hook raced it for the same .venv. So:
#
#   plans/cloud-setup.sh --wait
#
# blocks until whatever setup_in_background started has finished, and exits 0 when it
# succeeded (or nothing was started), 1 when it failed or is still running after
# WAIT_TIMEOUT_SECONDS. feature-start.sh runs it in the cloud before its setup hook and
# its gate, whenever this file carries the flag — so a copy that backgrounds a step by
# any other means is a copy feature-start.sh cannot wait for. setup_in_background starts
# its command at most once at a time: a session start while an earlier one's step is still
# running says so and starts nothing. Its pid, exit code and log live in this clone's own
# git dir, never in the tree, where an untracked file would make the start refuse the
# checkout as dirty.
#
# It is an ADAPTER (design §1), and keeps a guard of its own though its caller already
# decided the profile: outside the cloud profile it exits 0 at once, `--wait` included, so
# running it by hand, or from a settings file wired before session-start.sh existed, is
# still a no-op on a laptop. It asks agentTooling/env-profile.sh — the one place the
# profile is decided — through its functions, never the variables behind them; with no
# detector beside it, nothing can be decided and nothing is done.
#
# The alternative is the cloud environment's own setup script (configured with the
# environment, run once when the container is built): see agentTooling/templates/README.md
# for when to prefer it. Seeded once by agentTooling/sync-plans.sh, then REPO-OWNED and
# never overwritten.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_SCRIPT="$REPO_DIR/agentTooling/env-profile.sh"
# The contract feature-start.sh calls (header)
WAIT_FLAG="--wait"
# How often --wait looks again, and how long it waits in all before failing
WAIT_POLL_SECONDS=2
WAIT_TIMEOUT_SECONDS=1800
# What a background step leaves in the clone's git dir: its pid, its exit code, its output
STATE_PID_NAME="cloud-setup.pid"
STATE_RC_NAME="cloud-setup.rc"
STATE_LOG_NAME="cloud-setup.log"

if [[ ! -f "$PROFILE_SCRIPT" ]]; then exit 0; fi
. "$PROFILE_SCRIPT"
if ! profile_is_cloud; then exit 0; fi
cd "$REPO_DIR" || exit 1
STATE_DIR="$(git rev-parse --absolute-git-dir 2>/dev/null)" || exit 1
PID_FILE="$STATE_DIR/$STATE_PID_NAME"
RC_FILE="$STATE_DIR/$STATE_RC_NAME"
LOG_FILE="$STATE_DIR/$STATE_LOG_NAME"

# background_pid — the pid of a background step still running, or nothing
background_pid() {
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null)"
  if [[ "$pid" =~ ^[0-9]+$ ]] && ps -p "$pid" >/dev/null 2>&1; then echo "$pid"; fi
}

# setup_in_background <command> [<arg>...] — runs it detached, its output to the log,
# recording its pid and then its exit code for --wait (header). Not again while running.
setup_in_background() {
  local running
  running="$(background_pid)"
  if [[ -n "$running" ]]; then
    echo "  cloud-setup  $1 still running from an earlier start (pid $running)"
    return 0
  fi
  rm -f "$RC_FILE"
  ( "$@"; echo "$?" > "$RC_FILE" ) >> "$LOG_FILE" 2>&1 < /dev/null &
  echo "$!" > "$PID_FILE"
  echo "  cloud-setup  $1 started in the background (pid $!, log $LOG_FILE); plans/cloud-setup.sh $WAIT_FLAG waits for it"
}

if [[ "${1:-}" == "$WAIT_FLAG" ]]; then
  waited=0
  running="$(background_pid)"
  while [[ -n "$running" ]]; do
    if (( waited >= WAIT_TIMEOUT_SECONDS )); then
      echo "  cloud-setup  still running after ${waited}s (pid $running); see $LOG_FILE" >&2
      exit 1
    fi
    sleep "$WAIT_POLL_SECONDS"
    waited=$(( waited + WAIT_POLL_SECONDS ))
    running="$(background_pid)"
  done
  # Nothing was ever started in the background: nothing to wait for.
  if [[ ! -f "$PID_FILE" ]]; then exit 0; fi
  rc="$(cat "$RC_FILE" 2>/dev/null)"
  if [[ -z "$rc" ]]; then
    echo "  cloud-setup  the background setup ended without recording an exit code (killed?); see $LOG_FILE" >&2
    exit 1
  fi
  if [[ "$rc" != 0 ]]; then
    echo "  cloud-setup  the background setup exited $rc; see $LOG_FILE" >&2
    exit 1
  fi
  exit 0
fi

# ── REPO-SPECIFIC: what a fresh container needs ──────────────────────────────
# No server, no database: one pure-Python package. A fresh container lacks only the
# repo's .venv, which the CLAUDE.md commands (`.venv/bin/python -m pytest`, ruff) run
# from. plans/gate.sh would bootstrap it too; doing it here means a session can run the
# tests before any gate has. Same install as plans/worktree-setup.sh. Idempotent: only
# when the venv is missing.
VENV_PYTHON="$REPO_DIR/.venv/bin/python"
if [[ -x "$VENV_PYTHON" ]]; then
  echo "  cloud-setup  .venv present — nothing to do"
else
  python3 -m venv "$REPO_DIR/.venv" || exit 1
  "$VENV_PYTHON" -m pip install -q -e ".[dev]" --disable-pip-version-check || exit 1
  echo "  cloud-setup  .venv created with the editable [dev] install"
fi
# ──────────────────────────────────────────────────────────────────────────────
