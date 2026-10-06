#!/usr/bin/env bash
set -uo pipefail

# Scaffold an experiment: check its fixtures and methods exist, refuse branch names
# that already exist, and write experiment.json with the prediction recorded first.
#
#   harness/new-experiment.sh <name> --fixtures <a,b> --methods <x,y> --prediction '<text>' \
#                             [--repeats N] [--noise-band 15] [--compare-to <path>] \
#                             [--no-review] [--no-rework] [--no-accept] \
#                             [--override <fixture>=<stem>]... [--consumer <path>]
#
# Run from the consuming repo root. Writes plans/experiments/<name>/{experiment.json,
# README.md}. Every fixture named must pass harness/check-fixture.sh; every method must be
# a directory under harness/methods/. For every cell it computes the branch the run would
# create (<stem><Method><n>) and refuses if that branch already exists, locally or on the
# fixture repo's remote — a replay of a feature that has already been built needs
# `--override <fixture>=<newStem>`, which becomes `branch_stem_override` in the JSON.
# The prediction is required: EXPERIMENTS.md's checklist-first rule, and run.sh will not
# start without one.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_REQUIRED_TOOLS="jq git python3"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DEFAULT_REPEATS=1
DEFAULT_NOISE_BAND_PCT=15

NAME=""; FIXTURES=""; METHODS=""; PREDICTION=""; COMPARE_TO=""
REPEATS="$DEFAULT_REPEATS"; NOISE_BAND="$DEFAULT_NOISE_BAND_PCT"
DO_REVIEW=true; DO_REWORK=true; DO_ACCEPT=true
OVERRIDES=()
CONSUMER_ROOT="$DEFAULT_CONSUMER_ROOT"

usage() {
  sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while (( $# > 0 )); do
  case "$1" in
    --fixtures)   FIXTURES="${2:?--fixtures needs a comma list}"; shift 2 ;;
    --methods)    METHODS="${2:?--methods needs a comma list}"; shift 2 ;;
    --prediction) PREDICTION="${2:?--prediction needs text}"; shift 2 ;;
    --repeats)    REPEATS="${2:?--repeats needs a number}"; shift 2 ;;
    --noise-band) NOISE_BAND="${2:?--noise-band needs a percentage}"; shift 2 ;;
    --compare-to) COMPARE_TO="${2:?--compare-to needs a path}"; shift 2 ;;
    --override)   OVERRIDES+=("${2:?--override needs <fixture>=<stem>}"); shift 2 ;;
    --no-review)  DO_REVIEW=false; shift ;;
    --no-rework)  DO_REWORK=false; shift ;;
    --no-accept)  DO_ACCEPT=false; shift ;;
    --consumer)   CONSUMER_ROOT="$(cd "${2:?--consumer needs a path}" && pwd)"; shift 2 ;;
    -h|--help)    usage 0 ;;
    -*)           harness_die "unknown option: $1" ;;
    *)            [[ -z "$NAME" ]] || harness_die "unexpected argument: $1"
                  NAME="$1"; shift ;;
  esac
done

[[ -n "$NAME" ]] || usage 1
[[ "$NAME" =~ ^[a-z][A-Za-z0-9]*$ ]] || harness_die "experiment name must be bare camelCase: $NAME"
[[ -n "$FIXTURES" ]] || harness_die "--fixtures is required"
[[ -n "$METHODS" ]] || harness_die "--methods is required"
[[ -n "$PREDICTION" ]] || harness_die "--prediction is required: write the checklist before the run (harness/EXPERIMENTS.md)"
[[ "$REPEATS" =~ ^[1-9][0-9]*$ ]] || harness_die "--repeats must be a positive integer"
[[ "$NOISE_BAND" =~ ^[0-9]+$ ]] || harness_die "--noise-band must be an integer percentage"

harness_require_tools

EXPERIMENT_DIR="$CONSUMER_ROOT/plans/experiments/$NAME"
[[ ! -e "$EXPERIMENT_DIR" ]] || harness_die "experiment already exists: $EXPERIMENT_DIR"
FIXTURES_DIR="$CONSUMER_ROOT/plans/experiments/fixtures"

FIXTURES_JSON="$(jq -cn --arg s "$FIXTURES" '$s | split(",") | map(select(length > 0))')"
METHODS_JSON="$(jq -cn --arg s "$METHODS" '$s | split(",") | map(select(length > 0))')"

# ── Overrides: <fixture>=<stem> ──────────────────────────────────────────────
OVERRIDES_JSON='{}'
for pair in "${OVERRIDES[@]-}"; do
  [[ -n "$pair" ]] || continue
  [[ "$pair" == *=* ]] || harness_die "--override must be <fixture>=<stem>: $pair"
  fx="${pair%%=*}"; stem="${pair#*=}"
  [[ "$stem" =~ ^[a-z][A-Za-z0-9]*$ ]] || harness_die "override stem must be bare camelCase: $stem"
  OVERRIDES_JSON="$(jq -c --arg f "$fx" --arg s "$stem" '.[$f] = $s' <<<"$OVERRIDES_JSON")"
done

# ── Every fixture passes check-fixture; every method is a directory ──────────
for fixture in $(jq -r '.[]' <<<"$FIXTURES_JSON"); do
  [[ -d "$FIXTURES_DIR/$fixture" ]] || harness_die "no fixture at $FIXTURES_DIR/$fixture"
  "$SCRIPT_DIR/check-fixture.sh" "$fixture" --consumer "$CONSUMER_ROOT" \
    || harness_die "fixture $fixture is not runnable — fix the checks above first"
done
for method in $(jq -r '.[]' <<<"$METHODS_JSON"); do
  [[ -f "$HARNESS_METHODS_DIR/$method/run.sh" && -f "$HARNESS_METHODS_DIR/$method/template.md" ]] \
    || harness_die "no method at $HARNESS_METHODS_DIR/$method (needs run.sh and template.md — see methods/README.md)"
done

# ── The branches the run would create must not exist yet ────────────────────
collisions=()
CELLS_TABLE=""
for fixture in $(jq -r '.[]' <<<"$FIXTURES_JSON"); do
  fixture_json="$FIXTURES_DIR/$fixture/fixture.json"
  repo="$(harness_json "$fixture_json" .repo.path)"
  remote="$(jq -r '.repo.remote // "origin"' "$fixture_json")"
  stem="$(jq -r --arg f "$fixture" '.[$f] // empty' <<<"$OVERRIDES_JSON")"
  [[ -n "$stem" ]] || stem="$(harness_json "$fixture_json" .branch_stem)"
  git -C "$repo" remote get-url "$remote" >/dev/null 2>&1 && git -C "$repo" fetch -q "$remote" 2>/dev/null
  for method in $(jq -r '.[]' <<<"$METHODS_JSON"); do
    for (( n = 1; n <= REPEATS; n++ )); do
      branch="$(harness_branch_name "$stem" "$method" "$n" "$REPEATS")"
      CELLS_TABLE+="| \`$fixture\` | \`$method\` | $n | \`$branch\` |"$'\n'
      if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" \
         || git -C "$repo" show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
        collisions+=("$branch (fixture $fixture, in $repo)")
      fi
    done
  done
done
if (( ${#collisions[@]} > 0 )); then
  printf 'ERROR: these branches already exist, so the run would append to an earlier arm'"'"'s record:\n' >&2
  printf '  %s\n' "${collisions[@]}" >&2
  printf 'Pass --override <fixture>=<newStem> to put this experiment on fresh branches.\n' >&2
  exit 1
fi

# ── Write it ─────────────────────────────────────────────────────────────────
mkdir -p "$EXPERIMENT_DIR"
jq -n \
  --arg name "$NAME" --argjson fixtures "$FIXTURES_JSON" --argjson methods "$METHODS_JSON" \
  --argjson repeats "$REPEATS" --argjson review "$DO_REVIEW" --argjson rework "$DO_REWORK" \
  --argjson accept "$DO_ACCEPT" --argjson band "$NOISE_BAND" --arg prediction "$PREDICTION" \
  --arg compare "$COMPARE_TO" --argjson overrides "$OVERRIDES_JSON" \
  '{name: $name, fixtures: $fixtures, methods: $methods, repeats: $repeats,
    stages: {review: $review, rework: $rework, accept: $accept},
    noise_band_pct: $band, prediction: $prediction, compare_to: $compare}
   + (if ($overrides | length) > 0 then {branch_stem_override: $overrides} else {} end)' \
  > "$EXPERIMENT_DIR/experiment.json"

cat > "$EXPERIMENT_DIR/README.md" <<README
# $NAME

@@TODO@@ (harness/new-experiment.sh stub): one paragraph on the question this experiment
answers — replace before the run, and nothing else here needs to change afterwards
except the results section \`harness/publish.sh\` asks you to add.

- **Cells:** $(jq -r '. | join(", ")' <<<"$FIXTURES_JSON") × $(jq -r '. | join(", ")' <<<"$METHODS_JSON") × $REPEATS; stages review=$DO_REVIEW, rework=$DO_REWORK, accept=$DO_ACCEPT.
- **Prediction, recorded before the run:** *$PREDICTION*
- **Noise band:** ±$NOISE_BAND% — a cost difference inside it reads as a tie.
$( [[ -n "$COMPARE_TO" ]] && printf -- '- **Compared against:** `%s`\n' "$COMPARE_TO" )

| Fixture | Method | Repeat | Branch |
|---|---|---|---|
$CELLS_TABLE
| File | What it is |
|---|---|
| \`experiment.json\` | Which cells to run, which stages, the noise band, the prediction. |
| \`results.jsonl\` | Appended by the harness, one row per run. |
| \`SCORECARD.md\` | Rendered from \`results.jsonl\` by \`agentTooling/harness/scorecard.py\`. |
| \`state/\`, \`logs/\` | Per-run state files (what \`--from\` resumes off) and the prompts, results and gate logs kept outside the arm's worktree. \`logs/\` is gitignored. |

## Running it

\`\`\`bash
./agentTooling/harness/run.sh plans/experiments/$NAME --dry-run
./agentTooling/harness/run.sh plans/experiments/$NAME
./agentTooling/harness/publish.sh plans/experiments/$NAME   # commit the results, push, open the PR
\`\`\`
README

harness_log "wrote $EXPERIMENT_DIR"
harness_log "cells:"
printf '%s' "$CELLS_TABLE" | sed 's/^/  /'
harness_log "next: replace the @@TODO@@ paragraph in README.md, then: harness/run.sh plans/experiments/$NAME --dry-run"
