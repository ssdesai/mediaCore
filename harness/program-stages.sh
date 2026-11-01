#!/usr/bin/env bash
# The program cell's stages: sourced by harness/run.sh, never run.
#
# A program cell is one orchestrator session running an ordered list of features under one
# agentTooling version, one implementer session per feature (harness/README.md → "The
# program row"). The harness drives the orchestrator turn by turn — `claude -p --session-id`
# for the program brief, `--resume` once per feature and once for the record — and runs each
# implementer itself, in that feature's own worktree, with the orchestrator's brief as its
# prompt. Review, rework, accept and capture then run per feature branch through the very
# functions an ordinary cell uses (do_review, do_rework, do_accept, do_capture), which is why
# load_program_feature sets the per-cell globals those read.
#
# Uses run.sh's globals and functions (stage_begin, stage_end, setup_tree, write_stage_manifest,
# capture_one, num, say, dry, …) and lib.sh's. Everything a `--from` resume needs is re-derived
# from program.json, experiment.json and the state files — never from a previous process.
#
# State files: the program's is <experiment-dir>/state/<PBRANCH>.json, each feature's
# <experiment-dir>/state/<featureBranch>.json. Keys this file adds beyond a cell's:
#   program   session_id, orchestrator_sessions[], orchestrator_session_starts{id: first
#             call start}, orchestrator_calls, t_method_start, t_method_end,
#             cost_overhead_usd, record_report ({…}|null), method_failed,
#             orchestrator_first_call_started (instant the first --session-id call began;
#             set with orchestrator_calls still 0 means that call never completed)
#   feature   position, program, depends_on_previous, start_point, brief_written, method
#             (the chosen one), session, t_implementer_start, t_implementer_end, pr_base,
#             tip, dependency_ok, failure_reason, feature_done, unpriced_reason (string|null)

# ── Stage names (HARNESS_PROGRAM_STAGES, lib.sh, is the list) ────────────────
PSTAGE_SETUP="setup"
# Setup outcome of a dependent feature whose start point's gate was red
PROGRAM_GATE_RED_RAN_OUTCOME="gate-red-ran-anyway"
PSTAGE_BRIEF="brief"
PSTAGE_LOOP="loop"
PSTAGE_COLLECT="collect"
PSTAGE_REVIEW="review"
PSTAGE_REWORK="rework"
PSTAGE_ACCEPT="accept"
PSTAGE_CAPTURE="capture"
PSTAGE_RECORD="record"
# The cell stage a feature's own state file records for its implementer.
FSTAGE_METHOD="method"
# `--from method` (the cell stage) names the program's loop.
PROGRAM_METHOD_STAGE_ALIAS="method"

# ── Where things live ────────────────────────────────────────────────────────
PROGRAM_BRIEFS_ROOT="plans/programs"        # inside the program tree
PROGRAM_BRIEFS_SUBDIR="briefs"
PROGRAM_BRIEF_NAME_FORMAT='%02d-%s.md'
PROGRAM_RECORD_ROOT="agentTooling/self/orchestrations"   # inside the program tree
PROGRAM_RECORD_NAME="README.md"
PROGRAM_REPORT_NAME="report.json"
PROGRAM_START_SCRIPT="orchestration-start.sh"
PROGRAM_CAPTURE_SCRIPT="orchestration-capture.sh"
PROGRAM_MANIFEST_PY="agentTooling/analysis/manifest.py"
PROGRAM_REPORT_PY="analysis/report.py"
PROGRAM_COST_SCRIPT="program_cost.py"
PROGRAM_PROMPT_TEMPLATE_BRIEF="program-brief.md"
PROGRAM_PROMPT_TEMPLATE_FEATURE="program-feature.md"
PROGRAM_PROMPT_TEMPLATE_COLLECT="program-collect.md"
PROGRAM_ORCHESTRATOR_TAG="orchestrator"     # in log file names

# ── What the orchestrator and the implementer say and do ─────────────────────
# The last line of a feature turn's reply names the implementer's method.
PROGRAM_METHOD_LINE_SED='s/^METHOD:[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*$/\1/p'
PROGRAM_DEFAULT_METHOD="direct"
PROGRAM_HAND_METHOD="hand"
PROGRAM_NO_PREVIOUS_TEXT="none yet — this is the first feature."
PROGRAM_OUTCOME_MAX_CHARS=4000              # of the previous implementer's report quoted forward
PROGRAM_COST_FORMAT='%.4f'
PROGRAM_FIGURE_FORMAT='%.4f'
PROGRAM_START_SUBJECT_FORMAT='%s: start the orchestration record'
PROGRAM_BRIEF_SUBJECT_FORMAT='%s: brief for %s'
PROGRAM_COLLECT_SUBJECT_FORMAT='%s: orchestration record (left over after the collect turn)'
PROGRAM_RECORD_FREEZE_SUBJECT_FORMAT='%s: freeze the orchestration record'
PROGRAM_CAPTURE_SUBJECT_FORMAT='%s: freeze the harness cost capture'
PROGRAM_MANIFEST_TITLE_FORMAT='%s — %s built by the %s method under the %s program'
# Why a feature's cost_method_usd is not a measurement (the row's unpriced_reason)
PROGRAM_UNPRICED_NO_MANIFEST="no implementer ran: the feature has no manifest directory, so nothing was priced"
PROGRAM_UNPRICED_MISSED_FORMAT='captured $%s against $%s reported by claude: the capture missed the session (check the manifest branch and session window, or the session'"'"'s project directory)'
PROGRAM_UNPRICED_FLOOR_PCT=0.9       # captured below this share of reported means a missed session
PROGRAM_ORCH_CALL_BRIEF="brief"
PROGRAM_ORCH_CALL_FEATURE="feature"
PROGRAM_ORCH_CALL_COLLECT="collect"

# HARNESS_PR_BASE is both the forge's base (lib.sh) and what the @@PR_BASE@@ placeholder
# reads; the prompts overwrite it per feature, so the real default is kept here, at source time.
PROGRAM_DEFAULT_PR_BASE="$HARNESS_PR_BASE"

# ── Program-level globals (one program cell at a time) ───────────────────────
PROGRAM=""; PROGRAM_DIR=""; PROGRAM_JSON=""
PBRANCH=""; PSLUG=""; PTREE=""; PSTATE=""; PSTEM=""
PBASE=""; PREPO_PATH=""; PREMOTE=""; PREPO_NAME=""
PGATE_COMMAND=""; PGATE_GREEN=""; PGATE_MINUTES=""
NFEAT=0
PF_FIXTURE=(); PF_DEPENDS=(); PF_PIN=(); PF_BRANCH=(); PF_SLUG=(); PF_TREE=()
ORCH_RESULT=""; ORCH_RC=0

# ── Bookkeeping ──────────────────────────────────────────────────────────────
pstage_begin() { harness_log "$PBRANCH — program stage $1"; harness_state_stage "$PSTATE" "$1" start "$(harness_utc_now)"; }
pstage_end()   { harness_state_stage "$PSTATE" "$1" end "$(harness_utc_now)"; harness_state_stage "$PSTATE" "$1" outcome "$2"; }

# stage_wanted over the program's stage list; the cell stage `method` means `loop`.
program_stage_wanted() {
  local stage="$1" from="$FROM_STAGE" seen=0 s
  [[ -n "$from" ]] || return 0
  [[ "$from" != "$PROGRAM_METHOD_STAGE_ALIAS" ]] || from="$PSTAGE_LOOP"
  for s in $HARNESS_PROGRAM_STAGES; do
    [[ "$s" == "$from" ]] && seen=1
    if [[ "$s" == "$stage" ]]; then
      if (( seen )); then return 0; else return 1; fi
    fi
  done
  return 1
}

pstate_or() {  # $1 state key, $2 fallback — a state value wins, as state_or does for a cell
  local v; v="$(harness_state_get "$PSTATE" "$1")"
  if [[ -n "$v" ]]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}

program_brief_dir()  { printf '%s/%s/%s/%s' "$PTREE" "$PROGRAM_BRIEFS_ROOT" "$PSLUG" "$PROGRAM_BRIEFS_SUBDIR"; }
program_brief_path() {  # $1 index (0-based)
  local name
  name="$(printf "$PROGRAM_BRIEF_NAME_FORMAT" "$(( $1 + 1 ))" "${PF_FIXTURE[$1]}")"
  printf '%s/%s' "$(program_brief_dir)" "$name"
}
program_record_relpath() { printf '%s/%s/%s' "$PROGRAM_RECORD_ROOT" "$PSLUG" "$PROGRAM_RECORD_NAME"; }
program_record_path()    { printf '%s/%s' "$PTREE" "$(program_record_relpath)"; }
program_fstate()         { printf '%s/%s.json' "$STATE_DIR" "${PF_BRANCH[$1]}"; }   # $1 index

program_method_valid() {  # $1 method name
  local m="$1"
  [[ -n "$m" ]] || return 1
  [[ " $PROGRAM_CHOICE_METHODS " == *" $m "* ]] && return 0
  [[ " $PROGRAM_RESERVED_METHODS " != *" $m "* && -d "$HARNESS_METHODS_DIR/$m" ]]
}

# The branch a feature's PR targets: the previous feature's branch for a dependent one
# (strict: only when that branch's tip was recorded), else the forge's usual base.
program_pr_base() {  # $1 index, $2 strict(1)|plan(0)
  local i="$1" strict="$2"
  if [[ "${PF_DEPENDS[$i]}" == true ]] && (( i > 0 )); then
    if (( ! strict )) || [[ -n "$(harness_state_get "$(program_fstate $(( i - 1 )))" tip)" ]]; then
      printf '%s' "${PF_BRANCH[$(( i - 1 ))]}"; return 0
    fi
  fi
  printf '%s' "$PROGRAM_DEFAULT_PR_BASE"
}

# ── Resolution ───────────────────────────────────────────────────────────────
resolve_program_cell() {  # program repeat arm armsha
  PROGRAM="$1"; REPEAT="$2"; ARM="${3:-}"; ARM_SHA="${4:-}"
  [[ "$ARM" != "-" ]] || { ARM=""; ARM_SHA=""; }
  PROGRAM_DIR="$CONSUMER_ROOT/$HARNESS_PROGRAMS_RELDIR/$PROGRAM"
  PROGRAM_JSON="$PROGRAM_DIR/$HARNESS_PROGRAM_FILE"
  [[ -f "$PROGRAM_JSON" ]] || harness_die "no program at $PROGRAM_JSON"
  harness_program_check "$PROGRAM_JSON" "$FIXTURES_DIR" || harness_die "program $PROGRAM fails its checks (above)"
  if [[ -n "$ARM" ]]; then
    [[ "$ARM" =~ $HARNESS_ARM_LABEL_RE ]] || harness_die "arm label must be bare lower-case letters: $ARM"
    [[ -n "$ARM_SHA" ]] || harness_die "arm $ARM names no agentTooling commit in $EXPERIMENT_JSON"
  fi

  FIXTURE=""; METHOD="$HARNESS_PROGRAM_METHOD"
  # The program's repository is the consumer (harness_program_check above refused a repo
  # block naming another).
  PREPO_PATH="$CONSUMER_ROOT"
  PREPO_NAME="$(harness_repo_name "$(git -C "$CONSUMER_ROOT" config --get "remote.$CONSUMER_IDENTITY_REMOTE.url" 2>/dev/null || basename "$CONSUMER_ROOT")")"
  PREMOTE="$(jq -r '.repo.remote // "origin"' "$PROGRAM_JSON")"
  PBASE="$(harness_json "$PROGRAM_JSON" .base)"
  PGATE_COMMAND="$(harness_program_gate_field "$PROGRAM_JSON" "$FIXTURES_DIR" command)"
  PGATE_GREEN="$(harness_program_gate_field "$PROGRAM_JSON" "$FIXTURES_DIR" green)"
  PGATE_MINUTES="$(harness_program_gate_field "$PROGRAM_JSON" "$FIXTURES_DIR" minutes)"
  [[ -n "$PGATE_MINUTES" ]] || PGATE_MINUTES="a few"

  PSTEM="$(jq -r --arg p "$PROGRAM" '.branch_stem_override[$p] // empty' "$EXPERIMENT_JSON")"
  [[ -n "$PSTEM" ]] || PSTEM="$(harness_json "$PROGRAM_JSON" .branch_stem)"
  PBRANCH="$(harness_branch_name "$PSTEM" "$HARNESS_PROGRAM_METHOD" "$REPEAT" "$REPEATS" "$ARM")"
  PSLUG="$(harness_slug_of_branch "$PBRANCH")"
  PTREE="$(harness_worktree_path "$PREPO_PATH" "$PBRANCH")"
  PSTATE="$STATE_DIR/$PBRANCH.json"

  local i fx fstem
  PF_FIXTURE=(); PF_DEPENDS=(); PF_PIN=(); PF_BRANCH=(); PF_SLUG=(); PF_TREE=()
  NFEAT="$(jq -r '.features | length' "$PROGRAM_JSON")"
  for (( i = 0; i < NFEAT; i++ )); do
    fx="$(jq -r --argjson i "$i" '.features[$i].fixture' "$PROGRAM_JSON")"
    PF_FIXTURE[$i]="$fx"
    PF_DEPENDS[$i]="$(jq -r --argjson i "$i" '.features[$i].depends_on_previous // false' "$PROGRAM_JSON")"
    PF_PIN[$i]="$(jq -r --argjson i "$i" '.features[$i].method // empty' "$PROGRAM_JSON")"
    fstem="$(jq -r --arg f "$fx" '.branch_stem_override[$f] // empty' "$EXPERIMENT_JSON")"
    [[ -n "$fstem" ]] || fstem="$(harness_json "$FIXTURES_DIR/$fx/fixture.json" .branch_stem)"
    # The program stem sits where an ordinary cell's method does.
    PF_BRANCH[$i]="$(harness_branch_name "$fstem" "$PSTEM" "$REPEAT" "$REPEATS" "$ARM")"
    PF_SLUG[$i]="$(harness_slug_of_branch "${PF_BRANCH[$i]}")"
    PF_TREE[$i]="$(harness_worktree_path "$PREPO_PATH" "${PF_BRANCH[$i]}")"
  done
  export HARNESS_LOG_DIR="$LOG_DIR" HARNESS_BRANCH_NAME="$PBRANCH"
}

# Set the per-cell globals for feature i, so do_review, do_rework, do_accept, do_capture and
# capture_one run unchanged on it. BASE is the program's (the fixture's own is ignored).
load_program_feature() {  # $1 index
  local i="$1" v
  FIXTURE="${PF_FIXTURE[$i]}"
  BRANCH="${PF_BRANCH[$i]}"; SLUG="${PF_SLUG[$i]}"; TREE="${PF_TREE[$i]}"
  STATE="$STATE_DIR/$BRANCH.json"
  require_fixture
  REPO_PATH="$PREPO_PATH"; REMOTE="$PREMOTE"; BASE="$PBASE"
  SPEC_REPO="$(harness_fixture_spec_repo "$FIXTURE_JSON")" || exit 1
  read_fixture_fields
  # A gate the program names explicitly governs its features too.
  v="$(harness_json "$PROGRAM_JSON" .gate.command)"
  if [[ -n "$v" ]]; then
    GATE_COMMAND="$v"
    GATE_GREEN="$(harness_json "$PROGRAM_JSON" .gate.green)"
    GATE_MINUTES="$(jq -r '.gate.minutes // "a few"' "$PROGRAM_JSON")"
  fi
  SPEC_TREE="$(harness_spec_worktree_path "$SPEC_REPO" "$FIXTURE")"
  BRIEF_FILE="$TREE/plans/features/$SLUG/BRIEF.md"
  reset_cell_results
  METHOD="$(harness_state_get "$STATE" method)"
  [[ -n "$METHOD" ]] || METHOD="$PROGRAM_DEFAULT_METHOD"
  if [[ "$(harness_state_get "$STATE" method_failed)" == true ]]; then METHOD_FAILED=true; fi
  PR_URL="$(harness_state_get "$STATE" pr_url)"
  GATE_COUNTS_PR_OPEN="$(harness_state_get "$STATE" gate_counts_pr_open)"
  set_template_vars
}

# The placeholders every program prompt can name that do not depend on a feature.
set_program_common_vars() {
  HARNESS_PROGRAM="$PROGRAM"; HARNESS_PROGRAM_SLUG="$PSLUG"
  HARNESS_PROGRAM_BRANCH="$PBRANCH"; HARNESS_PROGRAM_TREE="$PTREE"
  HARNESS_ARM="${ARM:-none}"; HARNESS_FEATURE_COUNT="$NFEAT"
  HARNESS_BRIEF_DIR="$(program_brief_dir)"
  HARNESS_RECORD_PATH="$(program_record_path)"
  HARNESS_BRIEF_TEMPLATE="$PTREE/agentTooling/templates/plans/ORCHESTRATOR_BRIEF.md"
}

# Program scope for the brief and collect prompts: the program's own branch and tree, and
# every feature-specific placeholder emptied so nothing of the last-loaded feature leaks.
set_program_scope_vars() {
  set_program_common_vars
  harness_build_isolation "$PREPO_PATH" "$PTREE"
  HARNESS_BRANCH="$PBRANCH"; HARNESS_SLUG="$PSLUG"; HARNESS_BASE="$PBASE"
  HARNESS_AGENT_TOOLING="$PTREE/agentTooling"
  HARNESS_EXPERIMENTS_DIR="$CONSUMER_ROOT/plans/experiments"
  HARNESS_GATE_COMMAND="$PGATE_COMMAND"; HARNESS_GATE_MINUTES="$PGATE_MINUTES"
  HARNESS_FIXTURE=""; HARNESS_FACTS=""; HARNESS_SPEC_TREE=""; HARNESS_SPEC_PATH=""
  HARNESS_SPEC_SECTIONS=""; HARNESS_REVIEW_BRIEF=""; HARNESS_FINDINGS=""; HARNESS_FINDINGS_TEXT=""
  HARNESS_BRIEF=""
  HARNESS_POSITION=""; HARNESS_PR_BASE="$PROGRAM_DEFAULT_PR_BASE"; HARNESS_DEPENDS=""; HARNESS_METHOD_CHOICE=""
  HARNESS_BRIEF_PATH=""; HARNESS_FEATURES=""; HARNESS_RECORD_COMMANDS=""
  HARNESS_PREV_OUTCOME=""
}

# ── Orchestrator calls ───────────────────────────────────────────────────────
orch_current_session() {  # the MOST RECENT id a call reported, else the one we minted
  local id
  id="$(jq -r '(.orchestrator_sessions // []) | last // empty' "$PSTATE" 2>/dev/null)"
  [[ -n "$id" ]] || id="$(harness_state_get "$PSTATE" session_id)"
  printf '%s' "$id"
}

program_session_id() {  # mint once, reuse on resume
  local sid
  sid="$(harness_state_get "$PSTATE" session_id)"
  if [[ -z "$sid" ]]; then
    sid="$(harness_new_session_id)"
    harness_state_set_str "$PSTATE" session_id "$sid"
  fi
  printf '%s' "$sid"
}

# Record the (session_id, start) a call's result reports; false when it reports none.
orch_record_session() {  # $1 result file, $2 call start
  local id tmp
  id="$(harness_claude_session "$1")"
  [[ -n "$id" ]] || return 1
  tmp="$PSTATE.tmp"
  jq --arg id "$id" --arg s "$2" '
      .orchestrator_sessions = ((.orchestrator_sessions // []) | if index($id) then . else . + [$id] end)
    | .orchestrator_session_starts = ((.orchestrator_session_starts // {}) | if has($id) then . else .[$id] = $s end)' \
    "$PSTATE" > "$tmp" && mv "$tmp" "$PSTATE"
}

# The first call was started before and never counted (the harness was killed during it, or
# it died before reporting a session), so the real CLI would refuse its --session-id as
# already used. Mint a fresh id; the old one stays in orchestrator_sessions[] with the
# marker's instant as its start, so whatever it cost is priced (a missing transcript is 0).
orch_replace_killed_session() {
  local started old new now tmp
  started="$(harness_state_get "$PSTATE" orchestrator_first_call_started)"
  [[ -n "$started" ]] || return 0
  old="$(program_session_id)"
  new="$(harness_new_session_id)"
  now="$(harness_utc_now)"
  tmp="$PSTATE.tmp"
  jq --arg o "$old" --arg os "$started" --arg n "$new" --arg ns "$now" '
      .orchestrator_sessions = ((.orchestrator_sessions // []) | map(select(. != $o and . != $n)) + [$o, $n])
    | .orchestrator_session_starts = ((.orchestrator_session_starts // {}) | (if has($o) then . else .[$o] = $os end) | .[$n] = $ns)
    | .session_id = $n' "$PSTATE" > "$tmp" && mv "$tmp" "$PSTATE"
  harness_state_intervention "$PSTATE" "the first orchestrator call (session $old, started $started) never completed; minted session $new for the first call"
}

orch_invoke() {  # $1 result file, $2 prompt file
  local result="$1" prompt="$2" calls
  local flags=(--model "$HARNESS_MODEL")
  if [[ -n "${PROGRAM_BUDGET_USD:-}" ]]; then flags+=(--max-budget-usd "$PROGRAM_BUDGET_USD"); fi
  flags+=(--permission-mode acceptEdits --allowedTools Bash)
  calls="$(harness_state_get "$PSTATE" orchestrator_calls)"
  if (( ${calls:-0} == 0 )); then
    orch_replace_killed_session
    harness_state_set_str "$PSTATE" orchestrator_first_call_started "$(harness_utc_now)"
    harness_claude_new_session "$result" "$prompt" "$PTREE" "$(program_session_id)" "${flags[@]}"
  else
    harness_claude_resume "$result" "$prompt" "$PTREE" "$(orch_current_session)" "${flags[@]}"
  fi
}

# orchestrator_call <kind> <prompt-file> [tag] — the one seam every orchestrator turn goes
# through. Sets ORCH_RESULT (the result file) and ORCH_RC; a non-zero exit that is not a
# usage limit marks the program method_failed and is an intervention (ruling 5).
orchestrator_call() {
  local kind="$1" prompt="$2" tag="${3:-}" started rc retried=0 calls
  ORCH_RESULT="$LOG_DIR/$PBRANCH-$PROGRAM_ORCHESTRATOR_TAG-$kind${tag:+-$tag}-result.json"
  while :; do
    started="$(harness_utc_now)"
    orch_invoke "$ORCH_RESULT" "$prompt"; rc=$?
    # A call that failed before reporting a session leaves the next one a fresh --session-id.
    if orch_record_session "$ORCH_RESULT" "$started" || (( rc == 0 )); then
      calls="$(harness_state_get "$PSTATE" orchestrator_calls)"
      harness_state_set "$PSTATE" orchestrator_calls "$(( ${calls:-0} + 1 ))"
    fi
    if (( rc != 0 && ! retried )) && harness_stopped_on_usage_limit "$ORCH_RESULT"; then
      retried=1
      harness_state_intervention "$PSTATE" "orchestrator $kind call stopped on a usage limit; waited and resumed once"
      harness_wait_for_usage_reset "$ORCH_RESULT"
      continue
    fi
    break
  done
  ORCH_RC="$rc"
  if (( rc != 0 )); then
    harness_state_set "$PSTATE" method_failed true
    harness_state_intervention "$PSTATE" "orchestrator $kind call exited $rc"
    harness_warn "orchestrator $kind call exited $rc"
  fi
  return "$rc"
}

# ── Setup ────────────────────────────────────────────────────────────────────
do_program_setup() {
  pstage_begin "$PSTAGE_SETUP"
  local first_setup=0
  [[ -z "$(harness_state_get "$PSTATE" t_setup_start)" ]] && first_setup=1
  harness_state_set_str "$PSTATE" t_setup_start "$(harness_utc_now)"
  program_session_id >/dev/null

  git -C "$PREPO_PATH" fetch -q "$PREMOTE" || harness_warn "fetch of $PREMOTE failed — using what is on disk"

  if (( first_setup )) && [[ ! -d "$PTREE" && "${HARNESS_ALLOW_EXISTING_BRANCH:-0}" != 1 ]] \
     && ( git -C "$PREPO_PATH" show-ref --verify --quiet "refs/heads/$PBRANCH" \
          || git -C "$PREPO_PATH" show-ref --verify --quiet "refs/remotes/$PREMOTE/$PBRANCH" ); then
    pstage_end "$PSTAGE_SETUP" "branch-collision"
    harness_die "branch $PBRANCH already exists in $PREPO_PATH and this program cell has no state.
  Set \"branch_stem_override\": {\"$PROGRAM\": \"<newStem>\"} in $EXPERIMENT_JSON,
  or pass HARNESS_ALLOW_EXISTING_BRANCH=1 if reusing that branch is really what you want."
  fi

  if [[ -d "$PTREE" ]]; then
    harness_log "worktree already present: $PTREE"
  elif git -C "$PREPO_PATH" show-ref --verify --quiet "refs/heads/$PBRANCH"; then
    git -C "$PREPO_PATH" worktree add "$PTREE" "$PBRANCH" || harness_die "worktree add failed"
  else
    git -C "$PREPO_PATH" worktree add -b "$PBRANCH" "$PTREE" "$PBASE" || harness_die "worktree add failed"
  fi

  if [[ -n "$ARM_SHA" ]] && ! git -C "$PTREE" log --format=%s "$PBASE..HEAD" 2>/dev/null \
       | grep -qxF "$HARNESS_PIN_SUBJECT_PREFIX ${ARM_SHA:0:$PIN_SHORT_SHA_LEN}"; then
    AT_CHECKOUT="$(harness_resolve_repo "$HARNESS_AGENT_TOOLING_URL")" || exit 1
    harness_pin_agent_tooling "$PTREE" "$ARM_SHA" "$AT_CHECKOUT"
  fi
  harness_state_set_str "$PSTATE" agent_tooling "$ARM_SHA"

  # The orchestration record is written through this path; a symlink would carry it into the
  # source checkout (ruling 7).
  if [[ -L "$PTREE/$AGENT_TOOLING_RELPATH" ]]; then
    pstage_end "$PSTAGE_SETUP" "symlinked-agentTooling"
    harness_die "$PTREE/$AGENT_TOOLING_RELPATH is a symlink — the orchestration record would be written into the source checkout; pin an arm (agent_tooling in $EXPERIMENT_JSON)"
  fi
  if ! harness_check_program_floor "$PTREE/$AGENT_TOOLING_RELPATH" "$ARM"; then
    pstage_end "$PSTAGE_SETUP" "below-floor"
    harness_die "program $PROGRAM cannot run on this agentTooling version (above)"
  fi

  local cmd
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    harness_log "setup: $cmd"
    ( cd "$PTREE" && eval "$cmd" ) || harness_die "program setup command failed: $cmd"
  done < <(jq -r '.setup[]? // empty' "$PROGRAM_JSON")

  local log="$LOG_DIR/$PBRANCH-gate-setup.log"
  harness_run_gate "$PTREE" "$PGATE_COMMAND" "$log"
  if ! harness_gate_is_green "$log" "$PGATE_GREEN"; then
    pstage_end "$PSTAGE_SETUP" "gate-red"
    harness_die "gate is not green at $PBASE in $PTREE (see $log) — the program's base is broken, not the method"
  fi

  if [[ -f "$(program_record_path)" ]]; then
    harness_log "orchestration record already present — not started again"
  else
    ( cd "$PTREE/$AGENT_TOOLING_RELPATH" && "./$PROGRAM_START_SCRIPT" "$PSLUG" --session "$(program_session_id)" ) \
      || { pstage_end "$PSTAGE_SETUP" "orchestration-start-failed"; harness_die "$PROGRAM_START_SCRIPT failed in $PTREE"; }
  fi
  # shellcheck disable=SC2059
  harness_commit_all "$PTREE" "$(printf "$PROGRAM_START_SUBJECT_FORMAT" "$PSLUG")" \
    || harness_log "nothing to commit after the orchestration start"
  pstage_end "$PSTAGE_SETUP" ok
}

# ── Brief ────────────────────────────────────────────────────────────────────
# The ordered feature block the program prompt carries: one entry per feature, the fixture's
# facts included (filled for that feature while it is loaded).
program_features_block() {
  local i block="" pin facts choice depends
  for (( i = 0; i < NFEAT; i++ )); do
    load_program_feature "$i"
    pin="${PF_PIN[$i]}"
    if [[ -n "$pin" ]]; then choice="pinned to \`$pin\` by the program"; else choice="your choice (direct, plans or hand)"; fi
    if [[ "${PF_DEPENDS[$i]}" == true ]]; then
      depends="yes — cut at the tip of feature $i's branch \`${PF_BRANCH[$(( i - 1 ))]}\`"
    else
      depends="no"
    fi
    facts="$(harness_fill_template "$FIXTURE_DIR/facts.md")"
    block+="### Feature $(( i + 1 )) of $NFEAT — $FIXTURE

- Depends on the previous feature: $depends
- Method: $choice
- Branch: \`$BRANCH\`
- Worktree: \`$TREE\`
- PR base: \`$(program_pr_base "$i" 0)\`
- Brief file: \`$(program_brief_path "$i")\`
- Spec: \`$SPEC_TREE/$SPEC_PATH\`, sections: $SPEC_SECTIONS
- Gate: \`$GATE_COMMAND\` (green when it prints \`$GATE_GREEN\`; about $GATE_MINUTES minutes)

Facts:

$facts

"
  done
  printf '%s' "$block"
}

do_program_brief() {
  pstage_begin "$PSTAGE_BRIEF"
  program_session_id >/dev/null
  local features prompt="$LOG_DIR/$PBRANCH-$PROGRAM_ORCHESTRATOR_TAG-brief-prompt.md"
  features="$(program_features_block)" || return 1
  set_program_scope_vars
  HARNESS_FEATURES="$features"
  mkdir -p "$(program_brief_dir)"
  harness_fill_template "$HARNESS_TEMPLATES_DIR/$PROGRAM_PROMPT_TEMPLATE_BRIEF" > "$prompt"
  # Before the first orchestrator call, so the window the overhead is priced in contains it.
  [[ -n "$(harness_state_get "$PSTATE" t_method_start)" ]] \
    || harness_state_set_str "$PSTATE" t_method_start "$(harness_utc_now)"
  if ! orchestrator_call "$PROGRAM_ORCH_CALL_BRIEF" "$prompt"; then
    pstage_end "$PSTAGE_BRIEF" "failed($ORCH_RC)"
    return 1
  fi
  pstage_end "$PSTAGE_BRIEF" ok
}

# ── Loop ─────────────────────────────────────────────────────────────────────
program_feature_state_init() {  # $1 index
  harness_state_init "$STATE"
  harness_state_set_str "$STATE" experiment "$EXPERIMENT_NAME"
  harness_state_set_str "$STATE" program "$PROGRAM"
  harness_state_set_str "$STATE" fixture "$FIXTURE"
  harness_state_set "$STATE" repeat "$REPEAT"
  harness_state_set_str "$STATE" arm "$ARM"
  harness_state_set_str "$STATE" branch "$BRANCH"
  harness_state_set_str "$STATE" slug "$SLUG"
  harness_state_set "$STATE" position "$(( $1 + 1 ))"
  harness_state_set "$STATE" depends_on_previous "${PF_DEPENDS[$1]}"
}

program_prev_outcome() {  # $1 index of the feature being briefed
  local i="$1" ps text url
  if (( i == 0 )); then printf '%s' "$PROGRAM_NO_PREVIOUS_TEXT"; return 0; fi
  ps="$(program_fstate $(( i - 1 )))"
  url="$(harness_state_get "$ps" pr_url)"
  if [[ -n "$url" ]]; then
    printf 'Feature %d (%s) opened a PR: %s (branch %s).' "$i" "${PF_FIXTURE[$(( i - 1 ))]}" "$url" "${PF_BRANCH[$(( i - 1 ))]}"
  else
    printf 'Feature %d (%s) FAILED: no PR was opened (%s).' "$i" "${PF_FIXTURE[$(( i - 1 ))]}" \
      "$(harness_state_get "$ps" failure_reason)"
  fi
  text="$(harness_claude_text "$LOG_DIR/${PF_BRANCH[$(( i - 1 ))]}-method-result.json" | head -c "$PROGRAM_OUTCOME_MAX_CHARS")"
  if [[ -n "$text" ]]; then printf '\n\nIts implementer reported:\n\n%s' "$text"; fi
}

program_feature_fail() {  # $1 reason, $2 stage outcome
  METHOD_FAILED=true
  harness_state_set "$STATE" method_failed true
  harness_state_set_str "$STATE" failure_reason "$1"
}

# The last bookkeeping of a feature, whatever happened: its tip, its dependency check, done.
program_finish_feature() {  # $1 index, $2 previous tip ("" when none)
  local i="$1" prev_tip="$2" tip ok
  if [[ -d "$TREE" ]]; then
    tip="$(git -C "$TREE" rev-parse HEAD 2>/dev/null)"
    [[ -z "$tip" ]] || harness_state_set_str "$STATE" tip "$tip"
  fi
  if [[ "${PF_DEPENDS[$i]}" == true ]]; then
    if [[ -n "$prev_tip" ]] && git -C "$PREPO_PATH" merge-base --is-ancestor "$prev_tip" "$BRANCH" 2>/dev/null; then
      ok=true
    else
      ok=false
    fi
    harness_state_set "$STATE" dependency_ok "$ok"
  fi
  harness_state_set "$STATE" feature_done true
}

# The orchestrator writes feature i's brief; true when a non-empty brief file exists after.
program_feature_brief() {  # $1 index
  local i="$1" nn brief prompt chosen text
  brief="$(program_brief_path "$i")"
  if [[ "$(harness_state_get "$STATE" brief_written)" == true && -s "$brief" ]]; then
    harness_log "$BRANCH: brief already written — reusing it"
    METHOD="$(harness_state_get "$STATE" method)"; [[ -n "$METHOD" ]] || METHOD="$PROGRAM_DEFAULT_METHOD"
    return 0
  fi
  stage_begin "$PSTAGE_BRIEF"
  nn="$(printf '%02d' "$(( i + 1 ))")"
  mkdir -p "$(dirname "$brief")"
  rm -f "$brief"
  set_program_common_vars
  HARNESS_POSITION="$(( i + 1 ))"
  HARNESS_PR_BASE="$(harness_state_get "$STATE" pr_base)"
  if [[ "${PF_DEPENDS[$i]}" == true ]]; then
    HARNESS_DEPENDS="yes — the branch was cut at the tip of feature $i's branch \`${PF_BRANCH[$(( i - 1 ))]}\`"
  else
    HARNESS_DEPENDS="no"
  fi
  if [[ -n "${PF_PIN[$i]}" ]]; then
    HARNESS_METHOD_CHOICE="pinned to \`${PF_PIN[$i]}\` by the program — write the brief for that method"
  else
    HARNESS_METHOD_CHOICE="your choice (direct, plans or hand)"
  fi
  HARNESS_BRIEF_PATH="$brief"
  # Not exported: the fill runs in this shell, and the next implementer's environment
  # should not carry the previous implementer's report.
  HARNESS_PREV_OUTCOME="$(program_prev_outcome "$i")"
  prompt="$LOG_DIR/$BRANCH-$PROGRAM_ORCHESTRATOR_TAG-prompt.md"
  harness_fill_template "$HARNESS_TEMPLATES_DIR/$PROGRAM_PROMPT_TEMPLATE_FEATURE" > "$prompt"
  orchestrator_call "$PROGRAM_ORCH_CALL_FEATURE" "$prompt" "$nn"

  chosen="${PF_PIN[$i]}"
  if [[ -z "$chosen" ]]; then
    text="$(harness_claude_text "$ORCH_RESULT")"
    chosen="$(printf '%s\n' "$text" | sed -n -E "$PROGRAM_METHOD_LINE_SED" | tail -1)"
    if ! program_method_valid "$chosen"; then
      if (( ORCH_RC == 0 )); then
        harness_state_intervention "$STATE" "the orchestrator named no valid METHOD line (got '${chosen}'); ran $PROGRAM_DEFAULT_METHOD"
      fi
      chosen="$PROGRAM_DEFAULT_METHOD"
    fi
  fi
  METHOD="$chosen"
  harness_state_set_str "$STATE" method "$METHOD"

  if [[ -s "$brief" ]]; then
    harness_state_set "$STATE" brief_written true
    # shellcheck disable=SC2059
    harness_commit_all "$PTREE" "$(printf "$PROGRAM_BRIEF_SUBJECT_FORMAT" "$PSLUG" "$FIXTURE")" \
      || harness_log "nothing to commit for the brief"
    stage_end "$PSTAGE_BRIEF" ok
    return 0
  fi
  harness_state_set "$STATE" brief_written false
  program_feature_fail "brief-unwritten"
  harness_state_set "$PSTATE" method_failed true
  harness_state_intervention "$PSTATE" "$FIXTURE: the orchestrator wrote no brief at $brief; no implementer ran"
  stage_end "$PSTAGE_BRIEF" "unwritten"
  return 1
}

program_run_implementer() {
  harness_claude "$HARNESS_METHOD_RESULT" "$BRIEF_FILE" "$TREE" \
    --model "$HARNESS_MODEL" --permission-mode acceptEdits --allowedTools $PROGRAM_IMPLEMENTER_TOOLS
}

program_feature_implement() {  # $1 index
  local i="$1" rc pr_base
  write_stage_manifest "$SLUG" \
    "$(printf "$PROGRAM_MANIFEST_TITLE_FORMAT" "$SLUG" "$FIXTURE" "$METHOD" "$PROGRAM")"
  mkdir -p "$(dirname "$BRIEF_FILE")"
  cp "$(program_brief_path "$i")" "$BRIEF_FILE"

  stage_begin "$FSTAGE_METHOD"
  harness_state_set_str "$STATE" t_implementer_start "$(harness_utc_now)"
  program_run_implementer; rc=$?
  if (( rc != 0 )) && harness_stopped_on_usage_limit "$HARNESS_METHOD_RESULT"; then
    harness_state_intervention "$STATE" "implementer stopped on a usage limit; waited and ran again once"
    harness_wait_for_usage_reset "$HARNESS_METHOD_RESULT"
    program_run_implementer; rc=$?
  fi
  harness_state_set_str "$STATE" t_implementer_end "$(harness_utc_now)"
  harness_state_set_str "$STATE" session "$(harness_claude_session "$HARNESS_METHOD_RESULT")"
  if (( rc != 0 )); then
    program_feature_fail "implementer-exit-$rc"
    stage_end "$FSTAGE_METHOD" "failed($rc)"
    return 1
  fi
  PR_URL="$(harness_pr_url "$TREE" "$BRANCH")"
  if [[ -z "$PR_URL" ]]; then
    program_feature_fail "no-pr"
    stage_end "$FSTAGE_METHOD" "no-pr"
    harness_warn "the implementer exited 0 but no PR is open for $BRANCH"
    return 1
  fi
  pr_base="$(harness_state_get "$STATE" pr_base)"
  harness_state_set_str "$STATE" pr_url "$PR_URL"
  harness_state_set_str "$STATE" t_pr_open "$(harness_utc_now)"
  harness_state_set_str "$STATE" pr_base "${pr_base:-$PROGRAM_DEFAULT_PR_BASE}"

  harness_close_manifest_window "$TREE" "$SLUG" "$(harness_utc_now)"
  harness_commit_all "$TREE" "$SLUG: close the manifest session window at PR-open" \
    || harness_warn "nothing to commit for the manifest window"
  harness_push "$TREE" "$BRANCH"
  GATE_COUNTS_PR_OPEN="$(harness_gate_counts "$TREE")"
  harness_state_set_str "$STATE" gate_counts_pr_open "$GATE_COUNTS_PR_OPEN"
  stage_end "$FSTAGE_METHOD" ok
}

program_run_feature() {  # $1 index
  local i="$1" prev_tip="" pr_base="$PROGRAM_DEFAULT_PR_BASE"
  load_program_feature "$i"
  program_feature_state_init "$i"
  if [[ "$(harness_state_get "$STATE" feature_done)" == true ]]; then
    harness_log "$BRANCH: already built — skipping (delete $STATE to redo it)"
    return 0
  fi
  START_POINT=""
  if [[ "${PF_DEPENDS[$i]}" == true ]] && (( i > 0 )); then
    prev_tip="$(harness_state_get "$(program_fstate $(( i - 1 )))" tip)"
    if [[ -n "$prev_tip" ]]; then
      START_POINT="$prev_tip"
      pr_base="${PF_BRANCH[$(( i - 1 ))]}"
    else
      harness_state_intervention "$STATE" "the previous feature left no branch tip; cut at $PBASE and targeting $PROGRAM_DEFAULT_PR_BASE instead"
    fi
  fi
  harness_state_set_str "$STATE" pr_base "$pr_base"
  harness_state_set_str "$STATE" start_point "${START_POINT:-$PBASE}"

  stage_begin "$PSTAGE_SETUP"
  # A dependent feature cut at the previous tip runs even if that branch is red.
  [[ -z "$START_POINT" ]] || GATE_RED_FATAL=0
  setup_tree
  GATE_RED_FATAL=1
  if (( GATE_RED_RAN_ANYWAY )); then
    stage_end "$PSTAGE_SETUP" "$PROGRAM_GATE_RED_RAN_OUTCOME"
  else
    stage_end "$PSTAGE_SETUP" ok
  fi
  START_POINT=""

  if program_feature_brief "$i"; then
    program_feature_implement "$i" || true
  fi
  program_finish_feature "$i" "$prev_tip"
}

do_program_loop() {
  pstage_begin "$PSTAGE_LOOP"
  local i
  for (( i = 0; i < NFEAT; i++ )); do
    program_run_feature "$i"
  done
  pstage_end "$PSTAGE_LOOP" ok
}

# ── Collect ──────────────────────────────────────────────────────────────────
program_record_args() {  # $1 index — the add-feature words for a feature that has a branch
  local fs session url out
  fs="$(program_fstate "$1")"
  out="repo=$PREPO_NAME slug=${PF_SLUG[$1]}"
  session="$(harness_state_get "$fs" session)"
  url="$(harness_state_get "$fs" pr_url)"
  [[ -z "$session" ]] || out+=" session=$session"
  out+=" branch=${PF_BRANCH[$1]}"
  [[ -z "$url" ]] || out+=" pr=$url"
  printf '%s' "$out"
}

program_has_branch() { git -C "$PREPO_PATH" show-ref --verify --quiet "refs/heads/${PF_BRANCH[$1]}"; }

program_manifest() {  # args after --orchestration <slug>, run in the program tree
  ( cd "$PTREE" && python3 "$PROGRAM_MANIFEST_PY" --orchestration "$PSLUG" "$@" )
}

do_program_collect() {
  pstage_begin "$PSTAGE_COLLECT"
  local i cmds="" prompt="$LOG_DIR/$PBRANCH-$PROGRAM_ORCHESTRATOR_TAG-collect-prompt.md" rc
  for (( i = 0; i < NFEAT; i++ )); do
    program_has_branch "$i" || continue
    cmds+="python3 $PROGRAM_MANIFEST_PY --orchestration $PSLUG add-feature $(program_record_args "$i")
"
  done
  cmds+="python3 $PROGRAM_MANIFEST_PY --orchestration $PSLUG set-window-to now"
  set_program_scope_vars
  HARNESS_RECORD_COMMANDS="$cmds"
  harness_fill_template "$HARNESS_TEMPLATES_DIR/$PROGRAM_PROMPT_TEMPLATE_COLLECT" > "$prompt"
  orchestrator_call "$PROGRAM_ORCH_CALL_COLLECT" "$prompt"; rc=$?
  harness_state_set_str "$PSTATE" t_method_end "$(harness_utc_now)"

  # The record must name every feature that has a branch and have its window closed; the
  # harness does whatever the orchestrator left undone, and says so.
  local names
  names="$(program_manifest get features 2>/dev/null)"; [[ -n "$names" ]] || names="[]"
  for (( i = 0; i < NFEAT; i++ )); do
    program_has_branch "$i" || continue
    if ! printf '%s' "$names" | jq -e --arg s "${PF_SLUG[$i]}" 'any(.[]; .slug == $s)' >/dev/null 2>&1; then
      # shellcheck disable=SC2046
      program_manifest add-feature $(program_record_args "$i") >/dev/null \
        || harness_warn "could not add ${PF_SLUG[$i]} to the orchestration record"
      harness_state_intervention "$PSTATE" "the record did not name ${PF_SLUG[$i]}; the harness added it"
    fi
  done
  if [[ -z "$(program_manifest get session_window.to 2>/dev/null)" ]]; then
    program_manifest set-window-to now >/dev/null \
      || harness_warn "could not close the orchestration record's window"
    harness_state_intervention "$PSTATE" "the record's session window was still open; the harness closed it"
  fi
  # shellcheck disable=SC2059
  harness_commit_all "$PTREE" "$(printf "$PROGRAM_COLLECT_SUBJECT_FORMAT" "$PSLUG")" \
    || harness_log "nothing left to commit after the collect turn"
  harness_push "$PTREE" "$PBRANCH"

  local sessions reported
  sessions="$(jq -r '(.orchestrator_sessions // []) | join(", ")' "$PSTATE")"
  reported="$(jq -s '[.[].total_cost_usd // 0] | add // 0' "$LOG_DIR/$PBRANCH-$PROGRAM_ORCHESTRATOR_TAG"-*-result.json 2>/dev/null)"
  # shellcheck disable=SC2059
  harness_log "orchestrator: sessions [$sessions], window $(harness_state_get "$PSTATE" t_method_start) .. $(harness_state_get "$PSTATE" t_method_end), reported spend \$$(printf "$PROGRAM_FIGURE_FORMAT" "$(num "$reported")")"
  if (( rc != 0 )); then
    pstage_end "$PSTAGE_COLLECT" "failed($rc)"
    return 1
  fi
  pstage_end "$PSTAGE_COLLECT" ok
}

# ── Review, rework, accept, capture ──────────────────────────────────────────
# A feature runs these when it built something: not method_failed, and a tree to work in.
program_over_features() {  # $1 stage name, $2 function to call per feature
  local stage="$1" fn="$2" i
  pstage_begin "$stage"
  for (( i = 0; i < NFEAT; i++ )); do
    load_program_feature "$i"
    if [[ "$METHOD_FAILED" == true || ! -d "$TREE" ]]; then
      harness_log "$BRANCH: failed or never built — skipping $stage"
      continue
    fi
    "$fn"
  done
  pstage_end "$stage" ok
}
do_program_review() { program_over_features "$PSTAGE_REVIEW" do_review; }
do_program_rework() { program_over_features "$PSTAGE_REWORK" do_rework; }
do_program_accept() { program_over_features "$PSTAGE_ACCEPT" do_accept; }

program_overhead() {  # prints the orchestrator's cost, priced with the driver's own analysis copy
  local id from args=() start end
  start="$(harness_state_get "$PSTATE" t_method_start)"
  end="$(harness_state_get "$PSTATE" t_method_end)"
  if [[ -z "$end" ]]; then
    end="$(harness_utc_now)"
    harness_state_intervention "$PSTATE" "the collect turn never ended; the overhead is priced to now"
  fi
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    from="$(jq -r --arg i "$id" '.orchestrator_session_starts[$i] // empty' "$PSTATE")"
    args+=(--session "${id}${from:+@$from}")
  done < <(jq -r '.orchestrator_sessions[]?' "$PSTATE")
  if [[ -z "$start" ]] || (( ${#args[@]} == 0 )); then
    harness_warn "no orchestrator session or window recorded — overhead is 0"
    printf '0'; return 0
  fi
  python3 "$SCRIPT_DIR/$PROGRAM_COST_SCRIPT" "$AGENT_TOOLING_DIR/analysis" "${args[@]}" --from "$start" --to "$end"
}

# The arm's own cross-check of the group cost (ruling 10): best effort, never fatal.
program_record_report() {
  local dir="$PTREE/$PROGRAM_RECORD_ROOT/$PSLUG" at="$PTREE/$AGENT_TOOLING_RELPATH" log="$LOG_DIR/$PBRANCH-record-report.log" report
  if [[ -x "$at/$PROGRAM_CAPTURE_SCRIPT" ]]; then
    ( cd "$at" && "./$PROGRAM_CAPTURE_SCRIPT" "$PSLUG" ) >> "$log" 2>&1 \
      || harness_warn "$PROGRAM_CAPTURE_SCRIPT failed in the program tree (see $log)"
  fi
  if [[ -f "$at/$PROGRAM_REPORT_PY" ]]; then
    ( cd "$at" && python3 "$PROGRAM_REPORT_PY" --orchestration "$PSLUG" ) >> "$log" 2>&1 \
      || harness_warn "report.py --orchestration failed in the program tree (see $log)"
  fi
  report="$dir/$PROGRAM_REPORT_NAME"
  if [[ -f "$report" ]] && jq -e . "$report" >/dev/null 2>&1; then
    harness_state_set "$PSTATE" record_report \
      "$(jq -c '{group_total_usd: (.group_total_usd // null), overhead_pct: (.overhead_pct // null), unpriced_count: (.unpriced_count // null)}' "$report")"
  else
    harness_state_set "$PSTATE" record_report null
  fi
}

# After do_capture (which leaves COST_METHOD and COST_METHOD_REPORTED set): write the
# feature's unpriced_reason when its cost_method_usd is not a measurement, else clear it.
program_note_unpriced() {
  local reason=""
  if [[ ! -d "$TREE/plans/features/$SLUG" ]]; then
    reason="$PROGRAM_UNPRICED_NO_MANIFEST"
  elif awk -v c="$(num "$COST_METHOD")" -v r="$COST_METHOD_REPORTED" -v f="$PROGRAM_UNPRICED_FLOOR_PCT" \
         'BEGIN { exit (r > 0 && c < f * r) ? 0 : 1 }'; then
    # shellcheck disable=SC2059
    reason="$(printf "$PROGRAM_UNPRICED_MISSED_FORMAT" "$(num "$COST_METHOD")" "$COST_METHOD_REPORTED")"
  fi
  if [[ -n "$reason" ]]; then
    harness_state_set_str "$STATE" unpriced_reason "$reason"
  else
    harness_state_set "$STATE" unpriced_reason null
  fi
}

do_program_capture() {
  pstage_begin "$PSTAGE_CAPTURE"
  local i overhead
  for (( i = 0; i < NFEAT; i++ )); do
    load_program_feature "$i"
    if [[ ! -d "$TREE" ]]; then
      harness_log "$BRANCH: no worktree — nothing to capture"
      continue
    fi
    do_capture
    program_note_unpriced
  done
  if overhead="$(program_overhead)"; then
    harness_state_set_str "$PSTATE" cost_overhead_usd "$(num "$overhead")"
  else
    harness_warn "pricing the orchestrator failed — cost_overhead_usd left at 0"
    harness_state_set_str "$PSTATE" cost_overhead_usd 0
    harness_state_intervention "$PSTATE" "program_cost.py failed; the overhead is recorded as 0"
  fi
  if [[ -d "$PTREE" ]]; then
    program_record_report
    # shellcheck disable=SC2059
    harness_commit_all "$PTREE" "$(printf "$PROGRAM_RECORD_FREEZE_SUBJECT_FORMAT" "$PSLUG")" \
      || harness_log "nothing to commit after the record report"
    harness_push "$PTREE" "$PBRANCH"
  fi
  pstage_end "$PSTAGE_CAPTURE" ok
}

# ── Record ───────────────────────────────────────────────────────────────────
program_feature_row() {  # $1 index — one features[] object, compact, from the state file
  local i="$1" fs s
  fs="$(program_fstate "$i")"
  s="$(jq -c . "$fs" 2>/dev/null)"; [[ -n "$s" ]] || s='{}'
  load_program_feature "$i"
  jq -c -n --argjson s "$s" --argjson position "$(( i + 1 ))" --arg fixture "$FIXTURE" \
    --argjson depends "${PF_DEPENDS[$i]}" --arg method "$METHOD" --arg branch "$BRANCH" --arg slug "$SLUG" \
    --argjson accept_on "$DO_ACCEPT" '
    def num(x): (x // 0) | (if type == "string" then (tonumber? // 0) else . end);
    def r4: (. * 10000 | round) / 10000;
    { position: $position, fixture: $fixture, depends_on_previous: $depends,
      method: ($s.method // $method), branch: $branch, slug: $slug,
      session: ($s.session // ""), pr_url: ($s.pr_url // ""), pr_base: ($s.pr_base // ""),
      t_implementer_start: ($s.t_implementer_start // ""), t_implementer_end: ($s.t_implementer_end // ""),
      brief_written: ($s.brief_written // false),
      dependency_ok: (if $depends then ($s.dependency_ok // false) else null end),
      cost_method_usd: (num($s.cost_method_usd) | r4),
      cost_review_usd: (num($s.cost_review_usd) | r4),
      cost_rework_usd: (num($s.cost_rework_usd) | r4),
      unpriced_reason: ($s.unpriced_reason // null),
      review_fixed: num($s.review_fixed), review_escalated: num($s.review_escalated),
      rework_ran: ($s.rework_ran // false),
      accept_pass: ($s.accept_pass // false), accept_lines: ($s.accept_lines // []),
      gate_counts_green: ($s.gate_counts_green // ""),
      method_failed: (if ($s | length) == 0 then true else ($s.method_failed // false) end) }
    | .cost_green_usd = ((.cost_method_usd + .cost_review_usd + .cost_rework_usd) | r4)
    | .green = ((.method_failed | not) and (($accept_on | not) or .accept_pass))'
}

build_program_row() {  # the `record` stage
  pstage_begin "$PSTAGE_RECORD"
  local i rows="" fints="" fs features row
  for (( i = 0; i < NFEAT; i++ )); do
    rows+="$(program_feature_row "$i")
"
    fs="$(program_fstate "$i")"
    fints+="$(jq -c --arg p "${PF_SLUG[$i]}" '(.interventions // []) | map(.what = ($p + ": " + .what))' "$fs" 2>/dev/null)
"
  done
  features="$(printf '%s' "$rows" | jq -s '.')"

  local method_failed
  method_failed="$(harness_state_get "$PSTATE" method_failed)"; [[ "$method_failed" == true ]] || method_failed=false
  row="$(jq -c -n \
    --arg experiment "$EXPERIMENT_NAME" --arg program "$PROGRAM" --argjson repeat "$REPEAT" \
    --arg arm "$ARM" --arg agent_tooling "$(pstate_or agent_tooling "$ARM_SHA")" \
    --arg branch "$PBRANCH" --arg slug "$PSLUG" --arg base "$PBASE" --arg model "$HARNESS_MODEL" \
    --arg effort "$HARNESS_EFFORT" \
    --argjson sessions "$(jq -c '.orchestrator_sessions // []' "$PSTATE")" \
    --arg record "$(program_record_relpath)" \
    --arg t_setup_start "$(harness_state_get "$PSTATE" t_setup_start)" \
    --arg t_method_start "$(harness_state_get "$PSTATE" t_method_start)" \
    --arg t_method_end "$(harness_state_get "$PSTATE" t_method_end)" \
    --argjson overhead "$(num "$(harness_state_get "$PSTATE" cost_overhead_usd)")" \
    --argjson method_failed "$method_failed" \
    --argjson record_report "$(jq -c '.record_report // null' "$PSTATE")" \
    --argjson features "$features" \
    --argjson fints "$(printf '%s' "$fints" | jq -s 'add // []')" \
    --argjson pints "$(jq -c '.interventions // []' "$PSTATE")" \
    --arg harness_version "$(harness_version)" \
    --arg kind program --arg orchestrator "$HARNESS_PROGRAM_METHOD" '
    def r4: (. * 10000 | round) / 10000;
    ($features | map(.cost_method_usd) | add // 0) as $msum
    | ($features | map(.cost_review_usd + .cost_rework_usd) | add // 0) as $rsum
    | ($overhead + $msum | r4) as $group
    | { kind: $kind, experiment: $experiment, program: $program, method: $orchestrator,
        repeat: $repeat, arm: $arm, agent_tooling: $agent_tooling,
        branch: $branch, slug: $slug, base: $base, model: $model,
        effort: (if $effort == "" then null else $effort end),
        orchestrator_sessions: $sessions, orchestration_record: $record,
        t_setup_start: $t_setup_start, t_method_start: $t_method_start, t_method_end: $t_method_end,
        cost_overhead_usd: $overhead,
        cost_group_usd: $group,
        cost_group_green_usd: ($group + $rsum | r4),
        overhead_pct: (if $group > 0 then ($overhead / $group * 100 | r4) else 0 end),
        features_count: ($features | length),
        features_pr_open: ($features | map(select(.pr_url != "")) | length),
        features_green: ($features | map(select(.green)) | length),
        method_failed: $method_failed, record_report: $record_report,
        features: $features,
        interventions: ($pints + $fints | sort_by(.t)),
        harness_version: $harness_version }')" \
    || { pstage_end "$PSTAGE_RECORD" "row-failed"; harness_die "could not build the program row"; }
  printf '%s\n' "$row" >> "$RESULTS_FILE"

  python3 "$SCRIPT_DIR/scorecard.py" "$EXPERIMENT_DIR" || harness_warn "scorecard render failed"

  if (( NO_CLEANUP )); then
    harness_log "--no-cleanup: leaving the program and feature worktrees in place"
  else
    for (( i = 0; i < NFEAT; i++ )); do
      if [[ -d "${PF_TREE[$i]}" ]]; then
        git -C "$PREPO_PATH" worktree remove "${PF_TREE[$i]}" \
          || harness_warn "could not remove ${PF_TREE[$i]} — remove it by hand (the branch and PR stay)"
      fi
    done
    if [[ -d "$PTREE" ]]; then
      git -C "$PREPO_PATH" worktree remove "$PTREE" \
        || harness_warn "could not remove $PTREE — remove it by hand (the branch stays)"
    fi
  fi
  pstage_end "$PSTAGE_RECORD" ok
}

# ── Dry run ──────────────────────────────────────────────────────────────────
dry_run_program_cell() {
  local i s start
  say ""
  say "── $PROGRAM × $HARNESS_PROGRAM_METHOD × ${ARM:-(no pin)} × $REPEAT ─────────────────────────────"
  say "  program branch: $PBRANCH"
  say "  program slug:   $PSLUG"
  say "  repo:           $PREPO_PATH"
  say "  worktree:       $PTREE"
  [[ -z "$ARM" ]] || say "  agentTooling:   pinned to upstream $ARM_SHA (arm $ARM)"
  say "  state file:     $PSTATE"
  say "  stages:         $(for s in $HARNESS_PROGRAM_STAGES; do program_stage_wanted "$s" && printf '%s ' "$s"; done)"
  say "  review: $DO_REVIEW   rework: $DO_REWORK   accept: $DO_ACCEPT"
  say "  features:"
  for (( i = 0; i < NFEAT; i++ )); do
    if [[ "${PF_DEPENDS[$i]}" == true ]]; then start="the tip of ${PF_BRANCH[$(( i - 1 ))]} when it finishes"; else start="$PBASE"; fi
    say "    $(( i + 1 )). ${PF_FIXTURE[$i]}   branch ${PF_BRANCH[$i]}"
    say "       worktree:   ${PF_TREE[$i]}"
    say "       start:      $start"
    say "       pr base:    $(program_pr_base "$i" 0)"
    say "       depends:    ${PF_DEPENDS[$i]}   method: ${PF_PIN[$i]:-chosen by the orchestrator}"
  done
  say "  commands:"
  dry "git -C $PREPO_PATH fetch -q $PREMOTE"
  dry "git -C $PREPO_PATH worktree add -b $PBRANCH $PTREE $PBASE"
  if [[ -n "$ARM" ]]; then
    dry "git -C <checkout of $HARNESS_AGENT_TOOLING_URL> archive $ARM_SHA | tar -x -C $PTREE/$AGENT_TOOLING_RELPATH   (after rm -rf of it)"
    dry "cd $PTREE && ./$SYNC_PLANS_RELPATH"
    dry "git -C $PTREE commit -m '$HARNESS_PIN_SUBJECT_PREFIX ${ARM_SHA:0:$PIN_SHORT_SHA_LEN}'"
  fi
  dry "check $PTREE/$AGENT_TOOLING_RELPATH is not a symlink and carries: $HARNESS_PROGRAM_FLOOR_FILES"
  local cmd
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    dry "cd $PTREE && $cmd"
  done < <(jq -r '.setup[]? // empty' "$PROGRAM_JSON")
  dry "cd $PTREE && $PGATE_COMMAND      # require: $PGATE_GREEN"
  dry "cd $PTREE/$AGENT_TOOLING_RELPATH && ./$PROGRAM_START_SCRIPT $PSLUG --session <orchestrator session id>"
  dry "git -C $PTREE commit -m '$PSLUG: start the orchestration record'"
  dry "$HARNESS_CLAUDE_BIN -p --output-format json$(harness_effort_dry) --session-id <id> --model $HARNESS_MODEL --permission-mode acceptEdits --allowedTools Bash <program brief>   (cwd $PTREE)"
  for (( i = 0; i < NFEAT; i++ )); do
    if [[ "${PF_DEPENDS[$i]}" == true ]]; then start="<tip of ${PF_BRANCH[$(( i - 1 ))]}>"; else start="$PBASE"; fi
    dry "git -C $PREPO_PATH worktree add -b ${PF_BRANCH[$i]} ${PF_TREE[$i]} $start   (then pin, fixture setup, gate, spec worktree)"
    dry "$HARNESS_CLAUDE_BIN -p --output-format json$(harness_effort_dry) --resume <latest orchestrator session> ... <feature $(( i + 1 )) request>   -> $(program_brief_path "$i")   (cwd $PTREE)"
    dry "$HARNESS_CLAUDE_BIN -p --output-format json$(harness_effort_dry) --model $HARNESS_MODEL --permission-mode acceptEdits --allowedTools $PROGRAM_IMPLEMENTER_TOOLS <the brief>   (cwd ${PF_TREE[$i]})"
    dry "${HARNESS_FORGE_BIN:-${PF_TREE[$i]}/$FORGE_RELPATH} pr-find ${PF_BRANCH[$i]}; push; record tip"
  done
  dry "$HARNESS_CLAUDE_BIN -p --output-format json$(harness_effort_dry) --resume <latest orchestrator session> ... <collect request>   (cwd $PTREE)"
  dry "push $PBRANCH (no PR)"
  if [[ "$DO_REVIEW" == true ]]; then
    dry "per feature: $HARNESS_CLAUDE_BIN -p$(harness_effort_dry) ... --max-budget-usd $REVIEW_BUDGET_USD <review preamble + the fixture's review-brief.md>"
  fi
  if [[ "$DO_REWORK" == true ]]; then
    dry "per feature, only if escalated >= 1: $HARNESS_CLAUDE_BIN -p$(harness_effort_dry) ... --max-budget-usd $REWORK_BUDGET_USD <rework preamble + findings>"
  fi
  if [[ "$DO_ACCEPT" == true ]]; then
    dry "per feature: python3 <fixture>/accept/accept.py <tree>; then its gate once more"
  fi
  dry "per feature: python3 <tree>/agentTooling/analysis/capture_planning.py <slug> (also -review, -rework); report.py <slug>"
  dry "python3 $SCRIPT_DIR/$PROGRAM_COST_SCRIPT $AGENT_TOOLING_DIR/analysis --session <id>@<first call start> ... --from <t_method_start> --to <t_method_end>"
  dry "cd $PTREE/$AGENT_TOOLING_RELPATH && ./$PROGRAM_CAPTURE_SCRIPT $PSLUG; python3 $PROGRAM_REPORT_PY --orchestration $PSLUG   (best effort)"
  dry "append one kind=program row to $RESULTS_FILE"
  dry "python3 $SCRIPT_DIR/scorecard.py $EXPERIMENT_DIR"
  (( NO_CLEANUP )) || dry "git -C $PREPO_PATH worktree remove each feature worktree and $PTREE   (branches and PRs kept)"
}

# ── Drive ────────────────────────────────────────────────────────────────────
run_program_cell() {
  mkdir -p "$STATE_DIR" "$LOG_DIR"
  harness_state_init "$PSTATE"
  harness_state_set_str "$PSTATE" experiment "$EXPERIMENT_NAME"
  harness_state_set_str "$PSTATE" program "$PROGRAM"
  harness_state_set_str "$PSTATE" method "$HARNESS_PROGRAM_METHOD"
  harness_state_set "$PSTATE" repeat "$REPEAT"
  harness_state_set_str "$PSTATE" arm "$ARM"
  harness_state_set_str "$PSTATE" branch "$PBRANCH"
  harness_state_set_str "$PSTATE" slug "$PSLUG"

  program_stage_wanted "$PSTAGE_SETUP" && { do_program_setup || return 1; }
  if program_stage_wanted "$PSTAGE_BRIEF"; then
    if ! do_program_brief; then
      harness_warn "the orchestrator's first call failed — recording the row and skipping the loop"
      harness_state_set_str "$PSTATE" t_method_end "$(harness_utc_now)"
      program_stage_wanted "$PSTAGE_CAPTURE" && do_program_capture
      program_stage_wanted "$PSTAGE_RECORD" && build_program_row
      return 1
    fi
  fi
  program_stage_wanted "$PSTAGE_LOOP" && do_program_loop
  program_stage_wanted "$PSTAGE_COLLECT" && { do_program_collect || true; }
  program_stage_wanted "$PSTAGE_REVIEW" && do_program_review
  program_stage_wanted "$PSTAGE_REWORK" && do_program_rework
  program_stage_wanted "$PSTAGE_ACCEPT" && do_program_accept
  program_stage_wanted "$PSTAGE_CAPTURE" && do_program_capture
  program_stage_wanted "$PSTAGE_RECORD" && build_program_row
  [[ "$(harness_state_get "$PSTATE" method_failed)" != true ]]
}
