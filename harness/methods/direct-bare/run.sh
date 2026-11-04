#!/usr/bin/env bash
set -uo pipefail

# direct-bare — `direct` without its procedure steps. One implementer, one shot.
#
#   run.sh <tree> <brief> <slug>
#
# Identical to ../direct/run.sh except the method name in its log lines and its mktemp
# prefix: nothing in
# `direct`'s run.sh is specific to the checkpoint or the stamps (those live only in its
# brief), so the arms differ in template.md alone.
#
# Exit 0 = PR open, 2 = usage-limit stop (resumable), 1 = work failure (do not retry),
# the convention harness/SPEC.md §1 pins and plan-runner-lib.sh already uses.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib.sh
source "$SCRIPT_DIR/../../lib.sh"

TREE="${1:?tree required}"
BRIEF="${2:?brief required}"
SLUG="${3:?slug required}"

RESULT="${HARNESS_METHOD_RESULT:-$(mktemp -t harness-direct-bare)}"

harness_log "direct-bare: one implementer on $SLUG (model $HARNESS_MODEL, no budget cap)"
harness_claude "$RESULT" "$BRIEF" "$TREE" \
  --model "$HARNESS_MODEL" --permission-mode acceptEdits --allowedTools Bash
rc=$?

harness_claude_text "$RESULT"

if (( rc != 0 )); then
  if harness_stopped_on_usage_limit "$RESULT"; then
    harness_log "direct-bare: stopped on a usage limit"
    exit "$METHOD_USAGE_LIMIT_RC"
  fi
  harness_warn "direct-bare: claude exited $rc"
  exit "$METHOD_FAILED_RC"
fi
exit "$METHOD_OK_RC"
