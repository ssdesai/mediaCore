#!/usr/bin/env bash
set -uo pipefail

# Experiment harness: build one frozen feature several ways, review and rework every
# tree the same way, score each run, append the numbers to a ledger.
#
#   harness/run.sh <experiment-dir> [--only <fixture>[:<method>[:<arm>][:<n>]]]
#                  [--only <program>[:orchestrator[:<arm>][:<n>]]] [--from <stage>]
#                  [--dry-run] [--no-cleanup] [--consumer <path>]
#
# Run from the consuming repo root. The experiment directory may be absolute or
# relative to that root. See harness/SPEC.md for the design and harness/README.md for
# the file shapes. A program cell (an orchestrator running a list of features) has
# its own stages: setup brief loop collect review rework accept capture record.
#
# Isolation is structural, not a policy the stages are asked to respect: a run's inputs
# are its fixture and its method and nothing else, the review brief exists before any
# method runs, the rework reads only its own tree's findings, and no stage reads across
# worktrees. There is no cross-check stage.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Reading metrics (harness/reading_metrics.py): its row fields, in the order they print
READING_METRICS_SCRIPT="reading_metrics.py"
READING_FIELDS="read_files_before_edit read_bytes_before_edit readme_bytes_read"

# ── Arguments ────────────────────────────────────────────────────────────────
EXPERIMENT_ARG=""
ONLY=""
FROM_STAGE=""
DRY_RUN=0
NO_CLEANUP=0
CONSUMER_ROOT="$DEFAULT_CONSUMER_ROOT"

usage() {
  sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while (( $# > 0 )); do
  case "$1" in
    --only)      ONLY="${2:?--only needs <fixture or program>[:<method>[:<arm>][:<n>]]}"; shift 2 ;;
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
harness_require_own_driver

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
  case " $HARNESS_STAGES $HARNESS_PROGRAM_STAGES " in
    *" $FROM_STAGE "*) ;;
    *) harness_die "--from must be one of: $HARNESS_STAGES (a program cell: $HARNESS_PROGRAM_STAGES)" ;;
  esac
fi

(( DRY_RUN )) && HARNESS_REQUIRED_TOOLS="jq git python3"
# A dry run names the clone a run would make rather than making it.
(( DRY_RUN )) && export HARNESS_RESOLVE_NO_CLONE=1
harness_require_tools

# ── Experiment ───────────────────────────────────────────────────────────────
EXPERIMENT_NAME="$(harness_json "$EXPERIMENT_JSON" .name)"
REPEATS="$(jq -r '.repeats // 1' "$EXPERIMENT_JSON")"
DO_REVIEW="$(harness_stage_enabled "$EXPERIMENT_JSON" review)"
DO_REWORK="$(harness_stage_enabled "$EXPERIMENT_JSON" rework)"
DO_ACCEPT="$(harness_stage_enabled "$EXPERIMENT_JSON" accept)"
PREDICTION="$(harness_json "$EXPERIMENT_JSON" .prediction)"
[[ -n "$PREDICTION" ]] || harness_die "experiment.json has no prediction — harness/EXPERIMENTS.md requires the checklist first"

# `run` is set per cell so the stage functions read one name rather than eight arguments.
FIXTURE=""; METHOD=""; REPEAT=""; BRANCH=""; SLUG=""; TREE=""; STATE=""
ARM=""; ARM_SHA=""; AT_CHECKOUT=""
EXPERIMENT_ARM_KIND=""; ARM_BASE=""; FIXTURE_BASE=""
FIXTURE_DIR=""; FIXTURE_JSON=""; REPO_PATH=""; REMOTE=""; BASE=""
SPEC_REPO=""; SPEC_COMMIT=""; SPEC_PATH=""; SPEC_SECTIONS=""; SPEC_TREE=""
GATE_COMMAND=""; GATE_GREEN=""; GATE_MINUTES=""; BRIEF_FILE=""
METHOD_FAILED=false; PR_URL=""; PR_OPENED_BY_HARNESS=false; RECAPTURE_METHOD=false
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
  FIXTURE="$1"; METHOD="$2"; REPEAT="$3"; ARM="${4:-}"; ARM_SHA="${5:-}"
  [[ "$ARM" != "-" ]] || { ARM=""; ARM_SHA=""; }
  ARM_BASE=""
  if [[ -n "$ARM" && "$EXPERIMENT_ARM_KIND" == "$HARNESS_ARM_KIND_BASE" ]]; then
    ARM_BASE="$ARM_SHA"; ARM_SHA=""
  fi

  require_fixture
  [[ -d "$HARNESS_METHODS_DIR/$METHOD" ]] || harness_die "no method at $HARNESS_METHODS_DIR/$METHOD"
  if [[ -n "$ARM" ]]; then
    [[ "$ARM" =~ $HARNESS_ARM_LABEL_RE ]] || harness_die "arm label must be bare lower-case letters: $ARM"
    if [[ "$EXPERIMENT_ARM_KIND" == "$HARNESS_ARM_KIND_BASE" ]]; then
      [[ -n "$ARM_BASE" ]] || harness_die "arm $ARM names no commit of the measured repository in $EXPERIMENT_JSON"
    else
      [[ -n "$ARM_SHA" ]] || harness_die "arm $ARM names no agentTooling commit in $EXPERIMENT_JSON"
    fi
  fi

  # The fixture's repository is the consumer (a repo block naming another is refused here,
  # the first point the fixture is read); only an external spec repository is resolved.
  REPO_PATH="$(harness_fixture_repo "$FIXTURE_JSON")" || exit 1
  REMOTE="$(jq -r '.repo.remote // "origin"' "$FIXTURE_JSON")"
  BASE="$(harness_json "$FIXTURE_JSON" .base)"
  FIXTURE_BASE="$BASE"
  if [[ -n "$ARM_BASE" ]]; then BASE="$ARM_BASE"; fi
  SPEC_REPO="$(harness_fixture_spec_repo "$FIXTURE_JSON")" || exit 1
  read_fixture_fields

  # The fixture names the stem; an experiment may override it for one fixture, which is
  # how a replay of a feature that has already been built avoids landing on the recorded
  # arm's branch — that branch is a cost record and must never gain a second arm's commits.
  local stem
  stem="$(jq -r --arg f "$FIXTURE" '.branch_stem_override[$f] // empty' "$EXPERIMENT_JSON")"
  [[ -n "$stem" ]] || stem="$(harness_json "$FIXTURE_JSON" .branch_stem)"
  BRANCH="$(harness_branch_name "$stem" "$METHOD" "$REPEAT" "$REPEATS" "$ARM")"
  SLUG="$(harness_slug_of_branch "$BRANCH")"
  TREE="$(harness_worktree_path "$REPO_PATH" "$BRANCH")"
  SPEC_TREE="$(harness_spec_worktree_path "$SPEC_REPO" "$FIXTURE")"
  STATE="$STATE_DIR/$BRANCH.json"
  BRIEF_FILE="$TREE/plans/features/$SLUG/BRIEF.md"

  reset_cell_results

  set_template_vars
}

# The fixture's directory and file, or a death: the first thing any cell reads.
require_fixture() {
  FIXTURE_DIR="$FIXTURES_DIR/$FIXTURE"
  FIXTURE_JSON="$FIXTURE_DIR/fixture.json"
  [[ -f "$FIXTURE_JSON" ]] || harness_die "no fixture at $FIXTURE_JSON"
}

# What fixture.json says that needs no repository resolved (a program feature reads the
# same fields; its repository, base and spec checkout come from the program).
read_fixture_fields() {
  SPEC_COMMIT="$(harness_json "$FIXTURE_JSON" .spec.commit)"
  SPEC_PATH="$(harness_json "$FIXTURE_JSON" .spec.path)"
  SPEC_SECTIONS="$(jq -r '[.spec.sections[]] | join(", ")' "$FIXTURE_JSON")"
  GATE_COMMAND="$(harness_json "$FIXTURE_JSON" .gate.command)"
  GATE_GREEN="$(harness_json "$FIXTURE_JSON" .gate.green)"
  GATE_MINUTES="$(jq -r '.gate.minutes // "a few"' "$FIXTURE_JSON")"
}

reset_cell_results() {
  METHOD_FAILED=false; PR_URL=""; PR_OPENED_BY_HARNESS=false; RECAPTURE_METHOD=false
  COST_METHOD=0; COST_METHOD_REPORTED=0; COST_REVIEW=0; COST_REWORK=0
  REVIEW_FIXED=0; REVIEW_ESCALATED=0; REWORK_RAN=false
  ACCEPT_PASS=false; ACCEPT_LINES='[]'
  GATE_COUNTS_PR_OPEN=""; GATE_COUNTS_GREEN=""; COST_LOST=0
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
  setup_tree
  write_stage_manifest "$SLUG" \
    "$SLUG — $FIXTURE built by the $METHOD method"
  stage_end setup ok
}

# Worktree, pin, fixture setup, gate rehearsal and spec worktree: everything setup does
# before the manifest skeleton. A program feature runs it too, with START_POINT set to the
# commit its branch is cut at (the previous feature's tip when it depends on it); empty,
# the cell's BASE. Its stage bookkeeping is the caller's (stage_begin before, stage_end after).
START_POINT=""
# 1: a red gate rehearsal ends the run (every cell, and a program's non-dependent feature);
# program-stages.sh sets 0 around a dependent feature's setup. GATE_RED_RAN_ANYWAY is set
# by setup_tree when it let a red gate through.
GATE_RED_FATAL=1
GATE_RED_RAN_ANYWAY=0
setup_tree() {
  # Read before the write below: an already-recorded start is what tells a resume of this
  # cell from a fresh cell landing on somebody else's branch.
  local first_setup=0
  [[ -z "$(harness_state_get "$STATE" t_setup_start)" ]] && first_setup=1
  harness_state_set_str "$STATE" t_setup_start "$(harness_utc_now)"

  git -C "$REPO_PATH" fetch -q "$REMOTE" || harness_warn "fetch of $REMOTE failed — using what is on disk"
  # A base that is a prep commit on no fetched branch: fetch it by sha once (no ref moves).
  harness_resolve_commit "$REPO_PATH" "$BASE" "$REMOTE" >/dev/null \
    || harness_die "base $BASE does not resolve in $REPO_PATH, even after fetching it from $REMOTE"

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
    git -C "$REPO_PATH" worktree add -b "$BRANCH" "$TREE" "${START_POINT:-$BASE}" || harness_die "worktree add failed"
  fi

  # The arm's agentTooling version, pinned before anything reads the vendored copy: the
  # fixture's setup, the gate, the method, the review and the capture all run from it.
  # Skipped only when the branch already carries its pin commit — not merely because the
  # tree exists: a pin that died after the worktree was added (a clone the cloud proxy
  # refused, say) leaves a tree with no pin, and the re-run must still pin it.
  if [[ -n "$ARM_SHA" ]] && ! git -C "$TREE" log --format=%s "$BASE..HEAD" 2>/dev/null \
       | grep -qxF "$HARNESS_PIN_SUBJECT_PREFIX ${ARM_SHA:0:$PIN_SHORT_SHA_LEN}"; then
    AT_CHECKOUT="$(harness_resolve_repo "$HARNESS_AGENT_TOOLING_URL")" || exit 1
    harness_pin_agent_tooling "$TREE" "$ARM_SHA" "$AT_CHECKOUT"
  fi
  harness_state_set_str "$STATE" agent_tooling "$ARM_SHA"

  local cmd
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    harness_log "setup: $cmd"
    ( cd "$TREE" && eval "$cmd" ) || harness_die "fixture setup command failed: $cmd"
  done < <(jq -r '.setup[]? // empty' "$FIXTURE_JSON")

  local log="$LOG_DIR/$BRANCH-gate-setup.log"
  harness_run_gate "$TREE" "$GATE_COMMAND" "$log"
  GATE_RED_RAN_ANYWAY=0
  if ! harness_gate_is_green "$log" "$GATE_GREEN"; then
    if (( GATE_RED_FATAL )); then
      stage_end setup "gate-red"
      harness_die "gate is not green at $BASE in $TREE (see $log) — the fixture is broken, not the method"
    fi
    # A dependent program feature: the predecessor's branch is what it is; run anyway.
    local red_tip
    red_tip="$(git -C "$TREE" rev-parse --short=7 HEAD)"
    harness_warn "gate is red at the previous feature's tip $red_tip in $TREE (see $log) — running anyway"
    harness_state_intervention "$STATE" "$BRANCH: gate red at the previous feature's tip $red_tip; ran anyway"
    GATE_RED_RAN_ANYWAY=1
  fi
  harness_state_set_str "$STATE" gate_counts_base "$(harness_gate_counts "$TREE")"

  if [[ ! -d "$SPEC_TREE" ]]; then
    git -C "$SPEC_REPO" fetch -q origin 2>/dev/null || true
    git -C "$SPEC_REPO" worktree add --detach "$SPEC_TREE" "$SPEC_COMMIT" \
      || harness_die "could not add the read-only spec worktree at $SPEC_TREE"
  fi
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

  settle_pr || return 1
  stage_end method ok
}

# The PR step of the method stage, and the whole of a resume that skips the method
# (`--from review` on a cell recorded `no-pr`: do_pr_resume). Returns 1 with the stage
# closed as "no-pr" when there is no PR and the harness could not open one.
settle_pr() {
  PR_URL="$(harness_pr_url "$TREE" "$BRANCH")"
  # The build is the arm's, the PR bookkeeping the driver's. A method that exited 0 with
  # its branch pushed and commits beyond the base has built the feature; when its own
  # PR hook could not open the PR (an August arm's plans/pr.sh, `gh` unauthenticated in a
  # cloud container) the harness opens it, through the driver's forge, and says so on the
  # row — never silently. Title and body follow the direct method: the slug, and a body
  # that names who opened it.
  if [[ -z "$PR_URL" ]] && harness_branch_pushed "$TREE" "$BRANCH" \
       && harness_branch_has_commits "$TREE" "$BASE"; then
    local pr_body="$LOG_DIR/$BRANCH-pr-body.md"
    printf '%s\n\n%s\n' "$SLUG" \
      "Opened by the experiment harness, not by the $METHOD method: it exited 0 with this branch pushed and commits beyond $BASE, and no PR was open." > "$pr_body"
    PR_URL="$(harness_pr_open "$TREE" "$BRANCH" "$SLUG" "$pr_body")"
    if [[ -n "$PR_URL" ]]; then
      PR_OPENED_BY_HARNESS=true
      harness_state_set "$STATE" pr_opened_by_harness true
      harness_state_intervention "$STATE" "$METHOD exited 0 with the branch pushed but no PR open; the harness opened $PR_URL"
      harness_warn "$METHOD opened no PR for $BRANCH — the harness opened $PR_URL"
    fi
  fi
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
}

# A cell whose method built and pushed but was recorded method_failed ("no-pr") only
# because no PR was open — an old harness's verdict — resumed past the method stage. The
# method is never re-run (a build costs real money): the worktree is brought back from the
# branch if the record stage removed it, the PR is checked and, if need be, opened by the
# harness, the state is cleared of method_failed, and the later stages go on. The method's
# cost is re-captured with the driver's rates (RECAPTURE_METHOD).
resume_no_pr() {
  [[ "$(harness_state_get "$STATE" method_failed)" == true \
     && "$(jq -r '.stages.method.outcome // empty' "$STATE")" == no-pr ]]
}

do_pr_resume() {
  harness_log "$BRANCH — resuming a cell recorded no-pr: PR check/open only, the method is not re-run"
  ensure_resume_trees
  stage_begin method
  if ! settle_pr; then
    METHOD_FAILED=true
    return 1
  fi
  METHOD_FAILED=false
  harness_state_set "$STATE" method_failed false
  harness_state_intervention "$STATE" "resumed from no-pr with --from $FROM_STAGE: the method was not re-run; the PR is $PR_URL"
  RECAPTURE_METHOD=true
  stage_end method "ok(pr-resumed)"
}

# The worktree and the spec worktree, which a finished cell's record stage removes.
ensure_resume_trees() {
  if [[ ! -d "$TREE" ]]; then
    git -C "$REPO_PATH" fetch -q "$REMOTE" 2>/dev/null || harness_warn "fetch of $REMOTE failed — using what is on disk"
    if git -C "$REPO_PATH" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      git -C "$REPO_PATH" worktree add "$TREE" "$BRANCH" || harness_die "worktree add failed for the resume"
    elif git -C "$REPO_PATH" show-ref --verify --quiet "refs/remotes/$REMOTE/$BRANCH"; then
      git -C "$REPO_PATH" worktree add -b "$BRANCH" "$TREE" "$REMOTE/$BRANCH" || harness_die "worktree add failed for the resume"
    else
      harness_die "cannot resume $BRANCH: it is on no local branch and not on $REMOTE"
    fi
  fi
  if [[ ! -d "$SPEC_TREE" ]]; then
    git -C "$SPEC_REPO" worktree add --detach "$SPEC_TREE" "$SPEC_COMMIT" \
      || harness_die "could not add the read-only spec worktree at $SPEC_TREE"
  fi
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

# Measuring is the driver's, building is the arm's: cost capture runs from the DRIVER's
# own analysis/ (the copy this run.sh lives in, with today's rates and capture rules),
# never from the worktree's vendored copy, which a fixture's historical base can leave
# months stale — an old rates table has no price for today's `opus`/`sonnet` and leaves
# those sessions out. `--arm-root $TREE` points the driver's scripts at the worktree's
# plans/features/; the transcripts are found as before (the session root is the primary
# checkout the worktree belongs to, and `claim_roots` admits the worktree's own project
# directory by the manifest's branches).
capture_one() {
  local slug="$1"
  local capture="$AGENT_TOOLING_DIR/analysis/capture_planning.py"
  local report="$AGENT_TOOLING_DIR/analysis/report.py"
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
  if [[ "$slug" == "$SLUG" && "$RECAPTURE_METHOD" == true ]]; then
    # A resume past a method recorded no-pr: its freeze was priced then, perhaps with the
    # arm's stale rates, and the method is not re-run — price the same transcripts again.
    harness_log "capture: $slug resumed past a no-pr method — recapturing at the driver's rates" >&2
    recapture=(--recapture)
  elif [[ -f "$dir/planning.json" ]]; then
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
  python3 "$capture" "$slug" --arm-root "$TREE" ${recapture[@]+"${recapture[@]}"} >> "$LOG_DIR/$BRANCH-capture.log" 2>&1 || true
  python3 "$report" "$slug" --arm-root "$TREE" >> "$LOG_DIR/$BRANCH-capture.log" 2>&1 || true
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

# What the method's sessions read before their first edit: the transcripts filed under
# the worktree's own project directory, inside [t_method_start, t_pr_open] (now, when
# no PR opened). Ordinary cells only: a program feature's capture never calls this.
do_reading_metrics() {
  local from to out field
  from="$(harness_state_get "$STATE" t_method_start)"
  [[ -n "$from" ]] || return 0
  to="$(harness_state_get "$STATE" t_pr_open)"
  [[ -n "$to" ]] || to="$(harness_utc_now)"
  if ! out="$(python3 "$SCRIPT_DIR/$READING_METRICS_SCRIPT" "$AGENT_TOOLING_DIR/analysis" "$TREE" \
              --from "$from" --to "$to" 2>>"$LOG_DIR/$BRANCH-reading.log")"; then
    harness_warn "reading metrics failed for $BRANCH — see $LOG_DIR/$BRANCH-reading.log"
    return 0
  fi
  for field in $READING_FIELDS; do
    harness_state_set "$STATE" "$field" "$(jq -c --arg f "$field" '.[$f]' <<<"$out")"
  done
}

# A `--from` resume runs record in a fresh process: fields set by stages of the
# killed process exist only in the state file, so a state value wins over this
# process's per-cell default (which is what the row silently got before this fix).
cell_arm_kind() {  # the row's arm_kind: agent_tooling or base for an arm, "" for none
  if [[ -n "$ARM" ]]; then printf '%s' "$EXPERIMENT_ARM_KIND"; fi
}

state_or() {  # $1 state key, $2 fallback
  local v; v="$(harness_state_get "$STATE" "$1")"
  if [[ -n "$v" ]]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}

state_json_or_null() {  # $1 state key: its JSON value, or null when the state lacks it
  jq -c --arg k "$1" '.[$k] // null' "$STATE" 2>/dev/null || printf 'null'
}

build_ledger_row() {  # the `record` stage: one appended results.jsonl row + scorecard render
  stage_begin record
  PR_URL="$(state_or pr_url "$PR_URL")"
  PR_OPENED_BY_HARNESS="$(state_or pr_opened_by_harness "$PR_OPENED_BY_HARNESS")"
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
    --arg model "$HARNESS_MODEL" --arg effort "$HARNESS_EFFORT" --arg arm "$ARM" \
    --arg agent_tooling "$(state_or agent_tooling "$ARM_SHA")" \
    --arg arm_kind "$(cell_arm_kind)" \
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
    --argjson read_files_before_edit "$(state_json_or_null read_files_before_edit)" \
    --argjson read_bytes_before_edit "$(state_json_or_null read_bytes_before_edit)" \
    --argjson readme_bytes_read "$(state_json_or_null readme_bytes_read)" \
    --argjson review_fixed "$(num "$REVIEW_FIXED")" \
    --argjson review_escalated "$(num "$REVIEW_ESCALATED")" \
    --argjson rework_ran "$REWORK_RAN" \
    --arg gate_counts_pr_open "$GATE_COUNTS_PR_OPEN" \
    --arg gate_counts_green "$GATE_COUNTS_GREEN" \
    --argjson accept_pass "$ACCEPT_PASS" \
    --argjson accept_lines "$ACCEPT_LINES" \
    --argjson method_failed "$METHOD_FAILED" \
    --argjson pr_opened_by_harness "$PR_OPENED_BY_HARNESS" \
    --argjson interventions "$(jq -c '.interventions // []' "$STATE")" \
    --arg harness_version "$(harness_version)" \
    '{experiment: $experiment, fixture: $fixture, method: $method, repeat: $repeat,
      arm: $arm, agent_tooling: $agent_tooling,
      arm_kind: $arm_kind,
      branch: $branch, slug: $slug, pr_url: $pr_url, base: $base,
      spec_commit: $spec_commit, model: $model,
      effort: (if $effort == "" then null else $effort end),
      t_setup_start: $t_setup_start, t_method_start: $t_method_start,
      t_pr_open: $t_pr_open, t_review_end: $t_review_end,
      t_rework_end: $t_rework_end, t_green: $t_green,
      cost_method_usd: $cost_method_usd, cost_method_reported_usd: $cost_method_reported_usd,
      cost_review_usd: $cost_review_usd,
      cost_rework_usd: $cost_rework_usd, cost_green_usd: $cost_green_usd,
      cost_lost_usd: $cost_lost_usd,
      read_files_before_edit: $read_files_before_edit, read_bytes_before_edit:
      $read_bytes_before_edit, readme_bytes_read: $readme_bytes_read,
      review_fixed: $review_fixed, review_escalated: $review_escalated,
      rework_ran: $rework_ran,
      gate_counts_pr_open: $gate_counts_pr_open, gate_counts_green: $gate_counts_green,
      accept_pass: $accept_pass, accept_lines: $accept_lines,
      method_failed: $method_failed, pr_opened_by_harness: $pr_opened_by_harness,
      interventions: $interventions,
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

# The program cell's stages (an orchestrator over an ordered list of features) reuse the
# functions above on each feature's branch.
# shellcheck source=program-stages.sh
source "$SCRIPT_DIR/program-stages.sh"

# ── Dry run ──────────────────────────────────────────────────────────────────
dry_run_cell() {
  say ""
  say "── $FIXTURE × $METHOD × ${ARM:-(no pin)} × $REPEAT ─────────────────────────────"
  say "  branch:        $BRANCH"
  say "  slug:          $SLUG"
  say "  repo:          $REPO_PATH"
  say "  worktree:      $TREE"
  say "  spec worktree: $SPEC_TREE  (detached at $SPEC_COMMIT, read-only; $(harness_spec_source_label "$FIXTURE_JSON"))"
  [[ -z "$ARM_SHA" ]] || say "  agentTooling:  pinned to upstream $ARM_SHA (arm $ARM)"
  [[ -z "$ARM_BASE" ]] || say "  base:          arm $ARM at $ARM_BASE (the fixture's own base $FIXTURE_BASE is not used)"
  say "  state file:    $STATE"
  say "  stages:        $(for s in $HARNESS_STAGES; do stage_wanted "$s" && printf '%s ' "$s"; done)"
  say "  review: $DO_REVIEW   rework: $DO_REWORK   accept: $DO_ACCEPT"
  say "  commands:"
  dry "git -C $REPO_PATH fetch -q $REMOTE"
  dry "git -C $REPO_PATH worktree add -b $BRANCH $TREE $BASE"
  if [[ -n "$ARM_SHA" ]]; then
    dry "git -C <checkout of $HARNESS_AGENT_TOOLING_URL> archive $ARM_SHA | tar -x -C $TREE/$AGENT_TOOLING_RELPATH   (after rm -rf of it)"
    dry "cd $TREE && ./$SYNC_PLANS_RELPATH"
    dry "git -C $TREE commit -m '$HARNESS_PIN_SUBJECT_PREFIX ${ARM_SHA:0:$PIN_SHORT_SHA_LEN}'"
  fi
  local cmd
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    dry "cd $TREE && $cmd"
  done < <(jq -r '.setup[]? // empty' "$FIXTURE_JSON")
  dry "cd $TREE && $GATE_COMMAND      # require: $GATE_GREEN"
  dry "git -C $SPEC_REPO worktree add --detach $SPEC_TREE $SPEC_COMMIT"
  dry "write $TREE/plans/features/$SLUG/README.md   (manifest skeleton, session_window.from = now)"
  dry "fill $HARNESS_METHODS_DIR/$METHOD/template.md -> $BRIEF_FILE"
  dry "$HARNESS_METHODS_DIR/$METHOD/run.sh $TREE $BRIEF_FILE $SLUG   (its claude call: --model $HARNESS_MODEL$(harness_effort_dry))"
  dry "${HARNESS_FORGE_BIN:-$DRIVER_FORGE} pr-find $BRANCH   (the driver's forge, FORGE_CHECKOUT=$TREE; none open, branch pushed with commits: pr-open $BRANCH $HARNESS_PR_BASE)"
  if [[ "$DO_REVIEW" == true ]]; then
    dry "$HARNESS_CLAUDE_BIN -p --output-format json$(harness_effort_dry) --model $HARNESS_MODEL --max-budget-usd $REVIEW_BUDGET_USD --permission-mode acceptEdits --allowedTools Bash <review preamble + $FIXTURE_DIR/review-brief.md>   (cwd $TREE)"
  fi
  if [[ "$DO_REWORK" == true ]]; then
    dry "$HARNESS_CLAUDE_BIN -p --output-format json$(harness_effort_dry) --model $HARNESS_MODEL --max-budget-usd $REWORK_BUDGET_USD --permission-mode acceptEdits --allowedTools Bash <rework preamble + $(harness_findings_path "$TREE" "$SLUG")>   (only if escalated >= 1)"
  fi
  if [[ "$DO_ACCEPT" == true ]]; then
    dry "python3 $FIXTURE_DIR/accept/accept.py $TREE"
    dry "cd $TREE && $GATE_COMMAND"
  fi
  dry "python3 $AGENT_TOOLING_DIR/analysis/capture_planning.py $SLUG --arm-root $TREE   (the driver's copy; also $SLUG-review, $SLUG-rework)"
  dry "python3 $AGENT_TOOLING_DIR/analysis/report.py $SLUG --arm-root $TREE             (read cost.total, then delete report.json/md)"
  dry "python3 $SCRIPT_DIR/$READING_METRICS_SCRIPT $AGENT_TOOLING_DIR/analysis $TREE --from <t_method_start> --to <t_pr_open>   (reading before the first edit)"
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
  harness_state_set_str "$STATE" arm "$ARM"
  harness_state_set_str "$STATE" arm_kind "$(cell_arm_kind)"
  harness_state_set_str "$STATE" base "$BASE"
  harness_state_set_str "$STATE" branch "$BRANCH"
  harness_state_set_str "$STATE" slug "$SLUG"

  stage_wanted setup  && { do_setup || return 1; }
  stage_wanted brief  && { do_brief || return 1; }
  if stage_wanted method; then
    if ! do_method; then
      harness_warn "method failed — recording the row and skipping the remaining model stages"
      stage_wanted capture && { do_capture; do_reading_metrics; }
      stage_wanted record && build_ledger_row
      return 1
    fi
  elif stage_wanted review && resume_no_pr; then
    # Past the method on a cell the old verdict failed for want of a PR: PR step only.
    if ! do_pr_resume; then
      harness_warn "resume found no PR and could not open one — recording the row"
      stage_wanted capture && { do_capture; do_reading_metrics; }
      stage_wanted record && build_ledger_row
      return 1
    fi
  else
    PR_URL="$(harness_state_get "$STATE" pr_url)"
  fi
  stage_wanted review && do_review
  stage_wanted rework && do_rework
  stage_wanted accept && do_accept
  stage_wanted capture && { do_capture; do_reading_metrics; }
  stage_wanted record && build_ledger_row
  return 0
}

# --only <fixture>[:<method>[:<arm>][:<n>]] — the arm is letters, the repeat digits, so
# the two trailing parts are told apart by shape.
cell_selected() {
  local fixture="$1" method="$2" repeat="$3" arm="$4" want_f want_m want_a want_n rest part
  [[ -n "$ONLY" ]] || return 0
  want_f="${ONLY%%:*}"; want_m=""; want_a=""; want_n=""
  if [[ "$ONLY" == *:* ]]; then
    rest="${ONLY#*:}"
    want_m="${rest%%:*}"
    rest="${rest#"$want_m"}"; rest="${rest#:}"
    while [[ -n "$rest" ]]; do
      part="${rest%%:*}"; rest="${rest#"$part"}"; rest="${rest#:}"
      if [[ "$part" =~ ^[0-9]+$ ]]; then want_n="$part"; else want_a="$part"; fi
    done
  fi
  [[ "$fixture" == "$want_f" ]] || return 1
  [[ -z "$want_m" || "$method" == "$want_m" ]] || return 1
  [[ -z "$want_a" || "$arm" == "$want_a" ]] || return 1
  [[ -z "$want_n" || "$repeat" == "$want_n" ]] || return 1
  return 0
}

say "########## experiment: $EXPERIMENT_NAME ##########"
say "prediction: $PREDICTION"
(( DRY_RUN )) && say "(dry run — nothing below is executed)"

failures=0
EXPERIMENT_ARM_KIND="$(harness_experiment_arm_kind "$EXPERIMENT_JSON")" || exit 1
if [[ "$EXPERIMENT_ARM_KIND" == "$HARNESS_ARM_KIND_BASE" && -n "$(jq -r '.programs[]?' "$EXPERIMENT_JSON")" ]]; then
  harness_die "$EXPERIMENT_JSON: $HARNESS_BASE_ARMS_NO_PROGRAMS_MSG"
fi
# One "<label> <sha>" per arm, or "- -" when the experiment names no arms.
ARMS="$(harness_experiment_arms "$EXPERIMENT_JSON")" || exit 1
for fixture in $(jq -r '.fixtures[]?' "$EXPERIMENT_JSON"); do
  for method in $(jq -r '.methods[]?' "$EXPERIMENT_JSON"); do
    # Read on its own descriptor: the stages below run programs that may read stdin.
    while read -r -u 3 arm_label arm_sha; do
      [[ -n "$arm_label" ]] || continue
      for repeat in $(seq 1 "$REPEATS"); do
        cell_selected "$fixture" "$method" "$repeat" "${arm_label#-}" || continue
        resolve_cell "$fixture" "$method" "$repeat" "$arm_label" "$arm_sha"
        if (( DRY_RUN )); then
          dry_run_cell
        else
          run_cell || failures=$(( failures + 1 ))
        fi
      done
    done 3<<<"$ARMS"
  done
done

# Program cells: program × arm × repeat. cell_selected reads the program as the fixture and
# the reserved method name as the method.
for program in $(jq -r '.programs[]?' "$EXPERIMENT_JSON"); do
  while read -r -u 3 arm_label arm_sha; do
    [[ -n "$arm_label" ]] || continue
    for repeat in $(seq 1 "$REPEATS"); do
      cell_selected "$program" "$HARNESS_PROGRAM_METHOD" "$repeat" "${arm_label#-}" || continue
      resolve_program_cell "$program" "$repeat" "$arm_label" "$arm_sha"
      if (( DRY_RUN )); then
        dry_run_program_cell
      else
        run_program_cell || failures=$(( failures + 1 ))
      fi
    done
  done 3<<<"$ARMS"
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
