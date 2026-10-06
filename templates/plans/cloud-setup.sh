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
# Nothing is configured yet. For a repo whose gate needs Postgres, e.g.:
#
#   # Start the server the image ships, once.
#   if ! pg_isready -q 2>/dev/null; then
#     service postgresql start >/dev/null && echo "  cloud-setup  postgres started"
#   fi
#   # A passwordless role and a database for it, only when missing.
#   if ! su postgres -c "psql -tAc \"select 1 from pg_roles where rolname='app'\"" | grep -q 1; then
#     su postgres -c "createuser --superuser app" && su postgres -c "createdb -O app app"
#     echo "  cloud-setup  role and database 'app' created"
#   fi
#   # A value only known now, for plans/environment.sh to read (keep the file ignored):
#   echo "export APP_DB_PORT=5432" > "$REPO_DIR/.cloud-env"
#
# Browser paths and other fixed facts belong in plans/environment.sh, not here.
echo "  cloud-setup  plans/cloud-setup.sh has nothing configured — start this repo's services here (agentTooling/templates/plans/cloud-setup.sh)"
# ──────────────────────────────────────────────────────────────────────────────
