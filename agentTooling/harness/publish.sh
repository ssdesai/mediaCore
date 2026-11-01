#!/usr/bin/env bash
set -uo pipefail

# Publish an experiment's results: re-render the scorecard, commit the experiment
# directory, push, and open the PR.
#
#   harness/publish.sh <experiment-dir> [--branch <name>] [--consumer <path>]
#
# Run from the consuming repo root after run.sh has appended to results.jsonl. Commits
# only the experiment directory (experiment.json, README.md, results.jsonl, SCORECARD.md,
# state/ — logs/ is gitignored by the consumer), as `<experiment>: run <n> results` where
# n is the ledger's row count. If the consumer is on its default branch it first creates
# `<experiment>Results` (or --branch) and moves the uncommitted results onto it; on any
# other branch it commits there. Pushes with `-u`; opens the PR through the forge seam
# (the consumer's vendored `agentTooling/forge.sh`, or HARNESS_FORGE_BIN) when that is
# there and no PR is open for the branch yet, otherwise prints the branch to open one
# from. The PR body is SCORECARD.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_REQUIRED_TOOLS="jq git python3"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DEFAULT_BRANCHES="main master"          # a checkout on one of these gets a results branch
RESULTS_BRANCH_SUFFIX="Results"

EXPERIMENT_ARG=""; BRANCH=""
CONSUMER_ROOT="$DEFAULT_CONSUMER_ROOT"

usage() {
  sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while (( $# > 0 )); do
  case "$1" in
    --branch)   BRANCH="${2:?--branch needs a name}"; shift 2 ;;
    --consumer) CONSUMER_ROOT="$(cd "${2:?--consumer needs a path}" && pwd)"; shift 2 ;;
    -h|--help)  usage 0 ;;
    -*)         harness_die "unknown option: $1" ;;
    *)          [[ -z "$EXPERIMENT_ARG" ]] || harness_die "unexpected argument: $1"
                EXPERIMENT_ARG="$1"; shift ;;
  esac
done
[[ -n "$EXPERIMENT_ARG" ]] || usage 1
harness_require_own_driver

harness_require_tools

if [[ "$EXPERIMENT_ARG" == /* ]]; then EXPERIMENT_DIR="$EXPERIMENT_ARG"; else EXPERIMENT_DIR="$CONSUMER_ROOT/$EXPERIMENT_ARG"; fi
[[ -d "$EXPERIMENT_DIR" ]] || harness_die "no experiment directory at $EXPERIMENT_DIR"
EXPERIMENT_DIR="$(cd "$EXPERIMENT_DIR" && pwd)"
EXPERIMENT_JSON="$EXPERIMENT_DIR/experiment.json"
RESULTS_FILE="$EXPERIMENT_DIR/results.jsonl"
[[ -f "$EXPERIMENT_JSON" ]] || harness_die "no experiment.json in $EXPERIMENT_DIR"
[[ -s "$RESULTS_FILE" ]] || harness_die "no results.jsonl in $EXPERIMENT_DIR — nothing has run"
case "$EXPERIMENT_DIR/" in "$CONSUMER_ROOT"/*) ;; *) harness_die "$EXPERIMENT_DIR is not inside the consumer $CONSUMER_ROOT" ;; esac
REL_DIR="${EXPERIMENT_DIR#"$CONSUMER_ROOT"/}"

NAME="$(harness_json "$EXPERIMENT_JSON" .name)"
ROWS="$(grep -c . "$RESULTS_FILE")"
[[ -z "$BRANCH" ]] && BRANCH="${NAME}${RESULTS_BRANCH_SUFFIX}"
[[ "$BRANCH" =~ ^[a-z][A-Za-z0-9]*$ ]] || harness_die "branch must be bare camelCase (no user/ prefix): $BRANCH"

git -C "$CONSUMER_ROOT" rev-parse --git-dir >/dev/null 2>&1 || harness_die "not a git repository: $CONSUMER_ROOT"

# ── Scorecard, from the ledger as it stands ──────────────────────────────────
python3 "$SCRIPT_DIR/scorecard.py" "$EXPERIMENT_DIR" >/dev/null || harness_die "scorecard.py failed"
harness_log "rendered $REL_DIR/SCORECARD.md from $ROWS row(s)"

# ── Which branch ─────────────────────────────────────────────────────────────
CURRENT="$(git -C "$CONSUMER_ROOT" branch --show-current)"
case " $DEFAULT_BRANCHES " in
  *" $CURRENT "*)
    if git -C "$CONSUMER_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      harness_die "branch $BRANCH already exists — pass --branch <other>, or check it out first and run again"
    fi
    git -C "$CONSUMER_ROOT" checkout -q -b "$BRANCH" || harness_die "could not create branch $BRANCH"
    harness_log "created branch $BRANCH off $CURRENT"
    ;;
  "")
    harness_die "detached HEAD in $CONSUMER_ROOT — check out a branch first" ;;
  *)
    BRANCH="$CURRENT"
    harness_log "committing on the current branch $BRANCH" ;;
esac

# ── Commit only the experiment directory ─────────────────────────────────────
other="$(git -C "$CONSUMER_ROOT" status --porcelain -- . ":!$REL_DIR" | head -5)"
[[ -z "$other" ]] || harness_warn "uncommitted changes outside $REL_DIR are left alone:"$'\n'"$other"
git -C "$CONSUMER_ROOT" add -- "$REL_DIR"
if git -C "$CONSUMER_ROOT" diff --cached --quiet -- "$REL_DIR"; then
  harness_log "nothing new under $REL_DIR to commit"
else
  git -C "$CONSUMER_ROOT" commit -q -m "$NAME: run $ROWS results" || harness_die "commit failed"
  harness_log "committed: $NAME: run $ROWS results"
fi
if git -C "$CONSUMER_ROOT" ls-files --error-unmatch -- "$REL_DIR/logs" >/dev/null 2>&1; then
  harness_warn "$REL_DIR/logs is tracked — add plans/experiments/*/logs/ to the consumer's .gitignore"
fi

# ── Push and PR ──────────────────────────────────────────────────────────────
harness_push "$CONSUMER_ROOT" "$BRANCH"

# Through the forge seam — the consumer's own vendored forge.sh (`gh api` REST, which
# works on a laptop and in a cloud container alike), or HARNESS_FORGE_BIN.
existing="$(harness_pr_url "$CONSUMER_ROOT" "$BRANCH")"
if [[ -n "$existing" ]]; then
  harness_log "PR already open for $BRANCH: $existing"
elif [[ -n "$(harness_forge_for "$CONSUMER_ROOT")" ]] && harness_has_remote "$CONSUMER_ROOT"; then
  url="$(harness_pr_open "$CONSUMER_ROOT" "$BRANCH" "$NAME: results, run $ROWS" "$EXPERIMENT_DIR/SCORECARD.md")"
  if [[ -n "$url" ]]; then
    harness_log "PR: $url"
  else
    harness_warn "the forge did not open the PR — open it from branch $BRANCH by hand, body $REL_DIR/SCORECARD.md"
  fi
else
  harness_log "no forge adapter or no remote — open the PR from branch $BRANCH by hand, body $REL_DIR/SCORECARD.md"
fi
harness_log "next: add a results section to $REL_DIR/README.md (what the row says against the prediction), then commit that on $BRANCH"
