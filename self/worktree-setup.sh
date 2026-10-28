#!/usr/bin/env bash
set -euo pipefail
# template-version: 2

# agentTooling's own worktree setup, run inside a new feature worktree by
# ../feature-start.sh --self, before the gate. The consuming-repo counterpart is
# templates/plans/worktree-setup.sh, seeded into plans/.
#
# This repo is bash and stdlib Python with no install step, and nothing is generated here
# any more: this checkout's permission policy, .claude/settings.json, is TRACKED
# (self/features/self-cloud-bootstrap), so a new worktree — like a fresh clone — has it
# from its checkout, before the first session there. It used to be written here, when the
# file was generated per checkout and untracked (self/features/self-settings-untracked);
# the gate still holds it byte for byte to hooks/wire-settings.py --self.
#
# Like the template (version 2), it sources self/environment.sh when present — the
# plans/environment.sh hook of self/DESIGN-2026-10-05-cloud-execution.md §7. agentTooling
# ships none: nothing here differs by profile today.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT_FILE="$REPO_DIR/self/environment.sh"

if [[ -f "$ENVIRONMENT_FILE" ]]; then
  . "$ENVIRONMENT_FILE"
fi
