#!/usr/bin/env bash
set -euo pipefail
# template-version: 2

# Sources plans/environment.sh first, when present — the facts that differ between a
# laptop and a Claude Code cloud container
# (agentTooling/self/DESIGN-2026-10-05-cloud-execution.md §7).
ENVIRONMENT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/environment.sh"
if [[ -f "$ENVIRONMENT_FILE" ]]; then
  . "$ENVIRONMENT_FILE"
fi

python3 -m venv .venv
.venv/bin/python -m pip install -q -e ".[dev]" --disable-pip-version-check
echo "  hook  .venv created for this worktree (an editable install must not be shared across worktrees)"
