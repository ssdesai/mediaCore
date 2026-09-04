#!/usr/bin/env bash
set -euo pipefail
# template-version: 1

python3 -m venv .venv
.venv/bin/python -m pip install -q -e ".[dev]" --disable-pip-version-check
echo "  hook  .venv created for this worktree (an editable install must not be shared across worktrees)"
