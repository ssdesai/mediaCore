#!/usr/bin/env bash
# Shared machinery for the delegated-plan runners (run-plans.sh, run-verify.sh,
# run-review.sh).
# Both runners share an identical queue/resume/logging/routing pipeline — this
# file is the single source of truth for it, so a fix to the subtle parts (the
# FIFO-PID wait race, the usage-limit detection, stream finalization) can never
# drift between the two copies.
#
# A wrapper sources this file after setting:
#   REPO_DIR         — repo root; the runner cd's here so claude runs from root
#   FEATURES_DIR     — $REPO_DIR/plans/features, the root of the per-feature tree
#   FEATURES_LABEL   — FEATURES_DIR as typed from REPO_DIR ("plans/features", or
#                      "self/features" under --self); messages print after the cd
#   SELF_ARG         — "--self " or "", so a retry hint reproduces this run's mode
#   QUEUE            — which queue this runner drains: "auto", "verify" or "review".
#                      Used only to build paths, so a new queue is a new wrapper script
#                      plus a directory — nothing in this file changes.
#   PLAN_KIND        — singular noun for log lines: "plan" or "verify plan"
#   SUMMARY_TITLE    — header for the end-of-run status block
#   CLAUDE_TOOL_ARGS — array of extra claude flags scoping tool access; this is
#                      the security boundary between the two runners
#                      (--disallowedTools Bash vs --allowedTools Bash)
#   build_prompt <plan_path> <log_path> — echoes the executor prompt for one plan
# then calls: run_all "$@"

# Set by run_all once the feature is resolved — NOT at source time, because which
# directory this run drains is not known until then. Declared here (rather than left
# unset) so the EXIT trap can read them even if the run dies early under `set -u`.
FEATURE_SLUG=""
PLAN_DIR=""
INCOMPLETE_DIR=""
INPROGRESS_DIR=""
COMPLETE_DIR=""
FAILED_DIR=""

FEATURES_LABEL="${FEATURES_LABEL:-plans/features}"
SELF_ARG="${SELF_ARG:-}"
LEVEL_PAUSE_RC="${LEVEL_PAUSE_RC:-64}"

current_plan=""
exit_reason="all ${PLAN_KIND}s complete"
route_failures=0

# How long follow_stream waits between size checks on the stream file while `claude` is
# still writing. It sets the display's latency and NOTHING else: the drain is ended by
# `claude` having exited — observed through an on-disk marker, or through its pid being
# gone — never by a sleep expiring, so a value ten minutes long would make the terminal
# sluggish and still lose no events.
FOLLOW_POLL_SECONDS=0.2

# Set by run_plan for the lifetime of one `claude` invocation, and read by on_interrupt —
# which is the only other place that has to know a capture is in flight. CAPTURE_TMPDIR
# holds the exited-marker (see run_plan): a mktemp -d rather than a file beside the plan,
# because every file in this directory ships to every consuming repo and a new artifact in
# a feature's plan tree would need a .gitignore pattern there before the next `git subtree`
# push, which refuses a dirty tree.
CAPTURE_CLAUDE_PID=""
CAPTURE_TMPDIR=""
CAPTURE_EXITED_MARKER_NAME="claude-exited"
CAPTURE_TMPDIR_TEMPLATE="plan-capture.XXXXXX"
# run_plan's return code when the capture cannot be set up at all — distinct from any
# `claude -p` status, from the usage-limit (2) and budget (3) codes, and from
# LEVEL_PAUSE_RC (64), so finalize_plan files the plan to failed/ and the runner exits
# with something a caller can tell apart from a model failure.
CAPTURE_SETUP_RC=70

# ── One definition of the events in a captured stream ────────────────────────
# `claude`'s stderr is merged into the stream (`2>&1` in run_plan), so a runtime warning
# or a crash trace can leave a non-JSON line in it, and a killed run can leave a truncated
# last one. Every reader of "did this stream reach a `result` event?" parses it THIS way —
# skipping unparseable lines rather than failing over the file — and there is exactly one
# copy of the expression, because the two readers used to disagree: `stream_has_result`
# ran an intolerant `jq -e`, which exits non-zero on a *parse* error just as it does on an
# absent event, while write_usage_sidecar dropped bad lines and found the result. One
# stray line was enough for finalize_plan to warn that the capture had been truncated
# while the sidecar beside it recorded a real cost — a false alarm on the exact signal
# this whole feature exists to make trustworthy.
STREAM_EVENTS_JQ='split("\n") | map(select(length > 0) | fromjson?)'
STREAM_LAST_RESULT_JQ='map(select(.type == "result")) | last'

# The words a usage limit is reported in, matched case-insensitively. ONE copy, for the
# same reason STREAM_EVENTS_JQ is one copy: stream_shows_usage_limit now has two signals
# — the final `result` event and a hard-killed session's last `error` event — and two
# vocabularies would route the same limit two ways depending on which event carried it.
# Deliberately does NOT match "Reached maximum budget"; keeping this disjoint from
# stream_shows_budget_exhausted is what stops a mis-scoped brief being re-queued as a
# rate limit.
STREAM_LIMIT_TEXT_RE='usage.?limit|rate.?limit|hit.{0,15}limit|limit.{0,20}reset|quota|exceeded|insufficient.?credits|\\b429\\b|\\b529\\b|overloaded'

# The hard-kill signal: a session the platform cut off at a usage limit is killed
# mid-turn and never emits a `result` event, so the final-result matcher below is blind
# to exactly the case the graceful `rc == 2` path exists for (self/BACKLOG.md, raised by
# `stale-failed-sidecars`; vinylCatalogue's group-commit-all-adjudication review, filed
# as an ordinary failure on 2026-09-04).
#
# Three conditions, all required, and they are what keep this from becoming the
# whole-stream scan the final-result matcher exists to avoid:
#   1. no `result` event anywhere — a stream that reached one is judged by it alone;
#   2. the LAST parsed event is `type: "error"` — how the stream ENDED, not something
#      it recovered from and carried on past;
#   3. that event names a limit in STREAM_LIMIT_TEXT_RE's terms.
# Matched over the whole event, stringified, rather than a field chain: an `error`
# event has no settled layout and the platform has put the status code in
# `.error.status`, `.error.message` and `.error.type` at different times. The three
# conditions above are the scope; the field the code lands in is not.
STREAM_HARD_KILL_LIMIT_JQ="
  ($STREAM_EVENTS_JQ) as \$events
  | (\$events | last) as \$last
  | ((\$events | $STREAM_LAST_RESULT_JQ) == null)
    and (\$last.type? == \"error\")
    and ((\$last | tostring) | test(\"$STREAM_LIMIT_TEXT_RE\"; \"i\"))
"

print_status() {
  # Runs from the EXIT trap, so every way out of a pass — clean, failed, interrupted,
  # paused at a sentinel — leaves the same closing stamp with the reason it stopped.
  stamp_timing pass_end queue="${QUEUE:-}" reason="$exit_reason"
  echo ""
  echo "=================================================="
  echo "  $SUMMARY_TITLE [${FEATURE_SLUG:-none}]: $exit_reason"
  echo "=================================================="
  for label in complete inprogress failed incomplete; do
    case "$label" in
      complete)   dir="$COMPLETE_DIR" ;;
      inprogress) dir="$INPROGRESS_DIR" ;;
      failed)     dir="$FAILED_DIR" ;;
      incomplete) dir="$INCOMPLETE_DIR" ;;
    esac
    plans=()
    for f in "$dir"/[0-9]*.md; do
      [[ "$f" == *.progress.md ]] && continue
      plans+=("$f")
    done
    if (( ${#plans[@]} > 0 )); then
      echo "  [$label]"
      for f in "${plans[@]}"; do
        echo "    - $(basename "$f")"
      done
    fi
  done
  echo "=================================================="
}

# Stop a capture that is still in flight. `claude` runs as a background job now (run_plan),
# and a background job in a non-interactive shell has SIGINT and SIGQUIT set to ignore, so
# a Ctrl-C that reaches this script no longer reaches it through the process group the way
# it did when it was a foreground pipeline stage — it has to be signalled by pid. Touching
# the exited-marker releases follow_stream, which would otherwise be left polling a file
# nobody is going to write to again.
#
# The capture directory is removed here rather than left to the follower, because the
# follower does not always outlive this shell: on a `kill -TERM -<pgid>` — a supervisor
# tearing down a batch — it dies alongside the runner, and its own `rm -rf` never runs.
# Removing it under the follower is safe because the marker is not the follower's only
# way out: it also stops when `claude`'s pid is gone (see follow_stream), which the kill
# above has just arranged.
stop_capture() {
  if [[ -n "$CAPTURE_CLAUDE_PID" ]]; then
    kill "$CAPTURE_CLAUDE_PID" 2>/dev/null
  fi
  if [[ -n "$CAPTURE_TMPDIR" ]]; then
    : > "$CAPTURE_TMPDIR/$CAPTURE_EXITED_MARKER_NAME" 2>/dev/null
    rm -rf "$CAPTURE_TMPDIR"
    CAPTURE_TMPDIR=""
  fi
}

on_interrupt() {
  # Leave any in-progress plan + its log where they are; next run resumes them.
  stop_capture
  exit_reason="interrupted by signal (in-progress plan left for next run)"
  exit 130
}

# List plan files (excluding .progress.md logs) in a directory, sorted. When PLAN_MAX_NN
# is set (run-verify.sh --up-to NN), plans whose leading number is greater than it are
# omitted — that is how a level-verify plan is drained at its level boundary while the
# final verify, numbered above every sentinel, waits for the end of the batch.
list_plans() {
  local dir="$1" f base
  for f in "$dir"/[0-9]*.md; do
    [[ "$f" == *.progress.md ]] && continue
    if [[ -n "${PLAN_MAX_NN:-}" ]]; then
      base="$(basename "$f")"
      [[ $((10#${base%%-*})) -le $((10#$PLAN_MAX_NN)) ]] || continue
    fi
    echo "$f"
  done
}

# A sentinel plan `NN-gate.md` marks a level boundary (AGENT_PLANS.md, "Levels"). It is
# never sent to claude: the build runner runs the mechanical gate in its place, labelled
# with NN, then files it to complete/ with no progress log, stream or usage sidecar.
is_gate_sentinel() {
  [[ "$(basename "$1")" =~ ^[0-9]+-gate\.md$ ]]
}

# Is a verify plan numbered <= the given sentinel number queued for this feature? The
# build runner yields to run-batch.sh at a boundary only when there is a level-verify
# plan to run there; otherwise it continues into the next level without stopping.
# Both incomplete/ and inprogress/ count, the same pair resolve_feature calls "queued":
# a level-verify interrupted mid-run sits in inprogress/, and it is exactly as much a
# reason to stop before the next level as one that never started.
level_verify_queued() {
  local nn="$1" f base
  for f in "$FEATURES_DIR/$FEATURE_SLUG/verify/incomplete"/[0-9]*.md \
           "$FEATURES_DIR/$FEATURE_SLUG/verify/inprogress"/[0-9]*.md; do
    [[ "$f" == *.progress.md ]] && continue
    base="$(basename "$f")"
    if [[ $((10#${base%%-*})) -le $((10#$nn)) ]]; then return 0; fi
  done
  return 1
}

# Run the repo's gate at a level boundary, passing the sentinel's number as the label
# (gate.sh copies its report to gate-report.<label>.txt). Same contract as the final
# gate in run-batch.sh: advisory on red, fatal only on an unusable environment.
run_level_gate() {
  local label="$1" rc
  if [[ ! -x "$GATE_SCRIPT" ]]; then
    echo "=== level $label: no gate script at ${GATE_SCRIPT#$REPO_DIR/}, skipping ==="
    return 0
  fi
  echo "=== level $label: mechanical gate (${GATE_SCRIPT#$REPO_DIR/}) ==="
  # The sentinel is still in incomplete/ when this runs from run_all, complete/ afterwards.
  local sentinel
  for sentinel in "$FEATURES_DIR/$FEATURE_SLUG/auto"/{incomplete,complete}/"$label-gate.md"; do
    [[ -f "$sentinel" ]] && break
  done
  level_expectations "$sentinel"
  stamp_timing gate_start level="$label"
  "$GATE_SCRIPT" "$label"
  rc=$?
  unset GATE_EXPECTED_RED GATE_DEFERRED
  local green=false
  level_gate_green "$label" && green=true
  stamp_timing gate_end level="$label" rc="$rc" green="$green"
  if (( rc != 0 )); then
    exit_reason="stopped: gate reports an unusable environment (exit $rc) at level $label"
    # Never forward the reserved pause code: run-batch.sh would read it as "run the
    # level-verify and continue", burying a broken environment under a verify session.
    if (( rc == LEVEL_PAUSE_RC )); then exit 1; fi
    exit "$rc"
  fi
}

# Did the gate that just ran at level NN report a fully green tree? Reads the per-level
# copy gate.sh writes when it accepts a label (gate-report.NN.txt), falling back to the
# plain report for a repo gate that predates labels. Green means the last line under
# "# VERDICT" is exactly "all checks passed" — a SKIPPED or FAILED verdict is not green.
level_gate_green() {
  local nn="$1" report="$REPO_DIR/$GATE_REPORT_LABEL"
  local labelled="${report%.txt}.$nn.txt"
  [[ -f "$labelled" ]] && report="$labelled"
  [[ -f "$report" ]] || return 1
  [[ "$(awk '/^# VERDICT/{getline; print; exit}' "$report")" == "all checks passed" ]]
}

# Tier 2 of the red-gate ladder (RUNNER.md → "Red gates: the tier ladder"). When a level's
# authored level-verify (tier 1) leaves the gate red — or wrote an escalation note saying
# a contract has to change — run-batch.sh asks for a synthesized opus plan here, queued as
# a verify plan so it gets the same bash scope, usage sidecar and failed/ routing as every
# other pass. The brief is generated, not authored, because nobody knows at authoring
# time which level will go red: it points the executor at the manifest (the design
# resolutions and contracts table), the level's gate report, the tier-1 progress log and
# any escalation note, and charges it with the one thing tier 1 may not do — change a
# contract, and patch every queued downstream plan that mirrors it.
#
# Idempotent: a second call for the same level is a no-op (returns 1) so the batch can
# never buy the same escalation twice. Named NN-escalation-opus so analysis/report.py can
# recognise it as harness-synthesized and roll its cost in without a manifest entry.
escalation_note_path() {
  echo "$FEATURES_DIR/$FEATURE_SLUG/escalations/$1.md"
}

write_escalation_plan() {
  local nn="$1"
  local vdir="$FEATURES_DIR/$FEATURE_SLUG/verify"
  local stem="$nn-escalation-opus"
  local f
  for f in "$vdir"/{incomplete,inprogress,complete,failed}/"$stem.md"; do
    [[ -e "$f" ]] && return 1
  done
  mkdir -p "$vdir/incomplete"
  local report="$GATE_REPORT_LABEL"
  local labelled="${report%.txt}.$nn.txt"
  [[ -f "$REPO_DIR/$labelled" ]] && report="$labelled"
  local tier1_logs
  tier1_logs="$(ls "$vdir"/{complete,failed}/"$nn"-level-*.progress.md 2>/dev/null | sed "s#^$REPO_DIR/##" | sed 's/^/- /')"
  local note
  note="$(escalation_note_path "$nn")"
  local note_label="${note#$REPO_DIR/}"
  cat > "$vdir/incomplete/$stem.md" <<PLAN
# Escalation at level $nn — harness-synthesized, feature \`$FEATURE_SLUG\`

Level $nn's gate is still red after its level-verify ran (tier 1). Tier 1 was forbidden
from changing any contract; you are not. Make level $nn's gate green, changing a contract
if — and only if — the tree cannot be made green without it, and keep every plan still
queued for the levels above consistent with what you decided.

Read, in this order:
1. \`$FEATURES_LABEL/$FEATURE_SLUG/README.md\` — the manifest: design resolutions, the
   Levels table and the Contracts table. These are the decisions already made; start
   from them, not from the code.
2. \`$report\` — the level's gate report.
3. The escalation note at \`$note_label\`, if it exists: the tier-1 executor's statement
   of which contract it believes must change and why.
4. The tier-1 progress log(s), which list what it already edited:
$tier1_logs
5. Every plan still queued under \`$FEATURES_LABEL/$FEATURE_SLUG/auto/incomplete/\`.
   Build executors cold-start from those files alone. Any identifier, signature, field
   or fixture you change at this level that one of them pins must be corrected IN THE
   PLAN FILE before you finish — a plan that mirrors the old contract will rebuild the
   defect you just removed. This is the one pass in the batch permitted to edit plan
   files.

Then:
- Prefer the fix that touches the fewest contract rows. Changing a test that asserts the
  contract is allowed only when the manifest's design resolution says the test is wrong.
- Re-run only the gate sections that were red, then the whole gate script once at the
  end (\`$GATE_SCRIPT_LABEL $nn\`) and confirm its verdict is \`all checks passed\`.
- Append a section \`## Decided at tier 2\` to \`$note_label\` (create it if absent): what
  you changed, which contract rows moved, and which queued plans you edited. The review
  pass and the human reading the PR see this.
- If the gate cannot be made green without a decision the manifest does not cover,
  stop, write that decision question under \`## Needs a human\` in the same note, and
  leave the tree in the most consistent state you can. The batch will stop here.
PLAN
  echo "$vdir/incomplete/$stem.md"
}

# D3 (revised after the musicMap pilot): a level-verify plan is a fix session for a red
# level. When the level's gate is green it has nothing to fix, and running it anyway was
# measured at 23% of the final verify's cost for no finding. File every queued verify plan
# numbered <= NN to complete/ with a note saying why, so neither the batch's --up-to pass
# nor the final verify pass picks it up later.
skip_level_verify() {
  local nn="$1" f base log
  local vdir="$FEATURES_DIR/$FEATURE_SLUG/verify"
  mkdir -p "$vdir/complete"
  for f in "$vdir/incomplete"/[0-9]*.md; do
    [[ "$f" == *.progress.md ]] && continue
    base="$(basename "$f")"
    if [[ $((10#${base%%-*})) -le $((10#$nn)) ]]; then
      log="$vdir/complete/${base%.md}.progress.md"
      echo "skipped: level $nn gate reported 'all checks passed' — level-verify not run (AGENT_PLANS.md → Levels, D3)" > "$log"
      mv "$f" "$vdir/complete/$base"
      echo "=== level $nn: gate green — skipping level-verify $base (filed to verify/complete) ==="
    fi
  done
}

# Decide which feature's queue this run drains. Plans live under
# plans/features/<slug>/<queue>/{incomplete,inprogress,complete,failed} — or
# self/features/<slug>/… under --self; the wrapper decides, this file only reads
# FEATURES_DIR. A run operates on exactly one feature, and the feature directory is
# what makes a batch's plans, logs and cost records addressable as a unit.
#
# The slug may be passed explicitly (first arg to run_all). Otherwise it is inferred
# from whichever feature has work sitting in this queue. Inference is deliberately
# all-or-nothing: two features with queued work is an ERROR, not a pick. Guessing wrong
# does not merely run the wrong plans — it files their completed logs, streams and
# usage records under another feature, corrupting a cost report that nothing downstream
# can detect as wrong.
#
# Sets FEATURE_SLUG. Leaves it empty (returning 0) when nothing is queued anywhere:
# an empty queue is a no-op, the same as it was before this was per-feature.
resolve_feature() {
  local requested="${1:-}"
  local d slug

  if [[ -n "$requested" ]]; then
    if [[ ! -d "$FEATURES_DIR/$requested" ]]; then
      echo "ERROR: no such feature: $FEATURES_LABEL/$requested" >&2
      echo "  known features:" >&2
      for d in "$FEATURES_DIR"/*/; do echo "    $(basename "$d")" >&2; done
      return 1
    fi
    FEATURE_SLUG="$requested"
    return 0
  fi

  local candidates=()
  for d in "$FEATURES_DIR"/*/; do
    slug="$(basename "$d")"
    if [[ -n "$(list_plans "$d$QUEUE/incomplete")$(list_plans "$d$QUEUE/inprogress")" ]]; then
      candidates+=("$slug")
    fi
  done

  if (( ${#candidates[@]} == 0 )); then
    FEATURE_SLUG=""
    return 0
  fi

  if (( ${#candidates[@]} > 1 )); then
    echo "ERROR: ${#candidates[@]} features have queued ${PLAN_KIND}s; name one explicitly:" >&2
    for slug in "${candidates[@]}"; do
      echo "    $(basename "$0") $SELF_ARG$slug" >&2
    done
    return 1
  fi

  FEATURE_SLUG="${candidates[0]}"
  return 0
}

# Extract the model name from a plan filename like NN-description-MODEL.md.
# MODEL must be one of haiku, sonnet, opus. Falls back to sonnet with a warning
# if the trailing segment doesn't match a known model.
extract_model() {
  local plan_path="$1"
  local stem
  stem="$(basename "$plan_path" .md)"
  local model="${stem##*-}"
  case "$model" in
    haiku|sonnet|opus) echo "$model" ;;
    *)
      echo "WARN: $(basename "$plan_path") has no recognized model suffix; defaulting to sonnet" >&2
      echo "sonnet"
      ;;
  esac
}

# Pretty-print stream-json events as they arrive. Reads newline-delimited
# JSON from stdin, writes a human-readable summary to stdout so the user
# still sees progress during a run.
display_stream() {
  jq -r --unbuffered '
    if .type == "assistant" then
      (.message.content[]? |
        if .type == "text" then .text
        elif .type == "tool_use" then "\n[→ \(.name)]"
        else empty end)
    elif .type == "result" then
      "\n[result: \(.subtype // "unknown")\(if .is_error == true then " (error)" else "" end)]"
    else empty end
  ' 2>/dev/null
}

# Append one line per mutating tool_use to the plan's progress log, streamed
# live from the stream-json events. Only file-mutating tools are recorded, since
# the log's purpose is to hint on resume which files may already be touched —
# verification against on-disk state is still the executor's job.
log_stream_events() {
  local log_path="$1"
  jq -r --unbuffered '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    . as $t |
    ($t.input.file_path // $t.input.path // $t.input.notebook_path // "") as $file |
    if ($t.name | IN("Edit","Write","MultiEdit","NotebookEdit")) and ($file | length) > 0 then
      "\($t.name | ascii_downcase): \($file)"
    else empty end
  ' 2>/dev/null >> "$log_path"
}

# Follow the stream file `claude` is writing, forwarding everything that appears in it to
# the progress-log FIFO (fd 4, which the caller must have open) and, best-effort, to this
# function's stdout for display_stream.
#
#   follow_stream <stream_file> <exited_marker>            4> <fifo>
#
# `claude` owns the file; this only reads it. That is the whole of ruling 1
# (self/features/stream-capture-file-first): nothing downstream of the file — not this
# follower, not the logger, not the display, not the terminal — can stop the record from
# being written, because none of them is between `claude` and the file.
#
# Deterministic drain, not a timed one. <exited_marker> is created by the caller only
# AFTER it has reaped `claude`, so its existence proves the file is final. The loop
# samples the marker *before* it measures the file and only exits through a measurement
# that found nothing new, so the last measurement always happens after the last write.
# FOLLOW_POLL_SECONDS therefore sets latency, never correctness — which matters because
# macOS `tail` polls and has no `--pid`, so a `tail -f` killed after a fixed wait (the
# obvious implementation) would be exactly the race this avoids.
#
# Bytes, not lines. jq on the far end parses a JSON *stream*, so a chunk boundary in the
# middle of an event is invisible to it and there is nothing to gain from splitting on
# newlines — while `while read` over a growing file demonstrably loses that bet: a read
# loop whose other write in the same iteration failed with EPIPE re-read and re-emitted a
# line, reproducibly (NOTES.md). `tail -c`/`head -c` keep no such state, and both flags
# are BSD as well as GNU.
follow_stream() {
  local stream_file="$1" exited_marker="$2" producer_pid="$3"
  local off=0 size chunk producer_done=0 was_done=0 display=1

  while :; do
    was_done=$producer_done
    size="$(wc -c < "$stream_file" 2>/dev/null || echo 0)"
    size=$(( size ))
    if (( size > off )); then
      chunk=$(( size - off ))
      # The FIFO first and unconditionally: the progress log is a record, the display is
      # a convenience. Read twice rather than teeing once, so that a dead display is a
      # flag this function sets rather than a `tee` behaviour it has to trust.
      tail -c "+$(( off + 1 ))" "$stream_file" 2>/dev/null | head -c "$chunk" >&4 2>/dev/null
      if (( display )); then
        tail -c "+$(( off + 1 ))" "$stream_file" 2>/dev/null | head -c "$chunk" 2>/dev/null
        # head's status, not the pipeline's. `claude` keeps writing while this reads, so
        # `tail` usually has more to give than the $chunk bytes measured a moment ago and
        # is killed by `head` closing the pipe — which under `pipefail` is a non-zero
        # pipeline every time. Reading that as "the display is gone" cut the terminal
        # output off a few hundred events in, silently, while the capture ran on.
        if (( ${PIPESTATUS[1]} != 0 )); then display=0; fi
      fi
      off=$size
      continue
    fi
    if (( was_done )); then break; fi
    # Two ways to learn the producer has finished, and either is enough. The marker is
    # the authoritative one — the runner writes it only after `wait` has reaped `claude`,
    # so it cannot be seen a moment too early. The pid check is the one that means this
    # loop can never outlive its producer: if the marker is missing for any reason (an
    # interrupt handler that removed the capture directory, a `: >` that failed), a
    # process that no longer exists has also finished writing, and the snapshot-then-
    # measure order below still forces one more full read before the break. A hang here
    # would have been silent and unbounded — no timeout anywhere in the path — so it is
    # worth two conditions rather than one.
    if [[ -e "$exited_marker" ]] || ! kill -0 "$producer_pid" 2>/dev/null; then
      producer_done=1
      continue
    fi
    sleep "$FOLLOW_POLL_SECONDS"
  done
}

# Extract a one-line failure reason from the final `result` event, so a failed
# plan is self-documenting even when it died before its first mutating tool call.
stream_failure_reason() {
  local stream_file="$1"
  jq -r 'select(.type == "result" and .is_error == true) |
         (.result // .error // .subtype // "unknown error" | tostring)' \
     "$stream_file" 2>/dev/null | tail -1
}

# Did the captured stream reach `claude -p`'s final `result` event? Every normal ending
# emits one — success, failure, budget cap alike — so a stream without one either belongs
# to a session killed mid-turn or to a capture that lost the end of it. Paired with
# `rc == 0` in finalize_plan, the second is the only reading left, which is what makes
# that combination worth a warning.
#
# This is the single definition of that fact: write_usage_sidecar's `result_event` is
# derived from the same two expressions over the same tolerant parse, so the sidecar and
# the warning can never disagree about one file. See STREAM_EVENTS_JQ at the top.
stream_has_result() {
  local stream_file="$1"
  [[ -f "$stream_file" ]] || return 1
  jq -R -s -e "($STREAM_EVENTS_JQ) | ($STREAM_LAST_RESULT_JQ) | . != null" \
    "$stream_file" >/dev/null 2>&1
}

# Inspect a captured stream-json file for usage/rate-limit indicators.
# Returns 0 if a limit was hit, 1 otherwise. Two signals, and no others:
#
#   1. the final `result` event says so — the authoritative statement from claude -p
#      about why the run ended, and the only signal for any stream that reached one;
#   2. the stream has NO `result` event and its last parsed event is an `error` event
#      naming a limit (STREAM_HARD_KILL_LIMIT_JQ) — the hard kill, which never gets to
#      emit a result event at all.
#
# Scanning the whole stream would false-positive on any file or message that merely
# contains a phrase like "rate limit", which is why signal 2 is pinned to the stream's
# ending rather than its body: a limit reported mid-stream and recovered from is not a
# kill, and a `result` event that merely mentions one is still not a limit.
stream_shows_usage_limit() {
  local stream_file="$1"

  if jq -e "select(.type == \"result\" and .is_error == true) |
            select((.result // .error // .subtype // \"\" | tostring)
                   | test(\"$STREAM_LIMIT_TEXT_RE\"; \"i\"))" \
       "$stream_file" >/dev/null 2>&1; then
    return 0
  fi

  # -R -s and the shared tolerant parse, for the reason STREAM_EVENTS_JQ records:
  # claude's stderr is merged into this file, so an intolerant slurp would reject the
  # whole stream over one warning line and hide the error event under it.
  [[ -f "$stream_file" ]] || return 1
  jq -R -s -e "$STREAM_HARD_KILL_LIMIT_JQ" "$stream_file" >/dev/null 2>&1
}

# Inspect a captured stream-json file for budget exhaustion (`--max-budget-usd`).
# Returns 0 if the cap stopped the run, 1 otherwise.
#
# Distinct from stream_shows_usage_limit in what it means: that one is "the account
# is out of room, come back later" and leaves the plan queued; this one is "this plan
# spent more than its brief is worth", which is a scoping defect a human should see.
# `claude -p` exits 1 for both *and* for genuine failures, so matching the result
# event's subtype is the only way to tell the three apart. Matched on the exact field
# rather than the message text: the usage-limit regex above deliberately does not
# match "Reached maximum budget", and keeping these two disjoint is what stops a
# mis-scoped brief from being mistaken for a rate limit and silently re-queued.
stream_shows_budget_exhausted() {
  local stream_file="$1"

  jq -e 'select(.type == "result" and .is_error == true) |
         select(.subtype == "error_max_budget_usd"
                or .terminal_reason == "budget_exhausted")' \
     "$stream_file" >/dev/null 2>&1
}

# Run one plan. Caller must have already placed plan_path in $INPROGRESS_DIR
# and ensured the sidecar log exists. Returns:
#   0 = success
#   2 = usage limit reached (caller should stop cleanly, leave state alone)
#   3 = budget cap reached (caller should route to failed/ — the brief is mis-scoped)
#   other = claude-p exit code (caller should move plan + log to failed/)
run_plan() {
  local plan_path="$1"
  local log_path="${plan_path%.md}.progress.md"
  local plan_name
  plan_name="$(basename "$plan_path")"

  echo "=== Running $PLAN_KIND: $plan_name ==="
  stamp_timing plan_start plan="${plan_name%.md}" queue="$QUEUE"

  # The raw event stream is kept beside the plan rather than in a temp file, so
  # finalize_plan can move it into complete/ or failed/ alongside the plan for
  # later analysis. Gitignored.
  local stream_file="${plan_path%.md}.stream.jsonl"
  # A stream already sitting here belongs to a previous attempt at this same plan,
  # and the truncation below is the last moment it exists. Recover it first.
  harvest_orphan_attempt "$plan_path"
  : > "$stream_file"

  # The capture directory holds the exited-marker follow_stream watches for. Created here,
  # before anything has been started, and CHECKED: with an unwritable or missing $TMPDIR —
  # a full disk, a sandbox with no temp of its own — mktemp writes nothing to stdout and
  # exits non-zero, and an unchecked assignment would put the marker at `/claude-exited`,
  # where `: >` fails silently and the follower waits for a file that will never appear.
  # There is no timeout anywhere in that path, so the failure mode was a runner sitting
  # silent forever with the plan never finalized. Failing the plan by its own code is the
  # loud version: finalize_plan files it to failed/ with the reason in its progress log.
  # A bare `mktemp -d` is not used because on macOS it ignores $TMPDIR entirely (it asks
  # the OS for the per-user temp), which makes this both untestable and unconfigurable.
  local tmp_root="${TMPDIR:-/tmp}"
  tmp_root="${tmp_root%/}"
  CAPTURE_TMPDIR="$(mktemp -d "$tmp_root/$CAPTURE_TMPDIR_TEMPLATE" 2>/dev/null)"
  if [[ -z "$CAPTURE_TMPDIR" || ! -d "$CAPTURE_TMPDIR" ]]; then
    CAPTURE_TMPDIR=""
    echo "ERROR: could not create a capture directory under $tmp_root — not running $plan_name" >&2
    printf 'failed (exit %s): could not create a capture directory under %s (mktemp -d failed); set TMPDIR to somewhere writable and re-run\n' \
      "$CAPTURE_SETUP_RC" "$tmp_root" >> "$log_path"
    return "$CAPTURE_SETUP_RC"
  fi
  local exited_marker="$CAPTURE_TMPDIR/$CAPTURE_EXITED_MARKER_NAME"

  # The progress log is fed through a FIFO with a tracked PID rather than
  # `tee >(...)`: bash does not wait for a process substitution, so on the
  # failure path — where finalize_plan calls exit immediately — its pending
  # writes could be lost. The explicit wait below closes that race.
  local log_fifo="${plan_path%.md}.logfifo"
  rm -f "$log_fifo"
  mkfifo "$log_fifo"
  log_stream_events "$log_path" < "$log_fifo" &
  local log_pid=$!

  local model
  model="$(extract_model "$plan_path")"
  echo "    model: $model"

  # A wrapper may size the cap per plan (run-verify.sh does: a level-verify and a tier-2
  # escalation are not the same shape of work as the final verify). Optional hook; a
  # wrapper that does not define it keeps whatever CLAUDE_BUDGET_ARGS it set once.
  if declare -F budget_for_plan >/dev/null; then budget_for_plan "$plan_path"; fi

  # ── The capture ────────────────────────────────────────────────────────────
  # `claude` writes $stream_file ITSELF, and everything else reads it. This used to be a
  # single pipeline — claude | tee $stream_file | tee $log_fifo | display_stream — with
  # the file written by a `tee` in the middle of it, which meant the record's liveness
  # depended on every stage after it. display_stream inherits this script's stdout, so a
  # caller that stopped reading (a coordinator's backgrounded Bash command whose stdout
  # was piped onward) killed display_stream with SIGPIPE, then each `tee` on its next
  # write, while claude — whose own stdout was only the pipe into the first tee — ran to
  # completion and exited 0. Nine merged reviews were filed as successes with a 689-byte
  # stream, a 0-byte progress log and total_cost_usd: null. See
  # self/features/stream-capture-file-first/, and RUNNER.md → "Capturing the stream".
  #
  # Now: claude is a background job whose stdout (and stderr, merged as before) is the
  # file; follow_stream tails the file and feeds the FIFO and the display. Nothing
  # downstream of the file can reach it. `wait` on claude's own pid is the exact
  # replacement for the old ${PIPESTATUS[0]}, and the exited-marker written straight
  # after is what lets follow_stream know the file is final — with claude's pid, handed
  # to it below, as the second way of learning the same thing, so no path here can wait
  # on a marker that never arrives (see that function).
  #
  # CLAUDE_TOOL_ARGS is the one security-relevant difference between the runners:
  # run-plans.sh disables Bash, run-verify.sh enables it. build_prompt is the
  # other: each runner tells the executor what kind of pass this is.
  # CLAUDE_BUDGET_ARGS is optional and may be unset (run-plans.sh sets no cap), so it
  # gets the `${a[@]+"${a[@]}"}` form: under `set -u` on bash 3.2 — still the system
  # bash on macOS — expanding an empty array the naive way aborts the run.
  claude -p --model "$model" --permission-mode acceptEdits \
    "${CLAUDE_TOOL_ARGS[@]}" \
    ${CLAUDE_BUDGET_ARGS[@]+"${CLAUDE_BUDGET_ARGS[@]}"} \
    --output-format stream-json --verbose \
    "$(build_prompt "$plan_path" "$log_path")" \
    > "$stream_file" 2>&1 &
  CAPTURE_CLAUDE_PID=$!

  # One subshell for the whole follower pipeline, so $! is something `wait` can hold to
  # until BOTH halves have finished — waiting on display_stream alone would return early
  # every time a closed consumer killed it. The `rm -rf` is the normal path's cleanup and
  # a belt for the abnormal ones; stop_capture removes the directory too, because on a
  # group SIGTERM this subshell dies with the runner and never gets here.
  ( follow_stream "$stream_file" "$exited_marker" "$CAPTURE_CLAUDE_PID" 4> "$log_fifo" | display_stream
    rm -rf "$CAPTURE_TMPDIR" ) &
  local follow_pid=$!

  wait "$CAPTURE_CLAUDE_PID"
  local exit_code=$?
  CAPTURE_CLAUDE_PID=""
  # Only now: claude has been reaped, so every byte it wrote is in the file and this
  # marker cannot be seen a moment too early.
  : > "$exited_marker"

  # In order: the follower drains the rest of the file and closes the FIFO, then the
  # logger sees EOF and finishes. Both waits are what keep the log complete on the
  # failure path, where finalize_plan exits immediately after this returns.
  wait "$follow_pid" 2>/dev/null
  wait "$log_pid" 2>/dev/null
  rm -f "$log_fifo"
  rm -rf "$CAPTURE_TMPDIR"
  CAPTURE_TMPDIR=""

  if stream_shows_usage_limit "$stream_file"; then
    return 2
  fi

  if stream_shows_budget_exhausted "$stream_file"; then
    # Recorded in the log itself so failed/ explains the stop without anyone opening
    # the (gitignored) stream. The cap is enforced after each API call, so the spend
    # reported here overshoots the cap by at most one turn.
    printf 'stopped: reached the run budget (spent $%s)\n' \
      "$(jq -r 'select(.type == "result") | .total_cost_usd // "unknown"' \
         "$stream_file" 2>/dev/null | tail -1)" >> "$log_path"
    return 3
  fi

  if (( exit_code != 0 )); then
    # Put the reason in the progress log itself, so failed/ explains itself even
    # when the plan died before its first mutating tool call.
    printf 'failed (exit %s): %s\n' "$exit_code" "$(stream_failure_reason "$stream_file")" >> "$log_path"
  fi

  return "$exit_code"
}

# Extract a small, committed cost/usage summary from the run's final `result` event, so
# per-plan cost survives after the (gitignored) .stream.jsonl is gone. Called from the
# top of finalize_plan, before any mv, while stream_path is still where run_plan left it.
#
# **`result_event` says whether that event existed.** A run can exit 0, do its work and
# open its PR while its captured stream carries no `result` event at all — it has
# happened, cause unknown (self/BACKLOG.md), and every figure here is then null or zero.
# Without the field the sidecar is indistinguishable from a run that genuinely cost
# nothing, and analysis/report.py prints a bare `$0.0000` for the bucket. `outcome` is
# not the substitute: it is computed from the exit code and says what the plan DID.
# Anything deciding "is this priced" reads `result_event` and the null cost, never
# `outcome` — see analysis/README.md → usage.json.
# Non-fatal: guarded on the stream file existing, jq's stderr is suppressed the same way
# the other two call sites in this file suppress it, and a failed jq run leaves any
# existing sidecar alone rather than replacing it with a truncated one.
#
# **Cumulative across attempts, not last-write-wins.** Resuming a plan is a fresh
# `claude -p` with a fresh session id (RUNNER.md, "How resume works"), and run_plan
# truncates the stream, so overwriting this file would erase every earlier attempt:
# its dollars would vanish from the build/verify roll-up and — since
# capture_planning.py recognises a runner session only by finding its id in some
# usage.json — silently reappear as planning cost. Every total below therefore sums
# over `attempts[]`, whose per-attempt figures stay visible for the breakdown.
write_usage_sidecar() {
  local plan_path="$1"
  local rc="$2"
  local stream_path="$3"
  local usage_path="$4"

  [[ -f "$stream_path" ]] || return 0

  local model outcome
  # Suppress stderr here: extract_model's fallback WARN already printed once from
  # run_plan's own call; a second copy here would just be noise.
  model="$(extract_model "$plan_path" 2>/dev/null)"
  case "$rc" in
    0) outcome="complete" ;;
    2) outcome="inprogress" ;;
    3) outcome="budget_exceeded" ;;
    # Not a run_plan return code — harvest_orphan_attempt's sentinel for an attempt
    # reconstructed after the fact, whose exit status nobody was around to collect.
    killed) outcome="killed" ;;
    *) outcome="failed" ;;
  esac

  # Prior attempts, read back out of the file this call is about to replace. An absent
  # or unparseable sidecar is treated as no history rather than as an error: losing the
  # merge is bad, losing this attempt on top of it would be worse.
  local prev
  prev="$(jq -c '.' "$usage_path" 2>/dev/null || true)"
  [[ -n "$prev" ]] || prev="null"

  # -R -s and fromjson? rather than a plain -s slurp: a killed run can leave a truncated
  # final line, and claude's merged stderr can leave a non-JSON one, either of which
  # would make a plain slurp reject the whole file. $events and $r are spliced in from
  # the shared expressions at the top of this file rather than written out again here —
  # stream_has_result derives the same $r, and the two disagreeing is the defect this
  # sharing exists to prevent.
  local merged
  merged="$(jq -R -s --arg plan "$(basename "$plan_path" .md)" --arg model "$model" \
    --arg outcome "$outcome" --arg repo "$REPO_DIR/" --argjson prev "$prev" "
    ($STREAM_EVENTS_JQ) as \$events
    | (\$events | $STREAM_LAST_RESULT_JQ) as \$r
    "'
    | [ $events[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") ] as $tools
    | ($tools | map(select(.name == "Edit" or .name == "Write" or .name == "MultiEdit" or .name == "NotebookEdit"))) as $edits
    | ($prev // {}) as $p
    | {
        # Every event carries session_id, so a killed run with no result event still
        # yields the one thing the exclusion rule needs.
        session_id: ($r.session_id // $events[0].session_id // null),
        outcome: $outcome,
        total_cost_usd: ($r.total_cost_usd // null),
        num_turns: ($r.num_turns // null),
        duration_ms: ($r.duration_ms // null)
      } as $attempt
    | (($p.attempts // []) | map(select(.session_id != null and .session_id == $attempt.session_id)) | length > 0) as $seen
    | (if $seen
       then (($p.attempts // []) | map(if .session_id != null and .session_id == $attempt.session_id then $attempt else . end))
       else (($p.attempts // []) + [$attempt])
       end) as $attempts
    | {
        plan: $plan, model: $model, outcome: $outcome,
        session_id: $attempt.session_id,
        # Whether the stream carried a result event at all — the fact every figure
        # below depends on, kept separate from `outcome` because the two answer
        # different questions. `outcome` says what the plan DID, from the exit code;
        # this says whether anything measured what it cost. A run that exits 0 with no
        # result event is `outcome: "complete"` AND `result_event: "missing"`, and the
        # nulls beside it then mean "unmeasured", not "free" — the whole difference
        # between a $0 that is a measurement and a $0 that is a hole in the record.
        # Latest attempt only, like `subtype`, `is_error` and `model_usage`.
        # No apostrophes in this block: the jq program is single-quoted in bash.
        result_event: (if $r then "seen" else "missing" end),
        subtype: ($r.subtype // null),
        is_error: $r.is_error,
        # `add` over an empty array is null, which is the honest answer when no attempt
        # produced a result event — and what report.py reads as "unpriced".
        num_turns: ([ $attempts[].num_turns | select(. != null) ] | add),
        duration_ms: ([ $attempts[].duration_ms | select(. != null) ] | add),
        total_cost_usd: ([ $attempts[].total_cost_usd | select(. != null) ] | add),
        usage: {
          input_tokens: (($p.usage.input_tokens // 0) + ($r.usage.input_tokens // 0)),
          cache_creation_input_tokens: (($p.usage.cache_creation_input_tokens // 0) + ($r.usage.cache_creation_input_tokens // 0)),
          cache_read_input_tokens: (($p.usage.cache_read_input_tokens // 0) + ($r.usage.cache_read_input_tokens // 0)),
          output_tokens: (($p.usage.output_tokens // 0) + ($r.usage.output_tokens // 0))
        },
        # Latest attempt only: merging the nested per-model token counts is more jq
        # than the breakdown is worth, and attempts[] already carries per-attempt cost.
        model_usage: ($r.modelUsage // {}),
        permission_denials: (($p.permission_denials // 0) + (($r.permission_denials // []) | length)),
        tool_counts: (
          ($tools | group_by(.name) | map({key: .[0].name, value: length}) | from_entries) as $now
          | reduce ($now | to_entries[]) as $e (($p.tool_counts // {}); .[$e.key] = ((.[$e.key] // 0) + $e.value))
        ),
        files_edited: ((($p.files_edited // []) + ($edits | map(.input.file_path // empty | ltrimstr($repo)))) | unique),
        edit_count: (($p.edit_count // 0) + ($edits | length)),
        attempts: $attempts
      }
    ' "$stream_path" 2>/dev/null || true)"

  [[ -n "$merged" ]] || return 0
  printf '%s\n' "$merged" > "$usage_path"
}

# Called from run_plan immediately before the stream file is truncated. A run killed
# outright (Ctrl-C, SIGKILL) never reaches finalize_plan, so nothing ever recorded that
# attempt — and its stream is about to be overwritten. Without this, that session's id
# appears in no usage.json, capture_planning.py cannot tell it from an interactive
# session, and its spend is re-billed as planning cost on the feature's branch.
#
# Idempotent: only runs when the leftover stream holds a session that `attempts[]` has
# never seen. A previous run that reached finalize_plan by any route — usage limit,
# budget cap, ordinary failure — already recorded itself, so nothing is orphaned.
harvest_orphan_attempt() {
  local plan_path="$1"
  local stream_path="${plan_path%.md}.stream.jsonl"
  local usage_path="${plan_path%.md}.usage.json"

  [[ -f "$stream_path" ]] || return 0

  local stream_sids recorded_sids
  stream_sids="$(jq -R -r 'fromjson? | .session_id // empty' "$stream_path" 2>/dev/null | sort -u || true)"
  [[ -n "$stream_sids" ]] || return 0
  recorded_sids="$(jq -r '.attempts[]?.session_id // empty' "$usage_path" 2>/dev/null | sort -u || true)"

  if [[ -z "$(comm -23 <(printf '%s\n' "$stream_sids") <(printf '%s\n' "$recorded_sids"))" ]]; then
    return 0
  fi

  echo "    recovering usage from a previous run that never finalized"
  write_usage_sidecar "$plan_path" "killed" "$stream_path" "$usage_path"
}

# Move a plan and its sidecars into one of the queue directories.
#
# Recreates the destination first, because run_all's `mkdir -p` is not enough to
# guarantee it still exists by the time a run ends. A queue directory stays empty until
# something lands in it, git does not track empty directories, and the verify executor
# has bash: one `git stash -u` / `git stash pop` in the working tree removes and does not
# restore them (the plan queue is untracked, so `-u` sweeps it), and any checkout that
# empties a directory prunes it the same way. Observed once: every mv below failed with
# "No such file or directory", so a budget-capped plan stayed in inprogress/ — where the
# NEXT run resumes it and buys the mis-scoped brief another full budget, which is exactly
# what routing it to failed/ exists to prevent.
#
# Sets route_failures to the number of moves that still failed, so the caller reports a
# stranded plan instead of a clean stop. Never fatal on its own: a plan in the wrong
# folder is recoverable, and aborting here would skip the exit_reason that explains it.
route_plan_files() {
  local dest="$1"
  shift
  local src
  src="$(dirname "$1")"
  route_failures=0
  mkdir -p "$dest" || echo "WARN: could not create $dest" >&2
  local f
  for f in "$@"; do
    [[ -e "$f" ]] || continue
    mv "$f" "$dest/" || route_failures=$(( route_failures + 1 ))
  done
  if (( route_failures > 0 )); then
    echo "WARN: $route_failures file(s) could not be moved into $dest — left in $src" >&2
  fi
}

# Appended to an exit reason when routing failed, so the summary block says the plan is
# stranded rather than implying it was filed. Silent when every move succeeded.
route_warning() {
  (( route_failures > 0 )) || return 0
  printf ' [WARNING: %s file(s) could not be moved — plan left in inprogress/ and the next run will RESUME it; move it by hand]' "$route_failures"
}

# After run_plan returns, route the plan + log to the right folder.
finalize_plan() {
  local plan_path="$1"
  local rc="$2"
  local log_path="${plan_path%.md}.progress.md"
  local stream_path="${plan_path%.md}.stream.jsonl"
  local usage_path="${plan_path%.md}.usage.json"
  local plan_name
  plan_name="$(basename "$plan_path")"

  write_usage_sidecar "$plan_path" "$rc" "$stream_path" "$usage_path"
  stamp_timing plan_end plan="${plan_name%.md}" queue="$QUEUE" rc="$rc"

  if (( rc == 2 )); then
    exit_reason="stopped: Claude usage limit reached on $plan_name (left in inprogress for next run)"
    exit 1
  fi

  # Deliberately failed/, not inprogress/: a resume would just buy the same brief another
  # budget's worth of turns, which is the behaviour the cap exists to prevent. Hitting it
  # means the plan asked for more than a verify pass should do, and that is a question for
  # whoever wrote it — not something the runner should quietly pay to finish.
  if (( rc == 3 )); then
    route_plan_files "$FAILED_DIR" "$plan_path" "$log_path" "$stream_path" "$usage_path"
    exit_reason="stopped: $plan_name exceeded its run budget (moved to failed; re-scope the brief)$(route_warning)"
    # A wrapper with work to do AFTER a capped plan (run-review.sh opens the PR when the
    # report was written before the cap fired) defines this hook; run_all then returns
    # to it instead of exiting here. The plan is still filed to failed/ and the wrapper
    # still exits non-zero — only who gets to act on the stop changes.
    if declare -F after_budget_exceeded >/dev/null; then after_budget_exceeded; return 0; fi
    exit 1
  fi

  if (( rc != 0 )); then
    # The raw stream is the only record of *why* it failed — keep it.
    route_plan_files "$FAILED_DIR" "$plan_path" "$log_path" "$stream_path" "$usage_path"
    exit_reason="stopped: claude exited with code $rc on $plan_name (moved to failed)$(route_warning)"
    # LEVEL_PAUSE_RC is reserved for the sentinel path; a claude that happens to exit with
    # it must not make run-batch.sh run a level-verify and carry on past a failed plan.
    if (( rc == LEVEL_PAUSE_RC )); then exit 1; fi
    exit "$rc"
  fi

  # rc == 0 with no `result` event in the stream is the one combination that is never
  # normal: every ending claude -p has emits one, so a clean exit without it means the
  # end of the stream was lost between claude and this file. That is what went unnoticed
  # for nine features — each filed here, as a success, with a null cost and an empty
  # progress log — so it gets a warning naming the plan and the file, and the file is
  # kept (as it always was) for whoever reads it. Computed before the move so the stream
  # is still where run_plan left it, printed after so it can name where it landed.
  local capture_looks_truncated=0
  if ! stream_has_result "$stream_path"; then capture_looks_truncated=1; fi

  # Keep the full event stream even on success: it is the complete record of what
  # the model did — tool inputs and results the terminal summary omits. Gitignored.
  route_plan_files "$COMPLETE_DIR" "$plan_path" "$log_path" "$stream_path" "$usage_path"

  if (( capture_looks_truncated )); then
    echo "WARN: $plan_name exited 0 but its captured stream holds no result event — the capture may have been truncated, and this plan's cost, turn count and progress log are incomplete" >&2
    echo "      stream kept at $COMPLETE_DIR/$(basename "$stream_path") (gitignored, never committed)" >&2
  fi

  # A stranded success is as bad as a stranded failure: the plan is still in inprogress/,
  # so the next run resumes a plan that is already done. Carry it into the summary.
  exit_reason="$exit_reason$(route_warning)"
  echo "=== Finished: $plan_name ==="
  echo ""
}

# Fail fast on missing prerequisites. Both jq call sites suppress stderr (a malformed
# event must not spam the terminal), which means a missing jq would otherwise degrade
# silently in the worst possible way: no terminal output, an empty progress log, and a
# resume with no hints — while claude still exits 0 and every plan is filed complete.
# Checked before the EXIT trap is installed, so the failure prints plainly.
require_tools() {
  local missing=()
  local tool
  for tool in claude jq; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if (( ${#missing[@]} > 0 )); then
    echo "ERROR: missing required tool(s): ${missing[*]}" >&2
    echo "  claude — the Claude Code CLI that executes each plan" >&2
    echo "  jq     — parses the event stream into the progress log and terminal output" >&2
    exit 127
  fi
}

# Two-phase driver: resume anything in inprogress/, then drain incomplete/.
run_all() {
  require_tools

  # Survive a consumer that stops reading this script's stdout — and stop writing to it.
  # Ruling 1 of self/features/stream-capture-file-first says a closed consumer must not
  # fail the plan, and that is not only about the capture: every echo below goes to the
  # same stdout, so without this the runner died of SIGPIPE at the third line of run_plan
  # (`echo "    model: …"`), before claude had even started, whenever it was launched
  # with its output piped onward and the reader went away.
  #
  # Both halves of the handler are load-bearing:
  #
  #   exec >/dev/null   Point this shell's own output somewhere that cannot break. A
  #                     runner that keeps writing to a dead pipe takes a SIGPIPE per
  #                     line and prints a `write error` for each.
  #   printf '\n'       Flush bash's stdio buffer, now that flushing can succeed. This
  #                     is NOT cosmetic. The bytes of the write that failed are still
  #                     sitting in that buffer, and every fork from here on — every
  #                     `$(…)` that runs a function or a list, every `<(…)` — inherits
  #                     the dirty buffer and flushes it into its OWN stdout, which is
  #                     the substitution's pipe. Observed while building this: with the
  #                     redirect alone, `$(wc -c < "$stream")` came back as the byte
  #                     count plus the text of the failed echo, `$(build_prompt …)` fed
  #                     that text to claude, and `<(list_plans …)` handed run_all
  #                     "=== Finished: <plan>.md ===" as the next plan to run — an
  #                     infinite loop over garbage filenames. One successful write
  #                     clears it; a zero-byte one (`printf ''`) does not.
  #
  # A HANDLER, deliberately not `trap '' PIPE`. Bash resets a handled signal to its
  # default in exec'd children but propagates an *ignored* one through exec, so ignoring
  # here would silently change the SIGPIPE disposition of claude, jq, git, gh — and of a
  # consuming repo's own plans/gate.sh and plans/pr.sh, where a `foo | head -1` would
  # stop dying quietly and start printing write errors instead. Both forms keep this
  # shell alive; only this one has no blast radius.
  trap 'exec >/dev/null; printf "\n"' PIPE

  cd "$REPO_DIR"
  # Before resolve_feature, not after: list_plans globs, and without nullglob an empty
  # queue directory expands to the literal pattern and reads as "has work queued".
  shopt -s nullglob

  resolve_feature "${1:-}" || exit 2

  if [[ -z "$FEATURE_SLUG" ]]; then
    echo "No ${PLAN_KIND}s queued under $FEATURES_LABEL/*/$QUEUE/incomplete. Nothing to do."
    return 0
  fi

  PLAN_DIR="$FEATURES_DIR/$FEATURE_SLUG/$QUEUE"
  INCOMPLETE_DIR="$PLAN_DIR/incomplete"
  INPROGRESS_DIR="$PLAN_DIR/inprogress"
  COMPLETE_DIR="$PLAN_DIR/complete"
  FAILED_DIR="$PLAN_DIR/failed"
  mkdir -p "$INCOMPLETE_DIR" "$INPROGRESS_DIR" "$COMPLETE_DIR" "$FAILED_DIR"

  echo "Feature: $FEATURE_SLUG   queue: $QUEUE"
  stamp_timing pass_start queue="$QUEUE"

  # Report the resolved slug to a caller that asked for it, so run-batch.sh can hand the
  # verify pass the same feature the build pass chose instead of letting it infer again.
  if [[ -n "${FEATURE_SLUG_OUT:-}" ]]; then
    echo "$FEATURE_SLUG" > "$FEATURE_SLUG_OUT"
  fi

  trap on_interrupt INT TERM
  trap print_status EXIT

  # --- Phase 1: resume anything left in inprogress/ from a previous run. ---
  for plan_path in $(list_plans "$INPROGRESS_DIR"); do
    current_plan="$(basename "$plan_path")"
    local log_path="${plan_path%.md}.progress.md"
    touch "$log_path"  # log should already exist, but be safe
    echo "Resuming in-progress $PLAN_KIND: $current_plan"
    run_plan "$plan_path"
    finalize_plan "$plan_path" $?
  done

  # --- Phase 2: process the incomplete queue in order. ---
  while :; do
    local pending=()
    while IFS= read -r p; do pending+=("$p"); done < <(list_plans "$INCOMPLETE_DIR")
    (( ${#pending[@]} == 0 )) && break

    local plan_file="${pending[0]}"
    current_plan="$(basename "$plan_file")"
    if is_gate_sentinel "$plan_file"; then
      local level_nn="${current_plan%%-*}"
      run_level_gate "$level_nn"
      mv "$plan_file" "$COMPLETE_DIR/$current_plan"
      if [[ "$QUEUE" == "auto" ]] && level_verify_queued "$level_nn"; then
        if level_gate_green "$level_nn"; then
          skip_level_verify "$level_nn"
        else
          # Report the paused level to a caller that asked for it, the same handshake
          # FEATURE_SLUG_OUT is: this process knows which sentinel it stopped at, and
          # run-batch.sh would otherwise have to re-derive the number by sorting
          # auto/complete/. Written before the exit reason so a stop between the two
          # cannot leave a stale number behind.
          if [[ -n "${LEVEL_PAUSE_NN_OUT:-}" ]]; then
            echo "$level_nn" > "$LEVEL_PAUSE_NN_OUT"
          fi
          exit_reason="paused at level boundary $current_plan — a level-verify plan is queued; run: run-verify.sh $SELF_ARG--up-to $level_nn $FEATURE_SLUG, then re-run run-plans.sh $SELF_ARG$FEATURE_SLUG to continue"
          exit "$LEVEL_PAUSE_RC"
        fi
      fi
      continue
    fi
    # A brief that still carries the placeholder feature-start.sh wrote is not a brief.
    # An empty review queue is a clean no-op, which is exactly how a forgotten brief
    # would go unnoticed; a stub that fails loudly cannot be skipped by accident. Filed
    # to failed/ with the reason, no model called, and the pass stops here.
    # Anchored: the stub puts the marker at the start of a line, and a real brief may
    # mention it mid-sentence — this feature's own review brief did, and was refused.
    if grep -q '^@@TODO@@' "$plan_file"; then
      local stub_log="$FAILED_DIR/${current_plan%.md}.progress.md"
      echo "refused: $current_plan still contains @@TODO@@ — the stub feature-start.sh wrote was never replaced with a real brief; write it and re-queue the plan" > "$stub_log"
      mv "$plan_file" "$FAILED_DIR/$current_plan"
      echo "=== refused $current_plan: still contains @@TODO@@ (moved to failed) ==="
      exit_reason="stopped: $current_plan still contains @@TODO@@ (moved to failed; write the brief and move it back to incomplete/)"
      exit 1
    fi
    local inprogress_plan="$INPROGRESS_DIR/$current_plan"
    local inprogress_log="${inprogress_plan%.md}.progress.md"

    mv "$plan_file" "$inprogress_plan"
    : > "$inprogress_log"  # fresh empty log for a fresh plan

    run_plan "$inprogress_plan"
    finalize_plan "$inprogress_plan" $?
  done

  current_plan=""
}
