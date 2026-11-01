#!/usr/bin/env bash
set -uo pipefail

# Scaffold an experiment: check its fixtures and methods exist, refuse branch names
# that already exist, and write experiment.json with the prediction recorded first.
#
#   harness/new-experiment.sh <name> [--fixtures <a,b> --methods <x,y>] [--programs <p,q>] \
#                             --prediction '<text>' \
#                             [--agent-tooling <label>=<ref>[,<label>=<ref>]...] \
#                             [--repeats N] [--noise-band 15] [--compare-to <path>] \
#                             [--no-review] [--no-rework] [--no-accept] \
#                             [--override <fixture-or-program>=<stem>]... [--consumer <path>]
#
# Run from the consuming repo root. Writes plans/experiments/<name>/{experiment.json,
# README.md}. Every fixture named must pass harness/check-fixture.sh; every method must be
# a directory under harness/methods/. For every cell it computes the branch the run would
# create (<stem><Method><Arm><n>) and refuses if that branch already exists, locally or on
# the fixture repo's remote — a replay of a feature that has already been built needs
# `--override <fixture>=<newStem>`, which becomes `branch_stem_override` in the JSON.
# The prediction is required: EXPERIMENTS.md's checklist-first rule, and run.sh will not
# start without one.
#
# `--agent-tooling` adds a third axis, the ARMS: each label names an agentTooling commit
# (any ref the upstream checkout resolves — a sha, a tag, `origin/main`), pinned here to
# its full id and written as `agent_tooling: {<label>: <sha>}`. The run then builds every
# fixture × method under each version, replacing the worktree's vendored `agentTooling/`
# with that commit's tree before anything reads it (harness/README.md → "Arms"). A label
# is bare lower-case letters (`before`, `after`); it is capitalised into the branch.
#
# `--programs` adds PROGRAM cells (harness/README.md → "Program cells"): each names a
# plans/experiments/programs/<name>/program.json, checked here (harness_program_check),
# and runs once per arm × repeat on a program branch plus one branch per feature; those
# are collision-checked like cells' (`--override <program>=<stem>` renames the program's).
# `--fixtures`/`--methods` may then be left out; a program name must differ from every
# fixture name. Every arm must carry the orchestration machinery (the version floor).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_REQUIRED_TOOLS="jq git python3"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DEFAULT_REPEATS=1
DEFAULT_NOISE_BAND_PCT=15

NAME=""; FIXTURES=""; METHODS=""; PROGRAMS=""; PREDICTION=""; COMPARE_TO=""; ARMS=""
REPEATS="$DEFAULT_REPEATS"; NOISE_BAND="$DEFAULT_NOISE_BAND_PCT"
DO_REVIEW=true; DO_REWORK=true; DO_ACCEPT=true
OVERRIDES=()
CONSUMER_ROOT="$DEFAULT_CONSUMER_ROOT"

usage() {
  sed -n '3,35p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while (( $# > 0 )); do
  case "$1" in
    --fixtures)   FIXTURES="${2:?--fixtures needs a comma list}"; shift 2 ;;
    --programs)   PROGRAMS="${2:?--programs needs a comma list}"; shift 2 ;;
    --methods)    METHODS="${2:?--methods needs a comma list}"; shift 2 ;;
    --agent-tooling) ARMS="${2:?--agent-tooling needs <label>=<ref>[,...]}"; shift 2 ;;
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
harness_require_own_driver
[[ "$NAME" =~ ^[a-z][A-Za-z0-9]*$ ]] || harness_die "experiment name must be bare camelCase: $NAME"
[[ -n "$FIXTURES" || -n "$PROGRAMS" ]] || harness_die "--fixtures or --programs is required"
[[ -n "$PREDICTION" ]] || harness_die "--prediction is required: write the checklist before the run (harness/EXPERIMENTS.md)"
[[ "$REPEATS" =~ ^[1-9][0-9]*$ ]] || harness_die "--repeats must be a positive integer"
[[ "$NOISE_BAND" =~ ^[0-9]+$ ]] || harness_die "--noise-band must be an integer percentage"

harness_require_tools

EXPERIMENT_DIR="$CONSUMER_ROOT/plans/experiments/$NAME"
[[ ! -e "$EXPERIMENT_DIR" ]] || harness_die "experiment already exists: $EXPERIMENT_DIR"
FIXTURES_DIR="$CONSUMER_ROOT/plans/experiments/fixtures"

FIXTURES_JSON="$(jq -cn --arg s "$FIXTURES" '$s | split(",") | map(select(length > 0))')"
METHODS_JSON="$(jq -cn --arg s "$METHODS" '$s | split(",") | map(select(length > 0))')"
PROGRAMS_JSON="$(jq -cn --arg s "$PROGRAMS" '$s | split(",") | map(select(length > 0))')"
PROGRAMS_DIR="$CONSUMER_ROOT/$HARNESS_PROGRAMS_RELDIR"
if [[ "$FIXTURES_JSON" != '[]' && "$METHODS_JSON" == '[]' ]]; then
  harness_die "--methods is required when --fixtures is given"
fi
[[ "$FIXTURES_JSON" != '[]' || "$PROGRAMS_JSON" != '[]' ]] || harness_die "--fixtures or --programs names nothing"

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

# ── Every program is well-formed and named apart from the fixtures ───────────
for program in $(jq -r '.[]' <<<"$PROGRAMS_JSON"); do
  [[ "$program" =~ $PROGRAM_STEM_RE ]] || harness_die "program name must be bare camelCase: $program"
  # Any fixture directory, not only this experiment's --fixtures: a program's own feature
  # fixtures key branch_stem_override too, so a program named like one would rename both.
  if [[ -d "$FIXTURES_DIR/$program" ]] \
     || jq -e --arg p "$program" 'index($p) != null' <<<"$FIXTURES_JSON" >/dev/null; then
    harness_die "program $program has the name of a fixture — a name must identify one thing (the cell's branch stem override keys on it)"
  fi
  [[ -f "$PROGRAMS_DIR/$program/$HARNESS_PROGRAM_FILE" ]] \
    || harness_die "no program at $PROGRAMS_DIR/$program/$HARNESS_PROGRAM_FILE"
  harness_program_check "$PROGRAMS_DIR/$program/$HARNESS_PROGRAM_FILE" "$FIXTURES_DIR" \
    || harness_die "program $program is not runnable — fix the errors above first"
done

# ── The arms: each ref pinned to a full agentTooling commit id ───────────────
ARMS_JSON='{}'
if [[ -n "$ARMS" ]]; then
  at="$(harness_resolve_repo "$HARNESS_AGENT_TOOLING_URL")" || exit 1
  git -C "$at" fetch -q origin 2>/dev/null || harness_warn "fetch of $at failed; resolving against what is local"
  for pair in $(printf '%s' "$ARMS" | tr ',' ' '); do
    [[ "$pair" == *=* ]] || harness_die "--agent-tooling takes <label>=<ref>: $pair"
    label="${pair%%=*}"; ref="${pair#*=}"
    [[ "$label" =~ $HARNESS_ARM_LABEL_RE ]] || harness_die "arm label must be bare lower-case letters: $label"
    sha="$(git -C "$at" rev-parse --verify --quiet "${ref}^{commit}")" \
      || harness_die "agentTooling ref does not resolve in $at: $ref"
    harness_log "arm $label: $ref -> $sha"
    ARMS_JSON="$(jq -c --arg l "$label" --arg s "$sha" '.[$l] = $s' <<<"$ARMS_JSON")"
  done
fi
# One "<label> <sha>" per arm, or "- -" for an experiment with no pin — what run.sh loops.
ARM_LINES="$(jq -r 'if length == 0 then "- -" else to_entries[] | "\(.key) \(.value)" end' <<<"$ARMS_JSON")"

# ── The version floor: a program cell needs the orchestration machinery ──────
# Checked per arm in the upstream checkout (the file's existence at the pinned commit),
# or, for an experiment that pins nothing, in the consumer's own vendored copy.
if [[ "$PROGRAMS_JSON" != '[]' ]]; then
  floor_failed=false
  if [[ "$ARMS_JSON" == '{}' ]]; then
    harness_check_program_floor "$CONSUMER_ROOT/$AGENT_TOOLING_RELPATH" "" || floor_failed=true
  else
    while read -r -u 3 arm_label arm_sha; do
      for floor_file in $HARNESS_PROGRAM_FLOOR_FILES; do
        if ! git -C "$at" cat-file -e "$arm_sha:$floor_file" 2>/dev/null; then
          printf 'ERROR: arm %s (%s) of agentTooling has no %s — a program cell needs a version that has the orchestration machinery; pin a newer commit\n' \
            "$arm_label" "${arm_sha:0:$PIN_SHORT_SHA_LEN}" "$floor_file" >&2
          floor_failed=true
        fi
      done
    done 3<<<"$ARM_LINES"
  fi
  [[ "$floor_failed" == false ]] || exit 1
fi

# ── The branches the run would create must not exist yet ────────────────────
collisions=()
CELLS_TABLE=""
for fixture in $(jq -r '.[]' <<<"$FIXTURES_JSON"); do
  fixture_json="$FIXTURES_DIR/$fixture/fixture.json"
  repo="$(harness_fixture_repo "$fixture_json")" || exit 1
  remote="$(jq -r '.repo.remote // "origin"' "$fixture_json")"
  stem="$(jq -r --arg f "$fixture" '.[$f] // empty' <<<"$OVERRIDES_JSON")"
  [[ -n "$stem" ]] || stem="$(harness_json "$fixture_json" .branch_stem)"
  git -C "$repo" remote get-url "$remote" >/dev/null 2>&1 && git -C "$repo" fetch -q "$remote" 2>/dev/null
  for method in $(jq -r '.[]' <<<"$METHODS_JSON"); do
    while read -r -u 3 arm_label arm_sha; do
      [[ -n "$arm_label" ]] || continue
      [[ "$arm_label" != "-" ]] || arm_label=""
      for (( n = 1; n <= REPEATS; n++ )); do
        branch="$(harness_branch_name "$stem" "$method" "$n" "$REPEATS" "$arm_label")"
        CELLS_TABLE+="| \`$fixture\` | \`$method\` | ${arm_label:-—} | $n | \`$branch\` |"$'\n'
        if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" \
           || git -C "$repo" show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
          collisions+=("$branch (fixture $fixture, in $repo)")
        fi
      done
    done 3<<<"$ARM_LINES"
  done
done

# A program's branches: the program branch <stem>Orchestrator<Arm><n> and, per feature,
# <fixtureStem><ProgramStem><Arm><n> (the program stem sits where a cell's method does).
# The repository is the program's own; --override <program>=<stem> / <fixture>=<stem>
# replace the respective stem, as for cells.
PROGRAMS_TABLE=""
for program in $(jq -r '.[]' <<<"$PROGRAMS_JSON"); do
  program_json="$PROGRAMS_DIR/$program/$HARNESS_PROGRAM_FILE"
  repo="$CONSUMER_ROOT"   # harness_program_check above refused a repo block naming another
  remote="$(jq -r '.repo.remote // "origin"' "$program_json")"
  program_stem="$(jq -r --arg p "$program" '.[$p] // empty' <<<"$OVERRIDES_JSON")"
  [[ -n "$program_stem" ]] || program_stem="$(harness_json "$program_json" .branch_stem)"
  git -C "$repo" remote get-url "$remote" >/dev/null 2>&1 && git -C "$repo" fetch -q "$remote" 2>/dev/null
  while read -r -u 3 arm_label arm_sha; do
    [[ -n "$arm_label" ]] || continue
    [[ "$arm_label" != "-" ]] || arm_label=""
    for (( n = 1; n <= REPEATS; n++ )); do
      branches=("program|$(harness_branch_name "$program_stem" "$HARNESS_PROGRAM_METHOD" "$n" "$REPEATS" "$arm_label")")
      for fixture in $(jq -r '.features[].fixture' "$program_json"); do
        fixture_stem="$(jq -r --arg f "$fixture" '.[$f] // empty' <<<"$OVERRIDES_JSON")"
        [[ -n "$fixture_stem" ]] || fixture_stem="$(harness_json "$FIXTURES_DIR/$fixture/fixture.json" .branch_stem)"
        branches+=("$fixture|$(harness_branch_name "$fixture_stem" "$program_stem" "$n" "$REPEATS" "$arm_label")")
      done
      for entry in "${branches[@]}"; do
        what="${entry%%|*}"; branch="${entry#*|}"
        if [[ "$what" == program ]]; then what="(program branch)"; else what="\`$what\`"; fi
        PROGRAMS_TABLE+="| \`$program\` | $what | ${arm_label:-—} | $n | \`$branch\` |"$'\n'
        if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" \
           || git -C "$repo" show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
          collisions+=("$branch (program $program, in $repo)")
        fi
      done
    done
  done 3<<<"$ARM_LINES"
done

if (( ${#collisions[@]} > 0 )); then
  printf 'ERROR: these branches already exist, so the run would append to an earlier arm'"'"'s record:\n' >&2
  printf '  %s\n' "${collisions[@]}" >&2
  printf 'Pass --override <fixture-or-program>=<newStem> to put this experiment on fresh branches.\n' >&2
  exit 1
fi

# ── Write it ─────────────────────────────────────────────────────────────────
mkdir -p "$EXPERIMENT_DIR"
jq -n \
  --arg name "$NAME" --argjson fixtures "$FIXTURES_JSON" --argjson methods "$METHODS_JSON" \
  --argjson repeats "$REPEATS" --argjson review "$DO_REVIEW" --argjson rework "$DO_REWORK" \
  --argjson accept "$DO_ACCEPT" --argjson band "$NOISE_BAND" --arg prediction "$PREDICTION" \
  --arg compare "$COMPARE_TO" --argjson overrides "$OVERRIDES_JSON" --argjson arms "$ARMS_JSON" \
  --argjson programs "$PROGRAMS_JSON" \
  '{name: $name, fixtures: $fixtures}
   + (if ($programs | length) > 0 then {programs: $programs} else {} end)
   + {methods: $methods, repeats: $repeats,
    stages: {review: $review, rework: $rework, accept: $accept},
    noise_band_pct: $band, prediction: $prediction, compare_to: $compare}
   + (if ($arms | length) > 0 then {agent_tooling: $arms} else {} end)
   + (if ($overrides | length) > 0 then {branch_stem_override: $overrides} else {} end)' \
  > "$EXPERIMENT_DIR/experiment.json"

ARMS_TEXT=""
[[ "$ARMS_JSON" == "{}" ]] || ARMS_TEXT=" × agentTooling $(jq -r 'to_entries | map("\(.key)=\(.value[0:7])") | join(", ")' <<<"$ARMS_JSON")"
STAGES_TEXT="stages review=$DO_REVIEW, rework=$DO_REWORK, accept=$DO_ACCEPT"
CELLS_BULLET=""; CELLS_BLOCK=""
if [[ "$FIXTURES_JSON" != '[]' ]]; then
  CELLS_BULLET="- **Cells:** $(jq -r '. | join(", ")' <<<"$FIXTURES_JSON") × $(jq -r '. | join(", ")' <<<"$METHODS_JSON")$ARMS_TEXT × $REPEATS; $STAGES_TEXT."
  CELLS_BLOCK="| Fixture | Method | Arm | Repeat | Branch |
|---|---|---|---|---|
$CELLS_TABLE"
fi
if [[ "$PROGRAMS_JSON" != '[]' ]]; then
  [[ -z "$CELLS_BULLET" ]] || CELLS_BULLET+=$'\n'
  CELLS_BULLET+="- **Program cells:** $(jq -r '. | join(", ")' <<<"$PROGRAMS_JSON")$ARMS_TEXT × $REPEATS; one orchestrator session runs each program's features in order, one implementer per feature; $STAGES_TEXT."
  [[ -z "$CELLS_BLOCK" ]] || CELLS_BLOCK+=$'\n'
  CELLS_BLOCK+="| Program | Branch of | Arm | Repeat | Branch |
|---|---|---|---|---|
$PROGRAMS_TABLE"
fi

cat > "$EXPERIMENT_DIR/README.md" <<README
# $NAME

@@TODO@@ (harness/new-experiment.sh stub): one paragraph on the question this experiment
answers — replace before the run, and nothing else here needs to change afterwards
except the results section \`harness/publish.sh\` asks you to add.

$CELLS_BULLET
- **Prediction, recorded before the run:** *$PREDICTION*
- **Noise band:** ±$NOISE_BAND% — a cost difference inside it reads as a tie.
$( [[ -n "$COMPARE_TO" ]] && printf -- '- **Compared against:** `%s`\n' "$COMPARE_TO" )
$( [[ "$ARMS_JSON" != "{}" ]] && printf -- '- **Arms:** each cell runs under every agentTooling version named in `experiment.json`'"'"'s `agent_tooling`; the setup stage pins the worktree'"'"'s vendored copy to it in a commit titled `EXPERIMENT ARM (revert before merge): …`, which is never merged.\n' )

$CELLS_BLOCK
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
printf '%s%s' "$CELLS_TABLE" "$PROGRAMS_TABLE" | sed 's/^/  /'
harness_log "next: replace the @@TODO@@ paragraph in README.md, then: harness/run.sh plans/experiments/$NAME --dry-run"
