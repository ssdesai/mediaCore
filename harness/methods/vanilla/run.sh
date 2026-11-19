#!/usr/bin/env bash
set -uo pipefail

# vanilla — the minimal brief with no agentTooling doctrine in the build: for the length of
# the method the tree's CONVENTIONS.md imports and its command hook are taken out
# (neutralize.sh), and put back when this script exits by any path. One implementer, one
# shot.
#
#   run.sh <tree> <brief> <slug>
#
# ../vanilla-conv/run.sh plus the lines marked `# vanilla-only` and nothing else
# (self/tests/vanilla-pair.sh). The two arms' briefs are byte-identical; they differ in what
# the session loads from the tree.
#
# Exit 0 = PR open, 2 = usage-limit stop (resumable), 1 = work failure (do not retry),
# the convention harness/SPEC.md §1 pins and plan-runner-lib.sh already uses. A build whose
# commits touched a neutralized file is a failure: the arm's diff would carry the tooling
# change instead of only the feature.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib.sh
source "$SCRIPT_DIR/../../lib.sh"
# shellcheck source=neutralize.sh
source "$SCRIPT_DIR/neutralize.sh"   # vanilla-only

TREE="${1:?tree required}"
BRIEF="${2:?brief required}"
SLUG="${3:?slug required}"

RESULT="${HARNESS_METHOD_RESULT:-$(mktemp -t harness-vanilla)}"

START_COMMIT="$(git -C "$TREE" rev-parse HEAD)" || exit "$METHOD_FAILED_RC"   # vanilla-only
trap 'vanilla_restore "$TREE"' EXIT   # vanilla-only
trap 'exit "$VANILLA_TERM_RC"' TERM   # vanilla-only
trap 'exit "$VANILLA_INT_RC"' INT   # vanilla-only
vanilla_neutralize "$TREE" || exit "$METHOD_FAILED_RC"   # vanilla-only
harness_log "vanilla: one implementer on $SLUG (model $HARNESS_MODEL, no budget cap)"
harness_claude "$RESULT" "$BRIEF" "$TREE" \
  --model "$HARNESS_MODEL" --permission-mode acceptEdits --allowedTools Bash
rc=$?

harness_claude_text "$RESULT"
vanilla_verify "$TREE" "$START_COMMIT" || exit "$METHOD_FAILED_RC"   # vanilla-only

if (( rc != 0 )); then
  if harness_stopped_on_usage_limit "$RESULT"; then
    harness_log "vanilla: stopped on a usage limit"
    exit "$METHOD_USAGE_LIMIT_RC"
  fi
  harness_warn "vanilla: claude exited $rc"
  exit "$METHOD_FAILED_RC"
fi
exit "$METHOD_OK_RC"
