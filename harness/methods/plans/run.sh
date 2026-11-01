#!/usr/bin/env bash
set -uo pipefail

# plans — an architect authors the plan corpus, then agentTooling's own batch runner
# drains it (build → gate → verify → review → PR).
#
#   run.sh <tree> <brief> <slug>
#
# Exit 0 = PR open, 2 = usage-limit stop (resumable), 1 = work failure (do not retry).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib.sh
source "$SCRIPT_DIR/../../lib.sh"

TREE="${1:?tree required}"
BRIEF="${2:?brief required}"
SLUG="${3:?slug required}"

# Appended, never truncated: a second run resumes the batch, and `>` here lost one WP7
# arm's whole first run. The path is inside the tree on purpose — the log is part of the
# arm's record and pr.sh commits it with everything else.
BATCH_LOG="$TREE/plans/batch.log"
FEATURE_DIR="$TREE/plans/features/$SLUG"
RESULT="${HARNESS_METHOD_RESULT:-$(mktemp -t harness-plans)}"

# ── 1. The architect ─────────────────────────────────────────────────────────
# A usage-limit stop makes the harness call this script again, so the architect can be
# entered twice. It is re-entered as a FRESH session with a note about what is already on
# disk, rather than through `claude --resume`: that is the runners' own resume model
# (RUNNER.md → "How resume works") — the plans it wrote are the durable state, and a
# session id is not.
PROMPT="$BRIEF"
if [[ -n "$(ls "$FEATURE_DIR/auto/incomplete"/[0-9]*.md 2>/dev/null)" ]]; then
  PROMPT="${HARNESS_LOG_DIR:-$(dirname "$BRIEF")}/$(basename "$BRIEF" .md)-resume.md"
  {
    cat "$BRIEF"
    printf '\n\n## You are resuming\n\n'
    printf 'An earlier run of this same brief stopped part-way and left plans in `%s`.\n' "$FEATURE_DIR"
    printf 'Read what is already there before writing anything: finish the corpus, correct\n'
    printf 'what is inconsistent with it, and do not write a second copy of a plan that exists.\n'
  } > "$PROMPT"
  harness_log "plans: architect re-entered with a partial corpus on disk"
fi

harness_log "plans: architect on $SLUG (model $HARNESS_MODEL, no budget cap)"
harness_claude "$RESULT" "$PROMPT" "$TREE" \
  --model "$HARNESS_MODEL" --permission-mode acceptEdits --allowedTools Bash
rc=$?
harness_claude_text "$RESULT"

if (( rc != 0 )); then
  if harness_stopped_on_usage_limit "$RESULT"; then
    harness_log "plans: architect stopped on a usage limit"
    exit "$METHOD_USAGE_LIMIT_RC"
  fi
  harness_warn "plans: architect exited $rc"
  exit "$METHOD_FAILED_RC"
fi

# ── 2. What the architect must have left behind ──────────────────────────────
# Asserted here rather than trusted: an empty queue makes run-batch.sh a silent no-op,
# and the run would score a method that never built anything as a method that failed to
# build anything well.
missing=()
for queue in auto verify review; do
  [[ -n "$(ls "$FEATURE_DIR/$queue/incomplete"/[0-9]*.md 2>/dev/null)" ]] || missing+=("$queue/incomplete")
done
[[ -f "$FEATURE_DIR/NOTES.md" ]] || missing+=("NOTES.md")
if (( ${#missing[@]} > 0 )); then
  harness_warn "plans: architect left no ${missing[*]} under $FEATURE_DIR"
  exit "$METHOD_FAILED_RC"
fi

# ── 3. The batch ─────────────────────────────────────────────────────────────
batch_stopped_hard() {
  [[ -n "$(ls "$FEATURE_DIR/escalations"/*.md 2>/dev/null)" ]] && return 0
  local queue
  for queue in auto verify review; do
    [[ -n "$(ls "$FEATURE_DIR/$queue/failed"/[0-9]*.md 2>/dev/null)" ]] && return 0
  done
  return 1
}

run_batch() {
  harness_log "plans: run-batch.sh $SLUG (log appended to ${BATCH_LOG#"$TREE"/})"
  ( cd "$TREE" && ./agentTooling/run-batch.sh "$SLUG" ) >> "$BATCH_LOG" 2>&1
  return $?
}

run_batch
batch_rc=$?
if (( batch_rc == 0 )); then exit "$METHOD_OK_RC"; fi

if batch_stopped_hard; then
  harness_warn "plans: batch exited $batch_rc with an escalation or a failed plan — not retrying"
  exit "$METHOD_FAILED_RC"
fi

# Nothing in escalations/ or failed/ means the batch stopped for a usage limit or an
# interrupt, both of which leave the plan in inprogress/ and resume cleanly.
harness_log "plans: batch exited $batch_rc with nothing failed — resuming once"
run_batch
batch_rc=$?
if (( batch_rc == 0 )); then exit "$METHOD_OK_RC"; fi
if batch_stopped_hard; then
  harness_warn "plans: batch exited $batch_rc on the resume with an escalation or a failed plan"
  exit "$METHOD_FAILED_RC"
fi
harness_log "plans: batch still incomplete after one resume — resumable"
exit "$METHOD_USAGE_LIMIT_RC"
