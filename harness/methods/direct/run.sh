#!/usr/bin/env bash
set -uo pipefail

# direct — one implementer, one shot.
#
#   run.sh <tree> <brief> <slug>
#
# Exit 0 = PR open, 2 = usage-limit stop (resumable), 1 = work failure (do not retry),
# the convention harness/SPEC.md §1 pins and plan-runner-lib.sh already uses.
#
# `direct` is NOT "one claude -p": it is one claude -p plus the same harness review and
# the same rework as every other method. Nothing here reviews its own output.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib.sh
source "$SCRIPT_DIR/../../lib.sh"

TREE="${1:?tree required}"
BRIEF="${2:?brief required}"
SLUG="${3:?slug required}"

RESULT="${HARNESS_METHOD_RESULT:-$(mktemp -t harness-direct)}"

harness_log "direct: one implementer on $SLUG (model $HARNESS_MODEL, no budget cap)"
harness_claude "$RESULT" "$BRIEF" "$TREE" \
  --model "$HARNESS_MODEL" --permission-mode acceptEdits --allowedTools Bash
rc=$?

harness_claude_text "$RESULT"

if (( rc != 0 )); then
  if harness_stopped_on_usage_limit "$RESULT"; then
    harness_log "direct: stopped on a usage limit"
    exit "$METHOD_USAGE_LIMIT_RC"
  fi
  harness_warn "direct: claude exited $rc"
  exit "$METHOD_FAILED_RC"
fi
exit "$METHOD_OK_RC"
