#!/usr/bin/env bash
set -uo pipefail

# Experiment harness: build one frozen feature several ways, review and rework every
# tree the same way, score each run, append the numbers to a ledger.
#
#   harness/run.sh <experiment-dir> [--only <fixture>:<method>[:<n>]] [--from <stage>]
#                  [--dry-run] [--no-cleanup] [--consumer <path>]
#
# Run from the consuming repo root. The experiment directory may be absolute or
# relative to that root. See harness/SPEC.md for the design and harness/README.md for
# the file shapes.
#
# Isolation is structural, not a policy the stages are asked to respect: a run's inputs
# are its fixture and its method and nothing else, the review brief exists before any
# method runs, the rework reads only its own tree's findings, and no stage reads across
# worktrees. There is no cross-check stage.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# ── Arguments ────────────────────────────────────────────────────────────────
EXPERIMENT_ARG=""
ONLY=""
FROM_STAGE=""
DRY_RUN=0
NO_CLEANUP=0
CONSUMER_ROOT="$DEFAULT_CONSUMER_ROOT"

usage() {
  sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while (( $# > 0 )); do
  case "$1" in
    --only)      ONLY="${2:?--only needs <fixture>:<method>[:<n>]}"; shift 2 ;;
    --from)      FROM_STAGE="${2:?--from needs a stage}"; shift 2 ;;
    --consumer)  CONSUMER_ROOT="$(cd "${2:?--consumer needs a path}" && pwd)"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --no-cleanup) NO_CLEANUP=1; shift ;;
    -h|--help)   usage 0 ;;
    -*)          harness_die "unknown option: $1" ;;
    *)           [[ -z "$EXPERIMENT_ARG" ]] || harness_die "unexpected argument: $1"
                 EXPERIMENT_ARG="$1"; shift ;;
  esac
done

[[ -n "$EXPERIMENT_ARG" ]] || usage 1

if [[ "$EXPERIMENT_ARG" == /* ]]; then
  EXPERIMENT_DIR="$EXPERIMENT_ARG"
else
  EXPERIMENT_DIR="$CONSUMER_ROOT/$EXPERIMENT_ARG"
fi
[[ -d "$EXPERIMENT_DIR" ]] || harness_die "no experiment directory at $EXPERIMENT_DIR"
EXPERIMENT_DIR="$(cd "$EXPERIMENT_DIR" && pwd)"
EXPERIMENT_JSON="$EXPERIMENT_DIR/experiment.json"
[[ -f "$EXPERIMENT_JSON" ]] || harness_die "no experiment.json in $EXPERIMENT_DIR"

FIXTURES_DIR="$CONSUMER_ROOT/plans/experiments/fixtures"
RESULTS_FILE="$EXPERIMENT_DIR/results.jsonl"
STATE_DIR="$EXPERIMENT_DIR/state"
LOG_DIR="$EXPERIMENT_DIR/logs"

if [[ -n "$FROM_STAGE" ]]; then
  case " $HARNESS_STAGES " in
    *" $FROM_STAGE "*) ;;
    *) harness_die "--from must be one of: $HARNESS_STAGES" ;;
  esac
fi

(( DRY_RUN )) && HARNESS_REQUIRED_TOOLS="jq git python3"
harness_require_tools

# ── Experiment ───────────────────────────────────────────────────────────────
EXPERIMENT_NAME="$(harness_json "$EXPERIMENT_JSON" .name)"
REPEATS="$(jq -r '.repeats // 1' "$EXPERIMENT_JSON")"
DO_REVIEW="$(jq -r '.stages.review // true' "$EXPERIMENT_JSON")"
DO_REWORK="$(jq -r '.stages.rework // true' "$EXPERIMENT_JSON")"
DO_ACCEPT="$(jq -r '.stages.accept // true' "$EXPERIMENT_JSON")"
PREDICTION="$(harness_json "$EXPERIMENT_JSON" .prediction)"
[[ -n "$PREDICTION" ]] || harness_die "experiment.json has no prediction — harness/EXPERIMENTS.md requires the checklist first"

# `run` is set per cell so the stage functions read one name rather than eight arguments.
FIXTURE=""; METHOD=""; REPEAT=""; BRANCH=""; SLUG=""; TREE=""; STATE=""
FIXTURE_DIR=""; FIXTURE_JSON=""; REPO_PATH=""; REMOTE=""; BASE=""
SPEC_REPO=""; SPEC_COMMIT=""; SPEC_PATH=""; SPEC_SECTIONS=""; SPEC_TREE=""
GATE_COMMAND=""; GATE_GREEN=""; GATE_MINUTES=""; BRIEF_FILE=""
METHOD_FAILED=false; PR_URL=""
COST_METHOD=0; COST_METHOD_REPORTED=0; COST_REVIEW=0; COST_REWORK=0
REVIEW_FIXED=0; REVIEW_ESCALATED=0; REWORK_RAN=false
ACCEPT_PASS=false; ACCEPT_LINES='[]'
GATE_COUNTS_PR_OPEN=""; GATE_COUNTS_GREEN=""; COST_LOST=0

say() { printf '%s\n' "$*"; }
dry() { printf '  $ %s\n' "$*"; }

# A ledger row's dollar fields must parse as JSON numbers even when a stage was skipped.
num() {
  local v="${1:-}"
  if [[ "$v" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then printf '%s' "$v"; else printf '0'; fi
}

stage_wanted() {
  # With --from, every stage before it is skipped; without, all run.
  local stage="$1" seen=0 s
  [[ -n "$FROM_STAGE" ]] || return 0
  for s in $HARNESS_STAGES; do
    [[ "$s" == "$FROM_STAGE" ]] && seen=1
    [[ "$s" == "$stage" ]] && { (( seen )) && return 0 || return 1; }
  done
  return 1
}

stage_begin() { harness_log "$BRANCH — stage $1"; harness_state_stage "$STATE" "$1" start "$(harness_utc_now)"; }
stage_end()   { harness_state_stage "$STATE" "$1" end "$(harness_utc_now)"; harness_state_stage "$STATE" "$1" outcome "$2"; }

# ── Cell resolution ──────────────────────────────────────────────────────────
resolve_cell() {
  FIXTURE="$1"; METHOD="$2"; REPEAT="$3"

  FIXTURE_DIR="$FIXTURES_DIR/$FIXTURE"
  FIXTURE_JSON="$FIXTURE_DIR/fixture.json"
  [[ -f "$FIXTURE_JSON" ]] || harness_die "no fixture at $FIXTURE_JSON"
  [[ -d "$HARNESS_METHODS_DIR/$METHOD" ]] || harness_die "no method at $HARNESS_METHODS_DIR/$METHOD"

  REPO_PATH="$(harness_json "$FIXTURE_JSON" .repo.path)"
  REMOTE="$(jq -r '.repo.remote // "origin"' "$FIXTURE_JSON")"
  BASE="$(harness_json "$FIXTURE_JSON" .base)"
  SPEC_REPO="$(harness_json "$FIXTURE_JSON" .spec.repo)"
  SPEC_COMMIT="$(harness_json "$FIXTURE_JSON" .spec.commit)"
  SPEC_PATH="$(harness_json "$FIXTURE_JSON" .spec.path)"
  SPEC_SECTIONS="$(jq -r '[.spec.sections[]] | join(", ")' "$FIXTURE_JSON")"
  GATE_COMMAND="$(harness_json "$FIXTURE_JSON" .gate.command)"
  GATE_GREEN="$(harness_json "$FIXTURE_JSON" .gate.green)"
  GATE_MINUTES="$(jq -r '.gate.minutes // "a few"' "$FIXTURE_JSON")"

  # The fixture names the stem; an experiment may override it for one fixture, which is
  # how a replay of a feature that has already been built avoids landing on the recorded
  # arm's branch — that branch is a cost record and must never gain a second arm's commits.
  local stem
  stem="$(jq -r --arg f "$FIXTURE" '.branch_stem_override[$f] // empty' "$EXPERIMENT_JSON")"
  [[ -n "$stem" ]] || stem="$(harness_json "$FIXTURE_JSON" .branch_stem)"
  BRANCH="$(harness_branch_name "$stem" "$METHOD" "$REPEAT" "$REPEATS")"
  SLUG="$(harness_slug_of_branch "$BRANCH")"
  TREE="$(harness_worktree_path "$REPO_PATH" "$BRANCH")"
  SPEC_TREE="$(harness_spec_worktree_path "$SPEC_REPO" "$FIXTURE")"
  STATE="$STATE_DIR/$BRANCH.json"
  BRIEF_FILE="$TREE/plans/features/$SLUG/BRIEF.md"

  METHOD_FAILED=false; PR_URL=""
  COST_METHOD=0; COST_METHOD_REPORTED=0; COST_REVIEW=0; COST_REWORK=0
  REVIEW_FIXED=0; REVIEW_ESCALATED=0; REWORK_RAN=false
  ACCEPT_PASS=false; ACCEPT_LINES='[]'
  GATE_COUNTS_PR_OPEN=""; GATE_COUNTS_GREEN=""; COST_LOST=0

  set_template_vars
}

# Every placeholder any template can name, resolved once per cell — the brief, the
# review preamble and the rework preamble all draw from this one set, so `--from review`
# fills exactly what `--from setup` would have.
set_template_vars() {
  harness_build_isolation "$REPO_PATH" "$TREE"
  HARNESS_BRANCH="$BRANCH"; HARNESS_BASE="$BASE"; HARNESS_SLUG="$SLUG"
  HARNESS_SPEC_TREE="$SPEC_TREE"; HARNESS_SPEC_PATH="$SPEC_PATH"
  HARNESS_SPEC_SECTIONS="$SPEC_SECTIONS"
  HARNESS_FACTS="$(cat "$FIXTURE_DIR/facts.md")"
  HARNESS_GATE_COMMAND="$GATE_COMMAND"; HARNESS_GATE_MINUTES="$GATE_MINUTES"
  HARNESS_FIXTURE="$FIXTURE"; HARNESS_EXPERIMENTS_DIR="$CONSUMER_ROOT/plans/experiments"
  HARNESS_AGENT_TOOLING="$TREE/agentTooling"
  HARNESS_FINDINGS="$(harness_findings_path "$TREE" "$SLUG")"
  HARNESS_FINDINGS_TEXT=""
  HARNESS_REVIEW_BRIEF="$(cat "$FIXTURE_DIR/review-brief.md")"
  HARNESS_BRIEF="$BRIEF_FILE"
  # Read by a method's run.sh: where to leave its result object, so a usage-limit stop
  # can be told from a work failure and its reset time parsed.
  export HARNESS_METHOD_RESULT="$LOG_DIR/$BRANCH-method-result.json"
  export HARNESS_LOG_DIR="$LOG_DIR"
  export HARNESS_BRANCH_NAME="$BRANCH"
}

# ── Stages ───────────────────────────────────────────────────────────────────
do_setup() {
  stage_begin setup
  # Read before the write below: an already-recorded start is what tells a resume of this
  # cell from a fresh cell landing on somebody else's branch.
  local first_setup=0
  [[ -z "$(harness_state_get "$STATE" t_setup_start)" ]] && first_setup=1
  harness_state_set_str "$STATE" t_setup_start "$(harness_utc_now)"

  git -C "$REPO_PATH" fetch -q "$REMOTE" || harness_warn "fetch of $REMOTE failed — using what is on disk"

  # A branch that already exists and that this cell has never set up is a collision, not
  # a resume: continuing would append this arm's commits to whatever that branch records
  # — in the WP7 case, the very arm the new run is being compared against.
  if (( first_setup )) && [[ ! -d "$TREE" && "${HARNESS_ALLOW_EXISTING_BRANCH:-0}" != 1 ]] \
     && ( git -C "$REPO_PATH" show-ref --verify --quiet "refs/heads/$BRANCH" \
          || git -C "$REPO_PATH" show-ref --verify --quiet "refs/remotes/$REMOTE/$BRANCH" ); then
    stage_end setup "branch-collision"
    harness_die "branch $BRANCH already exists in $REPO_PATH and this cell has no state.
  Set \"branch_stem_override\": {\"$FIXTURE\": \"<newStem>\"} in $EXPERIMENT_JSON,
  or pass HARNESS_ALLOW_EXISTING_BRANCH=1 if reusing that branch is really what you want."
  fi

  if [[ -d "$TREE" ]]; then
    harness_log "worktree already present: $TREE"
  elif git -C "$REPO_PATH" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$REPO_PATH" worktree add "$TREE" "$BRANCH" || harness_die "worktree add failed"
  else
    git -C "$REPO_PATH" worktree add -b "$BRANCH" "$TREE" "$BASE" || harness_die "worktree add failed"
  fi

  local cmd
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    harness_log "setup: $cmd"
    ( cd "$TREE" && eval "$cmd" ) || harness_die "fixture setup command failed: $cmd"
  done < <(jq -r '.setup[]? // empty' "$FIXTURE_JSON")

  local log="$LOG_DIR/$BRANCH-gate-setup.log"
  harness_run_gate "$TREE" "$GATE_COMMAND" "$log"
  if ! harness_gate_is_green "$log" "$GATE_GREEN"; then
    stage_end setup "gate-red"
    harness_die "gate is not green at $BASE in $TREE (see $log) — the fixture is broken, not the method"
  fi
  harness_state_set_str "$STATE" gate_counts_base "$(harness_gate_counts "$TREE")"

  if [[ ! -d "$SPEC_TREE" ]]; then
    git -C "$SPEC_REPO" fetch -q origin 2>/dev/null || true
    git -C "$SPEC_REPO" worktree add --detach "$SPEC_TREE" "$SPEC_COMMIT" \
      || harness_die "could not add the read-only spec worktree at $SPEC_TREE"
  fi

  write_stage_manifest "$SLUG" \
    "$SLUG — $FIXTURE built by the $METHOD method"
  stage_end setup ok
}

do_brief() {
  stage_begin brief
  mkdir -p "$(dirname "$BRIEF_FILE")"
  harness_fill_template "$HARNESS_METHODS_DIR/$METHOD/template.md" > "$BRIEF_FILE"
  stage_end brief ok
}

do_method() {
  stage_begin method
  harness_state_set_str "$STATE" t_method_start "$(harness_utc_now)"

  "$HARNESS_METHODS_DIR/$METHOD/run.sh" "$TREE" "$BRIEF_FILE" "$SLUG"
  local rc=$?
  if (( rc == METHOD_USAGE_LIMIT_RC )); then
    harness_state_intervention "$STATE" "method stopped on a usage limit; waited and retried once"
    harness_wait_for_usage_reset "$LOG_DIR/$BRANCH-method-result.json"
    "$HARNESS_METHODS_DIR/$METHOD/run.sh" "$TREE" "$BRIEF_FILE" "$SLUG"
    rc=$?
  fi
  if (( rc != 0 )); then
    METHOD_FAILED=true
    harness_state_set "$STATE" method_failed true
    stage_end method "failed($rc)"
    return 1
  fi

  PR_URL="$(harness_pr_url "$TREE" "$BRANCH")"
  if [[ -z "$PR_URL" ]]; then
    METHOD_FAILED=true
    harness_state_set "$STATE" method_failed true
    stage_end method "no-pr"
    harness_warn "$METHOD exited 0 but no PR is open for $BRANCH"
    return 1
  fi
  harness_state_set_str "$STATE" pr_url "$PR_URL"
  harness_state_set_str "$STATE" t_pr_open "$(harness_utc_now)"

  harness_close_manifest_window "$TREE" "$SLUG" "$(harness_utc_now)"
  harness_commit_all "$TREE" "$SLUG: close the manifest session window at PR-open" \
    || harness_warn "nothing to commit for the manifest window"
  harness_push "$TREE" "$BRANCH"

  GATE_COUNTS_PR_OPEN="$(harness_gate_counts "$TREE")"
  harness_state_set_str "$STATE" gate_counts_pr_open "$GATE_COUNTS_PR_OPEN"
  stage_end method ok
}

# A stage that re-runs (a `--from` resume after a kill) overwrites its manifest with
# a fresh window, and the killed attempt's session — inside the old window, outside
# the new one — vanishes from every ledger. Price an OPEN orphaned window before
# resetting it and bank the figure separately: cost_lost_usd is real spend on the
# branch that no method figure should absorb (the kill is an intervention, not the
# method), but the row must still carry it. A closed window is a completed attempt
# whose cost is already frozen elsewhere — never price it again.
open_manifest_window_of() {  # $1 slug -> prints the open window's "from", else nothing
  local readme="$TREE/plans/features/$1/README.md"
  [[ -f "$readme" ]] || return 0
  python3 - "$readme" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
m = re.search(r'```json\n(.*?)\n```', text, re.S)
if m:
    try:
        window = json.loads(m.group(1)).get("session_window") or {}
        if window.get("to") is None and window.get("from"):
            print(window["from"])
    except ValueError:
        pass
PY
}

manifest_window_from() {  # $1 slug -> prints the manifest window's "from", open or closed
  local readme="$TREE/plans/features/$1/README.md"
  [[ -f "$readme" ]] || return 0
  python3 - "$readme" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
m = re.search(r'```json\n(.*?)\n```', text, re.S)
if m:
    try:
        window = json.loads(m.group(1)).get("session_window") or {}
        if window.get("from"):
            print(window["from"])
    except ValueError:
        pass
PY
}

write_stage_manifest() {  # $1 slug, $2 title — price any orphaned open window first
  local slug="$1" title="$2" orphan_from lost
  orphan_from="$(open_manifest_window_of "$slug")"
  if [[ -n "$orphan_from" ]]; then
    harness_close_manifest_window "$TREE" "$slug" "$(harness_utc_now)" || true
    rm -f "$TREE/plans/features/$slug/planning.json"
    lost="$(capture_one "$slug")"
    # Drop the freeze this pricing wrote: the stage's own capture must not honour it.
    rm -f "$TREE/plans/features/$slug/planning.json"
    COST_LOST="$(awk -v a="$(num "$COST_LOST")" -v b="$(num "$lost")" 'BEGIN{printf "%.4f", a + b}')"
    harness_state_set_str "$STATE" cost_lost_usd "$COST_LOST"
    harness_state_intervention "$STATE" \
      "$slug: an earlier attempt's open window (from $orphan_from) was priced at \$$lost into cost_lost_usd before the stage re-ran"
    harness_log "$slug: orphaned window priced at \$$lost (cost_lost_usd now \$$COST_LOST)"
  fi
  harness_write_manifest "$TREE" "$slug" "$BRANCH" "$(harness_utc_now)" "$title" "$METHOD"
}

# One fresh claude in the tree, same preamble and same fixture brief on every tree of
# the experiment, with its own manifest and window.
do_review() {
  [[ "$DO_REVIEW" == true ]] || { harness_log "review stage disabled"; return 0; }
  stage_begin review
  local rslug="$SLUG-review"
  write_stage_manifest "$rslug" \
    "$rslug — the harness review pass over $BRANCH"

  local prompt="$LOG_DIR/$BRANCH-review-prompt.md"
  local result="$LOG_DIR/$BRANCH-review-result.json"
  harness_fill_template "$HARNESS_TEMPLATES_DIR/review-preamble.md" > "$prompt"

  harness_claude "$result" "$prompt" "$TREE" \
    --model "$HARNESS_MODEL" --max-budget-usd "$REVIEW_BUDGET_USD" \
    --permission-mode acceptEdits --allowedTools Bash
  local rc=$?
  COST_REVIEW="$(harness_claude_cost "$result")"
  if (( rc != 0 )) && harness_stopped_on_usage_limit "$result"; then
    harness_state_intervention "$STATE" "review stopped on a usage limit; waited and retried once"
    harness_wait_for_usage_reset "$result"
    harness_claude "$result" "$prompt" "$TREE" \
      --model "$HARNESS_MODEL" --max-budget-usd "$REVIEW_BUDGET_USD" \
      --permission-mode acceptEdits --allowedTools Bash
    rc=$?
    COST_REVIEW="$(harness_claude_cost "$result")"
  fi

  local findings
  findings="$(harness_findings_path "$TREE" "$SLUG")"
  REVIEW_FIXED="$(harness_findings_count "$findings" fixed)"
  REVIEW_ESCALATED="$(harness_findings_count "$findings" escalated)"
  harness_close_manifest_window "$TREE" "$rslug" "$(harness_utc_now)" || true
  harness_commit_all "$TREE" "review: $FIXTURE" || harness_log "review left nothing to commit"
  harness_push "$TREE" "$BRANCH"
  harness_state_set_str "$STATE" t_review_end "$(harness_utc_now)"
  harness_state_set_str "$STATE" cost_review_usd "$COST_REVIEW"
  harness_state_set "$STATE" review_fixed "$REVIEW_FIXED"
  harness_state_set "$STATE" review_escalated "$REVIEW_ESCALATED"
  stage_end review "ok(rc=$rc, fixed=$REVIEW_FIXED, escalated=$REVIEW_ESCALATED)"
}

# Only if the review escalated something, and reading nothing but this tree's findings.
do_rework() {
  [[ "$DO_REWORK" == true ]] || { harness_log "rework stage disabled"; return 0; }
  local findings
  findings="$(harness_findings_path "$TREE" "$SLUG")"
  REVIEW_ESCALATED="$(harness_findings_count "$findings" escalated)"
  if (( REVIEW_ESCALATED == 0 )); then
    harness_log "no escalated findings — skipping rework"
    return 0
  fi
  stage_begin rework
  local wslug="$SLUG-rework"
  write_stage_manifest "$wslug" \
    "$wslug — the harness rework pass over $BRANCH"

  HARNESS_FINDINGS="$findings"
  HARNESS_FINDINGS_TEXT="$(cat "$findings")"
  local prompt="$LOG_DIR/$BRANCH-rework-prompt.md"
  local result="$LOG_DIR/$BRANCH-rework-result.json"
  harness_fill_template "$HARNESS_TEMPLATES_DIR/rework-preamble.md" > "$prompt"

  harness_claude "$result" "$prompt" "$TREE" \
    --model "$HARNESS_MODEL" --max-budget-usd "$REWORK_BUDGET_USD" \
    --permission-mode acceptEdits --allowedTools Bash
  local rc=$?
  COST_REWORK="$(harness_claude_cost "$result")"
  REWORK_RAN=true
  harness_close_manifest_window "$TREE" "$wslug" "$(harness_utc_now)" || true
  harness_commit_all "$TREE" "rework: $FIXTURE" || harness_log "rework left nothing to commit"
  harness_push "$TREE" "$BRANCH"
  harness_state_set_str "$STATE" t_rework_end "$(harness_utc_now)"
  harness_state_set_str "$STATE" cost_rework_usd "$COST_REWORK"
  harness_state_set "$STATE" rework_ran true
  stage_end rework "ok(rc=$rc)"
}

do_accept() {
  [[ "$DO_ACCEPT" == true ]] || { harness_log "accept stage disabled"; return 0; }
  stage_begin accept
  local probe="$FIXTURE_DIR/accept/accept.py"
  local out="$LOG_DIR/$BRANCH-accept.txt"
  python3 "$probe" "$TREE" > "$out" 2>&1
  local rc=$?
  if (( rc == 0 )); then ACCEPT_PASS=true; else ACCEPT_PASS=false; fi
  ACCEPT_LINES="$(jq -R -s 'split("\n") | map(select(length > 0))' < "$out")"
  harness_state_set "$STATE" accept_pass "$ACCEPT_PASS"
  harness_state_set "$STATE" accept_lines "$ACCEPT_LINES"

  local log="$LOG_DIR/$BRANCH-gate-green.log"
  harness_run_gate "$TREE" "$GATE_COMMAND" "$log"
  GATE_COUNTS_GREEN="$(harness_gate_counts "$TREE")"
  harness_gate_is_green "$log" "$GATE_GREEN" || harness_warn "gate is not green after rework (see $log)"
  harness_state_set_str "$STATE" gate_counts_green "$GATE_COUNTS_GREEN"
  harness_state_set_str "$STATE" t_green "$(harness_utc_now)"
  stage_end accept "$( (( rc == 0 )) && echo pass || echo fail )"
}

# Cost capture runs from the WORKTREE's own vendored copy: capture_planning.py resolves
# its session root from the script's location, and a `claude -p` launched in
# ~/dev/repo-<branch> writes its transcript under the project directory for that path.
capture_one() {
  local slug="$1"
  local capture="$TREE/agentTooling/analysis/capture_planning.py"
  local report="$TREE/agentTooling/analysis/report.py"
  local dir="$TREE/plans/features/$slug"
  [[ -d "$dir" ]] || { printf '0'; return 0; }
  # capture_planning.py honours an existing planning.json as a frozen record and skips.
  # A freeze stamped before the slug's CURRENT manifest window opened belongs to an
  # earlier attempt — a failed run reused with HARNESS_ALLOW_EXISTING_BRANCH=1, or a
  # completed stage a --from resume re-ran (which rewrites the window) — and would
  # be reported as this run's cost: the first replayF2Direct run recorded $0 that way,
  # and a redone stage used to report the old attempt's cost. Rebuild it; a freeze
  # from inside the current window is left alone.
  local recapture=()
  if [[ -f "$dir/planning.json" ]]; then
    local stamp started
    stamp="$(jq -r '.captured_at // empty' "$dir/planning.json" 2>/dev/null)"
    started="$(manifest_window_from "$slug")"
    [[ -n "$started" ]] || started="$(harness_state_get "$STATE" t_setup_start)"
    if [[ -n "$stamp" && -n "$started" && "$stamp" < "$started" ]]; then
      # capture_one runs inside $(...): stdout is the cost figure, so log to stderr.
      harness_log "capture: $slug carries a freeze predating its manifest window ($stamp < $started) — recapturing" >&2
      recapture=(--recapture)
    fi
  fi
  python3 "$capture" "$slug" ${recapture[@]+"${recapture[@]}"} >> "$LOG_DIR/$BRANCH-capture.log" 2>&1 || true
  python3 "$report" "$slug" >> "$LOG_DIR/$BRANCH-capture.log" 2>&1 || true
  local total=0
  if [[ -f "$dir/report.json" ]]; then
    total="$(jq -r '.cost.total // 0' "$dir/report.json")"
  fi
  rm -f "$dir/report.json" "$dir/report.md"
  printf '%s' "$total"
}

do_capture() {
  stage_begin capture
  COST_METHOD="$(capture_one "$SLUG")"
  COST_REVIEW="$(capture_one "$SLUG-review")"
  COST_REWORK="$(capture_one "$SLUG-rework")"
  # Cross-check against what `claude -p` itself reported for the method's first session
  # (the implementer, or the plans architect — never the batch, so captured may exceed
  # it). Captured below 90% of reported, or zero against a non-zero report, means the
  # capture missed the session: a manifest window or branch mismatch, or a stale freeze.
  COST_METHOD_REPORTED="$(num "$(harness_claude_cost "$LOG_DIR/$BRANCH-method-result.json")")"
  if awk -v c="$(num "$COST_METHOD")" -v r="$COST_METHOD_REPORTED" \
       'BEGIN { exit (r > 0 && c < 0.9 * r) ? 0 : 1 }'; then
    harness_warn "capture: $SLUG captured \$$COST_METHOD but claude reported \$$COST_METHOD_REPORTED — check the manifest's branch and session window"
  fi
  harness_state_set_str "$STATE" cost_method_usd "$COST_METHOD"
  harness_state_set_str "$STATE" cost_method_reported_usd "$COST_METHOD_REPORTED"
  harness_state_set_str "$STATE" cost_review_usd "$COST_REVIEW"
  harness_state_set_str "$STATE" cost_rework_usd "$COST_REWORK"
  # planning.json is the frozen record and the transcripts behind it expire; commit it
  # onto the branch, which SPEC.md §3 calls the cost record, and leave the tree clean
  # so the worktree can be removed without --force.
  harness_commit_all "$TREE" "$SLUG: freeze the harness cost capture" \
    || harness_log "nothing to commit after capture"
  harness_push "$TREE" "$BRANCH"
  stage_end capture ok
}

# A `--from` resume runs record in a fresh process: fields set by stages of the
# killed process exist only in the state file, so a state value wins over this
# process's per-cell default (which is what the row silently got before this fix).
state_or() {  # $1 state key, $2 fallback
  local v; v="$(harness_state_get "$STATE" "$1")"
  if [[ -n "$v" ]]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}

build_ledger_row() {  # the `record` stage: one appended results.jsonl row + scorecard render
  stage_begin record
  PR_URL="$(state_or pr_url "$PR_URL")"
  REVIEW_FIXED="$(state_or review_fixed "$REVIEW_FIXED")"
  REVIEW_ESCALATED="$(state_or review_escalated "$REVIEW_ESCALATED")"
  REWORK_RAN="$(state_or rework_ran "$REWORK_RAN")"
  GATE_COUNTS_PR_OPEN="$(state_or gate_counts_pr_open "$GATE_COUNTS_PR_OPEN")"
  GATE_COUNTS_GREEN="$(state_or gate_counts_green "$GATE_COUNTS_GREEN")"
  ACCEPT_PASS="$(state_or accept_pass "$ACCEPT_PASS")"
  COST_LOST="$(num "$(state_or cost_lost_usd "$COST_LOST")")"
  local state_accept_lines
  state_accept_lines="$(jq -c '.accept_lines // empty' "$STATE" 2>/dev/null)"
  [[ -n "$state_accept_lines" ]] && ACCEPT_LINES="$state_accept_lines"
  COST_METHOD="$(num "$(state_or cost_method_usd "$COST_METHOD")")"
  COST_METHOD_REPORTED="$(num "$(harness_state_get "$STATE" cost_method_reported_usd)")"
  COST_REVIEW="$(num "$(state_or cost_review_usd "$COST_REVIEW")")"
  COST_REWORK="$(num "$(state_or cost_rework_usd "$COST_REWORK")")"
  local green
  green="$(awk -v a="$COST_METHOD" -v b="$COST_REVIEW" -v c="$COST_REWORK" \
           'BEGIN{printf "%.4f", a + b + c}')"
  harness_state_set_str "$STATE" cost_green_usd "$green"

  # -c: results.jsonl is one row per line, and a pretty-printed object is not a row.
  local row
  row="$(jq -c -n \
    --arg experiment "$EXPERIMENT_NAME" --arg fixture "$FIXTURE" --arg method "$METHOD" \
    --argjson repeat "$REPEAT" --arg branch "$BRANCH" --arg slug "$SLUG" \
    --arg pr_url "$PR_URL" --arg base "$BASE" --arg spec_commit "$SPEC_COMMIT" \
    --arg model "$HARNESS_MODEL" \
    --arg t_setup_start "$(harness_state_get "$STATE" t_setup_start)" \
    --arg t_method_start "$(harness_state_get "$STATE" t_method_start)" \
    --arg t_pr_open "$(harness_state_get "$STATE" t_pr_open)" \
    --arg t_review_end "$(harness_state_get "$STATE" t_review_end)" \
    --arg t_rework_end "$(harness_state_get "$STATE" t_rework_end)" \
    --arg t_green "$(harness_state_get "$STATE" t_green)" \
    --argjson cost_method_usd "$COST_METHOD" \
    --argjson cost_method_reported_usd "$COST_METHOD_REPORTED" \
    --argjson cost_review_usd "$COST_REVIEW" \
    --argjson cost_rework_usd "$COST_REWORK" \
    --argjson cost_green_usd "$green" \
    --argjson cost_lost_usd "$COST_LOST" \
    --argjson review_fixed "$(num "$REVIEW_FIXED")" \
    --argjson review_escalated "$(num "$REVIEW_ESCALATED")" \
    --argjson rework_ran "$REWORK_RAN" \
    --arg gate_counts_pr_open "$GATE_COUNTS_PR_OPEN" \
    --arg gate_counts_green "$GATE_COUNTS_GREEN" \
    --argjson accept_pass "$ACCEPT_PASS" \
    --argjson accept_lines "$ACCEPT_LINES" \
    --argjson method_failed "$METHOD_FAILED" \
    --argjson interventions "$(jq -c '.interventions // []' "$STATE")" \
    --arg harness_version "$(harness_version)" \
    '{experiment: $experiment, fixture: $fixture, method: $method, repeat: $repeat,
      branch: $branch, slug: $slug, pr_url: $pr_url, base: $base,
      spec_commit: $spec_commit, model: $model,
      t_setup_start: $t_setup_start, t_method_start: $t_method_start,
      t_pr_open: $t_pr_open, t_review_end: $t_review_end,
      t_rework_end: $t_rework_end, t_green: $t_green,
      cost_method_usd: $cost_method_usd, cost_method_reported_usd: $cost_method_reported_usd,
      cost_review_usd: $cost_review_usd,
      cost_rework_usd: $cost_rework_usd, cost_green_usd: $cost_green_usd,
      cost_lost_usd: $cost_lost_usd,
      review_fixed: $review_fixed, review_escalated: $review_escalated,
      rework_ran: $rework_ran,
      gate_counts_pr_open: $gate_counts_pr_open, gate_counts_green: $gate_counts_green,
      accept_pass: $accept_pass, accept_lines: $accept_lines,
      method_failed: $method_failed, interventions: $interventions,
      harness_version: $harness_version}')"
  printf '%s\n' "$row" >> "$RESULTS_FILE"

  python3 "$SCRIPT_DIR/scorecard.py" "$EXPERIMENT_DIR" || harness_warn "scorecard render failed"

  if (( NO_CLEANUP )); then
    harness_log "--no-cleanup: leaving $TREE in place"
  else
    git -C "$REPO_PATH" worktree remove "$TREE" \
      || harness_warn "could not remove $TREE — remove it by hand (the branch and PR stay)"
  fi
  stage_end record ok
}

# ── Dry run ──────────────────────────────────────────────────────────────────
dry_run_cell() {
  say ""
  say "── $FIXTURE × $METHOD × $REPEAT ─────────────────────────────"
  say "  branch:        $BRANCH"
  say "  slug:          $SLUG"
  say "  worktree:      $TREE"
  say "  spec worktree: $SPEC_TREE  (detached at $SPEC_COMMIT, read-only)"
  say "  state file:    $STATE"
  say "  stages:        $(for s in $HARNESS_STAGES; do stage_wanted "$s" && printf '%s ' "$s"; done)"
  say "  review: $DO_REVIEW   rework: $DO_REWORK   accept: $DO_ACCEPT"
  say "  commands:"
  dry "git -C $REPO_PATH fetch -q $REMOTE"
  dry "git -C $REPO_PATH worktree add -b $BRANCH $TREE $BASE"
  local cmd
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    dry "cd $TREE && $cmd"
  done < <(jq -r '.setup[]? // empty' "$FIXTURE_JSON")
  dry "cd $TREE && $GATE_COMMAND      # require: $GATE_GREEN"
  dry "git -C $SPEC_REPO worktree add --detach $SPEC_TREE $SPEC_COMMIT"
  dry "write $TREE/plans/features/$SLUG/README.md   (manifest skeleton, session_window.from = now)"
  dry "fill $HARNESS_METHODS_DIR/$METHOD/template.md -> $BRIEF_FILE"
  dry "$HARNESS_METHODS_DIR/$METHOD/run.sh $TREE $BRIEF_FILE $SLUG"
  dry "$HARNESS_GH_BIN pr view $BRANCH --json url --jq .url"
  if [[ "$DO_REVIEW" == true ]]; then
    dry "$HARNESS_CLAUDE_BIN -p --output-format json --model $HARNESS_MODEL --max-budget-usd $REVIEW_BUDGET_USD --permission-mode acceptEdits --allowedTools Bash <review preamble + $FIXTURE_DIR/review-brief.md>   (cwd $TREE)"
  fi
  if [[ "$DO_REWORK" == true ]]; then
    dry "$HARNESS_CLAUDE_BIN -p --output-format json --model $HARNESS_MODEL --max-budget-usd $REWORK_BUDGET_USD --permission-mode acceptEdits --allowedTools Bash <rework preamble + $(harness_findings_path "$TREE" "$SLUG")>   (only if escalated >= 1)"
  fi
  if [[ "$DO_ACCEPT" == true ]]; then
    dry "python3 $FIXTURE_DIR/accept/accept.py $TREE"
    dry "cd $TREE && $GATE_COMMAND"
  fi
  dry "python3 $TREE/agentTooling/analysis/capture_planning.py $SLUG   (also $SLUG-review, $SLUG-rework)"
  dry "python3 $TREE/agentTooling/analysis/report.py $SLUG             (read cost.total, then delete report.json/md)"
  dry "append one row to $RESULTS_FILE"
  dry "python3 $SCRIPT_DIR/scorecard.py $EXPERIMENT_DIR"
  (( NO_CLEANUP )) || dry "git -C $REPO_PATH worktree remove $TREE   (branch and PR kept)"
}

# ── Drive ────────────────────────────────────────────────────────────────────
run_cell() {
  mkdir -p "$STATE_DIR" "$LOG_DIR"
  harness_state_init "$STATE"
  harness_state_set_str "$STATE" experiment "$EXPERIMENT_NAME"
  harness_state_set_str "$STATE" fixture "$FIXTURE"
  harness_state_set_str "$STATE" method "$METHOD"
  harness_state_set "$STATE" repeat "$REPEAT"
  harness_state_set_str "$STATE" branch "$BRANCH"
  harness_state_set_str "$STATE" slug "$SLUG"

  stage_wanted setup  && { do_setup || return 1; }
  stage_wanted brief  && { do_brief || return 1; }
  if stage_wanted method; then
    if ! do_method; then
      harness_warn "method failed — recording the row and skipping the remaining model stages"
      stage_wanted capture && do_capture
      stage_wanted record && build_ledger_row
      return 1
    fi
  else
    PR_URL="$(harness_state_get "$STATE" pr_url)"
  fi
  stage_wanted review && do_review
  stage_wanted rework && do_rework
  stage_wanted accept && do_accept
  stage_wanted capture && do_capture
  stage_wanted record && build_ledger_row
  return 0
}

cell_selected() {
  local fixture="$1" method="$2" repeat="$3" want_f want_m want_n rest
  [[ -n "$ONLY" ]] || return 0
  want_f="${ONLY%%:*}"; want_m=""; want_n=""
  if [[ "$ONLY" == *:* ]]; then
    rest="${ONLY#*:}"
    want_m="${rest%%:*}"
    [[ "$rest" == *:* ]] && want_n="${rest#*:}"
  fi
  [[ "$fixture" == "$want_f" ]] || return 1
  [[ -z "$want_m" || "$method" == "$want_m" ]] || return 1
  [[ -z "$want_n" || "$repeat" == "$want_n" ]] || return 1
  return 0
}

say "########## experiment: $EXPERIMENT_NAME ##########"
say "prediction: $PREDICTION"
(( DRY_RUN )) && say "(dry run — nothing below is executed)"

failures=0
for fixture in $(jq -r '.fixtures[]' "$EXPERIMENT_JSON"); do
  for method in $(jq -r '.methods[]' "$EXPERIMENT_JSON"); do
    for repeat in $(seq 1 "$REPEATS"); do
      cell_selected "$fixture" "$method" "$repeat" || continue
      resolve_cell "$fixture" "$method" "$repeat"
      if (( DRY_RUN )); then
        dry_run_cell
      else
        run_cell || failures=$(( failures + 1 ))
      fi
    done
  done
done

if (( DRY_RUN )); then
  say ""
  say "dry run complete — no worktree, no branch, no model call, no ledger row."
  exit 0
fi

say ""
if (( failures > 0 )); then
  say "########## experiment $EXPERIMENT_NAME: $failures cell(s) did not finish ##########"
  exit 1
fi
say "########## experiment $EXPERIMENT_NAME: complete — see $EXPERIMENT_DIR/SCORECARD.md ##########"
