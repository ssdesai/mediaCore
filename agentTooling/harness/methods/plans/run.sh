#!/usr/bin/env bash
set -uo pipefail

# plans — an architect authors the plan corpus, then agentTooling's own batch runner
# drains it (build → gate → verify → review → PR).
#
#   run.sh <tree> <brief> <slug>
#
# Exit 0 = PR open, 2 = usage-limit stop (resumable), 1 = work failure (do not retry).
# Exit 2 needs positive evidence of a usage-limit or interrupt stop; see USAGE_LIMIT_EVIDENCE.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib.sh
source "$SCRIPT_DIR/../../lib.sh"

TREE="${1:?tree required}"
BRIEF="${2:?brief required}"
SLUG="${3:?slug required}"

# Appended, never truncated: a second run resumes the batch, and `>` here lost one WP7
# arm's whole first run. The path is OUTSIDE the tree, in the cell's harness log directory:
# a tracked or untracked log inside the arm's tree is a dirty path, and feature-close.sh
# refuses to close over one ("these dirty paths are not <slug>'s cost records") before
# pr.sh ever runs — which is what ended both cells of exportStoreMethodEffortDefault with no
# PR. Nothing this method writes may land in the tree. Without a harness (HARNESS_LOG_DIR
# unset) it falls back to the temp directory, still outside the tree.
LOG_DIR="${HARNESS_LOG_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$LOG_DIR"
BATCH_LOG="$LOG_DIR/${HARNESS_BRANCH_NAME:-$SLUG}-plans-batch.log"
BATCH_LOG_TAIL_LINES=20

# The positive evidence that a batch stopped on a usage limit or an interrupt. These are the
# exit_reason texts plan-runner-lib.sh prints in every runner's closing summary
# ("  <title> [<slug>]: <reason>") when it leaves the plan in inprogress/ for the next run:
#   stopped: Claude usage limit reached on <plan> (left in inprogress for next run)
#   interrupted by signal (in-progress plan left for next run)
# self/tests/ (harness/tests/plans-method.sh) pins both against the library, so a reworded
# reason fails the gate instead of silently turning every limit stop into a failure.
USAGE_LIMIT_EVIDENCE='stopped: Claude usage limit reached on |interrupted by signal \(in-progress plan left'
FEATURE_DIR="$TREE/plans/features/$SLUG"
RESULT="${HARNESS_METHOD_RESULT:-$(mktemp -t harness-plans)}"

# ── 1. The architect ─────────────────────────────────────────────────────────
# A usage-limit stop makes the harness call this script again, so the architect can be
# entered twice. It is re-entered as a FRESH session with a note about what is already on
# disk, rather than through `claude --resume`: that is the runners' own resume model
# (RUNNER.md → "How resume works") — the plans it wrote are the durable state, and a
# session id is not.
# Has the batch already moved plans on? A usage-limit stop (exit 2) makes the harness call
# this script again from the top, and by then the queues the architect filled have been
# drained into inprogress/ and complete/. The architect must not run again on that corpus
# (it would author a second copy, and the queue assertion below would fail on the empty
# incomplete/ queues): go straight to the batch, which resumes from inprogress/.
batch_started() {
  [[ -n "$(ls "$FEATURE_DIR"/{auto,verify,review}/{inprogress,complete}/[0-9]*.md 2>/dev/null)" ]]
}

author_corpus() {
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
}

if batch_started; then
  harness_log "plans: the batch has already started on $SLUG — resuming it without the architect"
else
  author_corpus
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

batch_log_size() { stat -c %s "$BATCH_LOG" 2>/dev/null || stat -f %z "$BATCH_LOG" 2>/dev/null || echo 0; }

# Runs the batch once, appending to the log; leaves the byte offset where THIS run's output
# began in BATCH_RUN_START, so evidence is read from this invocation only (the log keeps
# earlier runs' output, which may itself name a limit that has since been resumed past).
BATCH_RUN_START=0
run_batch() {
  harness_log "plans: run-batch.sh $SLUG (log appended to $BATCH_LOG)"
  BATCH_RUN_START="$(batch_log_size)"
  ( cd "$TREE" && ./agentTooling/run-batch.sh "$SLUG" ) >> "$BATCH_LOG" 2>&1
  return $?
}

# Not `grep -q`: under pipefail, grep quitting at the first match can SIGPIPE tail when
# more of this run's output follows it, and the pipeline would then report no evidence.
batch_shows_usage_limit() {
  tail -c +"$((BATCH_RUN_START + 1))" "$BATCH_LOG" 2>/dev/null | grep -E "$USAGE_LIMIT_EVIDENCE" > /dev/null
}

run_batch
batch_rc=$?
if (( batch_rc == 0 )); then exit "$METHOD_OK_RC"; fi

if batch_stopped_hard; then
  harness_warn "plans: batch exited $batch_rc with an escalation or a failed plan — not retrying"
  exit "$METHOD_FAILED_RC"
fi

# Resumable only on positive evidence. The harness waits and calls this script again, which
# runs the batch again (it resumes from inprogress/); retrying here would just hit the same
# limit. Any other non-zero exit — a close refusal included — is a failure, at once: it was
# once assumed to be a usage limit, and cost a sleep, a second architect and a second review.
if batch_shows_usage_limit; then
  harness_log "plans: batch exited $batch_rc on a usage limit or an interrupt — resumable"
  exit "$METHOD_USAGE_LIMIT_RC"
fi

harness_warn "plans: batch exited $batch_rc with no usage-limit or interrupt evidence — failing, not resuming. Last $BATCH_LOG_TAIL_LINES lines of this run's output in $BATCH_LOG:"
tail -c +"$((BATCH_RUN_START + 1))" "$BATCH_LOG" | tail -n "$BATCH_LOG_TAIL_LINES" >&2
exit "$METHOD_FAILED_RC"
