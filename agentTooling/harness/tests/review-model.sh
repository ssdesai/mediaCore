#!/usr/bin/env bash
set -uo pipefail

# HARNESS_REVIEW_MODEL, offline: how lib.sh resolves it (unset and empty fall back to
# HARNESS_MODEL, a value is kept) and what `run.sh --dry-run` prints for every stage under
# each. The call-level and row assertions (the review call carries the review model, no
# build call does, the row records both) are in smoke.sh, which drives the real stages.
#
#   harness/tests/review-model.sh
#
# No network, no money, no model call: a `mktemp -d` directory, removed on exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_TOOLING_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
RUN="$HARNESS_DIR/run.sh"
LIB="$HARNESS_DIR/lib.sh"

# The consumer
FIXTURE_NAME="rmfix"
BRANCH_STEM="rmStem"
EXPERIMENT_NAME="reviewModel"
GATE_GREEN="gate-is-green"
GIT_USER_EMAIL="review-model@example.invalid"
GIT_USER_NAME="Harness Review Model"

# Models: the build model and the review model are distinct names so a mix-up shows
BUILD_MODEL="buildmodel"
REVIEW_MODEL="reviewmodel"
# lib.sh's own default for HARNESS_MODEL, read from it rather than mirrored here
DEFAULT_MODEL="$(env -u HARNESS_MODEL bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "$HARNESS_MODEL"' _ "$LIB")"

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/review-model.XXXXXX")"
[[ -n "$WORK" && -d "$WORK" ]] || { echo "review-model: cannot create a work directory" >&2; exit 1; }
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

BIN="$WORK/bin"
mkdir -p "$BIN"
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/claude"
printf '#!/usr/bin/env bash\nexit 2\n' > "$BIN/forge.sh"
chmod +x "$BIN/claude" "$BIN/forge.sh"
export HARNESS_CLAUDE_BIN="$BIN/claude"
export HARNESS_FORGE_BIN="$BIN/forge.sh"
export HARNESS_AGENT_TOOLING_URL="$AGENT_TOOLING_DIR"
export HARNESS_TEST_EXTERNAL_DRIVER=1

# resolved <env assignments…> — what lib.sh leaves in HARNESS_REVIEW_MODEL under them
resolved() {
  env -u HARNESS_MODEL -u HARNESS_REVIEW_MODEL "$@" bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "$HARNESS_REVIEW_MODEL"' _ "$LIB"
}

echo "=== review-model: resolution ==="
check "lib.sh sources and gives HARNESS_MODEL a default" test -n "$DEFAULT_MODEL"
check "unset: the review model is the default build model" \
  test "$(resolved)" = "$DEFAULT_MODEL"
check "unset: the review model follows HARNESS_MODEL" \
  test "$(resolved HARNESS_MODEL=$BUILD_MODEL)" = "$BUILD_MODEL"
check "empty: falls back to HARNESS_MODEL" \
  test "$(resolved HARNESS_MODEL=$BUILD_MODEL HARNESS_REVIEW_MODEL=)" = "$BUILD_MODEL"
check "set: kept, and HARNESS_MODEL does not change it" \
  test "$(resolved HARNESS_MODEL=$BUILD_MODEL HARNESS_REVIEW_MODEL=$REVIEW_MODEL)" = "$REVIEW_MODEL"

# The consumer: method direct, every stage on, so the dry run prints all the model lines
REPO="$WORK/repo"
mkdir -p "$REPO/plans"
ln -s "$AGENT_TOOLING_DIR" "$REPO/agentTooling"
printf '# Spec\n\n## 1. Nothing\n\nNothing.\n' > "$REPO/SPEC.md"
printf 'plans/experiments/*/logs/\n' > "$REPO/.gitignore"
FIXTURE_DIR="$REPO/plans/experiments/fixtures/$FIXTURE_NAME"
mkdir -p "$FIXTURE_DIR"
printf 'facts\n' > "$FIXTURE_DIR/facts.md"
printf 'brief\n' > "$FIXTURE_DIR/review-brief.md"
EXP="$REPO/plans/experiments/$EXPERIMENT_NAME"
mkdir -p "$EXP"
printf '# %s\n' "$EXPERIMENT_NAME" > "$EXP/README.md"
git -C "$REPO" init -q
git -C "$REPO" config user.email "$GIT_USER_EMAIL"
git -C "$REPO" config user.name "$GIT_USER_NAME"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "base"
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"
cat > "$FIXTURE_DIR/fixture.json" <<FIXTURE
{
  "name": "$FIXTURE_NAME",
  "base": "$BASE_SHA",
  "spec": {"commit": "$BASE_SHA", "path": "SPEC.md", "sections": ["1"]},
  "setup": [],
  "gate": {"command": "echo $GATE_GREEN", "green": "$GATE_GREEN", "minutes": 0},
  "branch_stem": "$BRANCH_STEM",
  "diff_lines": 1
}
FIXTURE
cat > "$EXP/experiment.json" <<EXPERIMENT
{
  "name": "$EXPERIMENT_NAME",
  "fixtures": ["$FIXTURE_NAME"],
  "methods": ["direct"],
  "repeats": 1,
  "noise_band_pct": 15,
  "prediction": "the dry run names the model of every stage",
  "compare_to": ""
}
EXPERIMENT
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "fixture and experiment"
git init -q --bare "$WORK/remote.git"
git -C "$REPO" remote add origin "$WORK/remote.git"
git -C "$REPO" push -q -u origin HEAD 2>/dev/null

# dry <out> <env assignments…> — the dry run's output, for the assertions below
dry() {
  local out="$1"; shift
  env -u HARNESS_MODEL -u HARNESS_REVIEW_MODEL "$@" "$RUN" "$EXP" --consumer "$REPO" --dry-run > "$out" 2>&1
}

echo "=== review-model: dry run, unset ==="
UNSET_OUT="$WORK/dry-unset.txt"
dry "$UNSET_OUT" HARNESS_MODEL=$BUILD_MODEL
check "exits 0" test -s "$UNSET_OUT"
check "method line names the build model" bash -c "grep -E 'methods/.*/run\.sh' '$UNSET_OUT' | grep -q -- '--model $BUILD_MODEL'"
check "review line names the build model (it falls back)" bash -c "grep 'review preamble' '$UNSET_OUT' | grep -q -- '--model $BUILD_MODEL '"
check "rework line names the build model" bash -c "grep 'rework preamble' '$UNSET_OUT' | grep -q -- '--model $BUILD_MODEL '"
check "no mention of the review model's own name" bash -c "! grep -q '$REVIEW_MODEL' '$UNSET_OUT'"

echo "=== review-model: dry run, set ==="
SET_OUT="$WORK/dry-set.txt"
dry "$SET_OUT" HARNESS_MODEL=$BUILD_MODEL HARNESS_REVIEW_MODEL=$REVIEW_MODEL
check "method line keeps the build model" bash -c "grep -E 'methods/.*/run\.sh' '$SET_OUT' | grep -q -- '--model $BUILD_MODEL'"
check "method line does not carry the review model" bash -c "! grep -E 'methods/.*/run\.sh' '$SET_OUT' | grep -q '$REVIEW_MODEL'"
check "review line names the review model" bash -c "grep 'review preamble' '$SET_OUT' | grep -q -- '--model $REVIEW_MODEL '"
check "review line does not carry the build model" bash -c "! grep 'review preamble' '$SET_OUT' | grep -q '$BUILD_MODEL'"
check "rework line stays on the build model" bash -c "grep 'rework preamble' '$SET_OUT' | grep -q -- '--model $BUILD_MODEL '"
check "rework line does not carry the review model" bash -c "! grep 'rework preamble' '$SET_OUT' | grep -q '$REVIEW_MODEL'"

echo ""
if (( failures > 0 )); then
  echo "review-model: $failures check(s) FAILED"
  exit 1
fi
echo "review-model: all checks passed"
