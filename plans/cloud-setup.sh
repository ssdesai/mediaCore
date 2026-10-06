#!/usr/bin/env bash
set -uo pipefail
# template-version: 1

# This is what `sync-plans.sh --check` compares a seeded copy against to report drift.
# Bump it whenever the body below changes in a way seeded copies must merge by hand.
#
# The once-per-container step for a Claude Code cloud container
# (agentTooling/self/DESIGN-2026-10-05-cloud-execution.md §7): start what this repo's gate
# and tests need that a fresh container lacks, and write what plans/environment.sh reads.
# A red base gate in the cloud means this file is unfinished — finishing it is a feature
# in this repo, not an exception in the gate.
#
# Run by the `SessionStart` hook agentTooling/sync-plans.sh wires into
# .claude/settings.json (agentTooling/hooks/wire-settings.py), on EVERY session start —
# and a session starts again on resume and after compaction, so every step below must be
# idempotent: start a server only when it is not up, create a role only when it is
# missing. Its stdout reaches the session's context, so print one line per thing done.
#
# It is an ADAPTER (design §1), and the guard is its own: outside the cloud profile it
# exits 0 at once, doing nothing, so the same settings file serves a laptop and a
# container. It asks agentTooling/env-profile.sh — the one place the profile is decided —
# through its functions, never the variables behind them; with no detector beside it,
# nothing can be decided and nothing is done.
#
# The alternative is the cloud environment's own setup script (configured with the
# environment, run once when the container is built): see agentTooling/templates/README.md
# for when to prefer it. Seeded once by agentTooling/sync-plans.sh, then REPO-OWNED and
# never overwritten.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_SCRIPT="$REPO_DIR/agentTooling/env-profile.sh"

if [[ ! -f "$PROFILE_SCRIPT" ]]; then exit 0; fi
. "$PROFILE_SCRIPT"
if ! profile_is_cloud; then exit 0; fi
cd "$REPO_DIR" || exit 1

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
