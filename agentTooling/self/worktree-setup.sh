#!/usr/bin/env bash
set -euo pipefail
# template-version: 1

# agentTooling's own worktree setup, run inside a new feature worktree by
# ../feature-start.sh --self. This repo is bash and stdlib Python with no install step,
# so there is nothing to do; it exists so the hook path is the same in both modes. The
# consuming-repo counterpart is templates/plans/worktree-setup.sh, seeded into plans/.

exit 0
