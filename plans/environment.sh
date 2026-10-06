#!/usr/bin/env bash
# template-version: 1

# This is what `sync-plans.sh --check` compares a seeded copy against to report drift.
# Bump it whenever the body below changes in a way seeded copies must merge by hand.
#
# The facts that differ by where this repo runs — a laptop or a Claude Code cloud
# container (agentTooling/self/DESIGN-2026-10-05-cloud-execution.md §7): the database
# connection, the browser path, anything else a test or a dev server reads from the
# environment. FACTS ONLY, never exceptions: a check that cannot pass in one place is
# fixed at its source (a test configuration, plans/cloud-setup.sh), not skipped here.
#
# SOURCED, never executed, by plans/gate.sh, plans/worktree-setup.sh and this repo's own
# scripts — each with `if [[ -f plans/environment.sh ]]; then . plans/environment.sh; fi`
# or the same with its own path. So: export what you set, keep it quick and quiet, and
# keep it safe under `set -u` and `set -e` (both callers use them). Seeded once by
# agentTooling/sync-plans.sh, then REPO-OWNED and never overwritten.
#
# It is an ADAPTER (design §1): it may branch on the profile, and asks
# agentTooling/env-profile.sh — the one place the profile is decided — through its
# functions (`profile_is_cloud`, `profile_name`), never the variables behind them.
# No `brew` here or anywhere a cloud container runs: the container has none, and what it
# starts it starts in plans/cloud-setup.sh.

# Refuse to run as a program: an `export` in a child process reaches nobody.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "plans/environment.sh is sourced, not run: . plans/environment.sh" >&2
  exit 2
fi

# The detector, from the repo root this file sits one level below.
ENVIRONMENT_PROFILE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/agentTooling/env-profile.sh"
if [[ -f "$ENVIRONMENT_PROFILE_SCRIPT" ]]; then
  . "$ENVIRONMENT_PROFILE_SCRIPT"
fi

# ── REPO-SPECIFIC: this repo's facts, one block per profile ──────────────────
# mediaCore sets nothing: no database, no browser, no dev server — the gate and tests read
# nothing from the environment, so a laptop and a container need the same (none). Add a
# block here only if that changes. The template's example, for a repo with Postgres and a
# Playwright suite; keep the same KEYS in both, only the values differ:
#
#   if declare -F profile_is_cloud >/dev/null && profile_is_cloud; then
#     # A cloud container: the Postgres plans/cloud-setup.sh starts, a role it creates
#     # with no password, and the Chromium the image ships — the CDN is blocked, so
#     # Playwright must never try to download one.
#     export DATABASE_URL="postgresql://app@localhost:5432/app"
#     export PLAYWRIGHT_BROWSERS_PATH="/opt/pw-browsers"
#     export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
#   else
#     # A laptop: the local server and whatever `npx playwright install` put in its cache.
#     export DATABASE_URL="postgresql://localhost:5432/app"
#   fi
#
# Values plans/cloud-setup.sh decides at run time (a port it picked, a socket path) are
# written by it to a file this one reads, e.g. `[[ -f .cloud-env ]] && . ./.cloud-env`,
# with that file in .gitignore.
# ──────────────────────────────────────────────────────────────────────────────
