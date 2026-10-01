#!/usr/bin/env bash
set -euo pipefail
# template-version: 1

# agentTooling's own worktree setup, run inside a new feature worktree by
# ../feature-start.sh --self, before the gate. The consuming-repo counterpart is
# templates/plans/worktree-setup.sh, seeded into plans/.
#
# This repo is bash and stdlib Python with no install step. The one thing a new worktree
# needs is this checkout's own .claude/settings.json — the hook entry and the deny and ask
# rules — which git does not track (a tracked copy would ship with the subtree and name a
# hook path no consuming repo has), so each checkout generates its own, before the first
# session there loads it. In a VENDORED agentTooling the generator writes nothing: the
# consuming repo's own wiring at its root is the one that loads (hooks/README.md).

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Relative to REPO_DIR: the generator, run with -B so it leaves no __pycache__ behind.
WIRE_SETTINGS="hooks/wire-settings.py"

python3 -B "$REPO_DIR/$WIRE_SETTINGS" --self --repo "$REPO_DIR" --write
