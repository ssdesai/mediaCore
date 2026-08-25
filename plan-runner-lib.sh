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

print_status() {
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

on_interrupt() {
  # Leave any in-progress plan + its log where they are; next run resumes them.
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
  "$GATE_SCRIPT" "$label"
  rc=$?
  unset GATE_EXPECTED_RED GATE_DEFERRED
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

# Extract a one-line failure reason from the final `result` event, so a failed
# plan is self-documenting even when it died before its first mutating tool call.
stream_failure_reason() {
  local stream_file="$1"
  jq -r 'select(.type == "result" and .is_error == true) |
         (.result // .error // .subtype // "unknown error" | tostring)' \
     "$stream_file" 2>/dev/null | tail -1
}

# Inspect a captured stream-json file for usage/rate-limit indicators.
# Returns 0 if a limit was hit, 1 otherwise. Only the final `result` event is
# inspected — the authoritative signal from claude -p about why the run ended.
# Scanning the whole stream would false-positive on any file or message that
# merely contains a phrase like "rate limit".
stream_shows_usage_limit() {
  local stream_file="$1"

  jq -e 'select(.type == "result" and .is_error == true) |
         select((.result // .error // .subtype // "" | tostring)
                | test("usage.?limit|rate.?limit|hit.{0,15}limit|limit.{0,20}reset|quota|exceeded|insufficient.?credits|\\b429\\b|\\b529\\b|overloaded"; "i"))' \
     "$stream_file" >/dev/null 2>&1
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

  # The raw event stream is kept beside the plan rather than in a temp file, so
  # finalize_plan can move it into complete/ or failed/ alongside the plan for
  # later analysis. Gitignored.
  local stream_file="${plan_path%.md}.stream.jsonl"
  # A stream already sitting here belongs to a previous attempt at this same plan,
  # and the truncation below is the last moment it exists. Recover it first.
  harvest_orphan_attempt "$plan_path"
  : > "$stream_file"

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

  # CLAUDE_TOOL_ARGS is the one security-relevant difference between the runners:
  # run-plans.sh disables Bash, run-verify.sh enables it. build_prompt is the
  # other: each runner tells the executor what kind of pass this is.
  # PIPESTATUS[0] preserves claude's exit code past both tee and display_stream.
  # CLAUDE_BUDGET_ARGS is optional and may be unset (run-plans.sh sets no cap), so it
  # gets the `${a[@]+"${a[@]}"}` form: under `set -u` on bash 3.2 — still the system
  # bash on macOS — expanding an empty array the naive way aborts the run.
  claude -p --model "$model" --permission-mode acceptEdits \
    "${CLAUDE_TOOL_ARGS[@]}" \
    ${CLAUDE_BUDGET_ARGS[@]+"${CLAUDE_BUDGET_ARGS[@]}"} \
    --output-format stream-json --verbose \
    "$(build_prompt "$plan_path" "$log_path")" 2>&1 \
    | tee "$stream_file" \
    | tee "$log_fifo" \
    | display_stream
  local exit_code=${PIPESTATUS[0]}

  # tee closed the FIFO when the pipeline ended; wait for the logger to drain it
  # before anyone reads or moves the log.
  wait "$log_pid" 2>/dev/null
  rm -f "$log_fifo"

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

  local merged
  merged="$(jq -R -s --arg plan "$(basename "$plan_path" .md)" --arg model "$model" \
    --arg outcome "$outcome" --arg repo "$REPO_DIR/" --argjson prev "$prev" '
    # -R -s and fromjson? rather than a plain -s slurp: a killed run can leave a
    # truncated final line, and slurping as JSON would reject the whole file over it.
    (split("\n") | map(select(length > 0) | fromjson?)) as $events
    | ($events | map(select(.type == "result")) | last) as $r
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

  # Keep the full event stream even on success: it is the complete record of what
  # the model did — tool inputs and results the terminal summary omits. Gitignored.
  route_plan_files "$COMPLETE_DIR" "$plan_path" "$log_path" "$stream_path" "$usage_path"
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
          exit_reason="paused at level boundary $current_plan — a level-verify plan is queued; run: run-verify.sh $SELF_ARG--up-to $level_nn $FEATURE_SLUG, then re-run run-plans.sh $SELF_ARG$FEATURE_SLUG to continue"
          exit "$LEVEL_PAUSE_RC"
        fi
      fi
      continue
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
