#!/usr/bin/env bash
set -uo pipefail

# HARNESS_REVIEW_EFFORT, offline: how lib.sh resolves it (unset and empty follow
# HARNESS_EFFORT, a value is kept, a bad value is refused) and what `run.sh --dry-run`
# prints for every stage under each. The call-level and row assertions (the review call
# carries the review effort, no build or rework call does, the row records both) are in
# smoke.sh, which drives the real stages.
#
#   harness/tests/review-effort.sh
#
# No network, no money, no model call: a `mktemp -d` directory, removed on exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_TOOLING_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
RUN="$HARNESS_DIR/run.sh"
LIB="$HARNESS_DIR/lib.sh"

# The consumer
FIXTURE_NAME="refix"
BRANCH_STEM="reStem"
EXPERIMENT_NAME="reviewEffort"
GATE_GREEN="gate-is-green"
GIT_USER_EMAIL="review-effort@example.invalid"
GIT_USER_NAME="Harness Review Effort"

# Efforts: distinct levels so a mix-up shows
BUILD_EFFORT="low"
REVIEW_EFFORT="max"
BAD_EFFORT="huge"

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/review-effort.XXXXXX")"
[[ -n "$WORK" && -d "$WORK" ]] || { echo "review-effort: cannot create a work directory" >&2; exit 1; }
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

# resolved <env assignments…> — what lib.sh leaves in HARNESS_REVIEW_EFFORT under them
resolved() {
  env -u HARNESS_EFFORT -u HARNESS_REVIEW_EFFORT "$@" bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "$HARNESS_REVIEW_EFFORT"' _ "$LIB"
}
# refused <env assignments…> — sourcing lib.sh fails, naming the variable
refused() {
  local out rc
  out="$(env -u HARNESS_EFFORT -u HARNESS_REVIEW_EFFORT "$@" bash -c 'source "$1"' _ "$LIB" 2>&1)"
  rc=$?
  (( rc != 0 )) && [[ "$out" == *"HARNESS_REVIEW_EFFORT="*"not an effort level"* ]]
}

echo "=== review-effort: resolution ==="
check "unset, HARNESS_EFFORT unset: empty (the CLI default)" test -z "$(resolved)"
check "unset: follows HARNESS_EFFORT" test "$(resolved HARNESS_EFFORT=$BUILD_EFFORT)" = "$BUILD_EFFORT"
check "empty: follows HARNESS_EFFORT" test "$(resolved HARNESS_EFFORT=$BUILD_EFFORT HARNESS_REVIEW_EFFORT=)" = "$BUILD_EFFORT"
check "set: kept, and HARNESS_EFFORT does not change it" \
  test "$(resolved HARNESS_EFFORT=$BUILD_EFFORT HARNESS_REVIEW_EFFORT=$REVIEW_EFFORT)" = "$REVIEW_EFFORT"
check "set with HARNESS_EFFORT unset: kept" test "$(resolved HARNESS_REVIEW_EFFORT=$REVIEW_EFFORT)" = "$REVIEW_EFFORT"
check "an invalid value is refused, naming the variable" refused HARNESS_REVIEW_EFFORT=$BAD_EFFORT
check "a valid HARNESS_EFFORT with an invalid review effort is refused" refused HARNESS_EFFORT=$BUILD_EFFORT HARNESS_REVIEW_EFFORT=$BAD_EFFORT

# The seam: harness_claude with a stub claude that logs its argv. A caller that names its own
# --effort (the review stage) replaces the run-wide one, so no call carries the flag twice.
SEAM_ARGV="$WORK/seam-argv.log"
SEAM_PROMPT="$WORK/seam-prompt.md"
SEAM_OUT="$WORK/seam-out.json"
printf 'prompt\n' > "$SEAM_PROMPT"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$SEAM_ARGV"\nprintf "{}"\n' > "$BIN/seamclaude"
chmod +x "$BIN/seamclaude"
# seam_call <env assignments…> -- <extra claude flags…> — one harness_claude call, argv logged
seam_call() {
  local envs=()
  while [[ "${1:-}" != "--" ]]; do envs+=("$1"); shift; done
  shift
  : > "$SEAM_ARGV"
  env -u HARNESS_EFFORT -u HARNESS_REVIEW_EFFORT SEAM_ARGV="$SEAM_ARGV" HARNESS_CLAUDE_BIN="$BIN/seamclaude" ${envs[@]+"${envs[@]}"} \
    bash -c 'source "$1" >/dev/null 2>&1; shift; harness_claude "$@"' _ "$LIB" "$SEAM_OUT" "$SEAM_PROMPT" "$WORK" "$@" >/dev/null 2>&1
}
echo "=== review-effort: the claude seam ==="
seam_call HARNESS_EFFORT=$BUILD_EFFORT -- --effort $REVIEW_EFFORT --model m
check "a caller's --effort under HARNESS_EFFORT: exactly one --effort in the argv" \
  test "$(grep -o -- '--effort' "$SEAM_ARGV" | wc -l)" -eq 1
check "... and it is the caller's" bash -c "grep -q -- '--effort $REVIEW_EFFORT' '$SEAM_ARGV' && ! grep -q -- '--effort $BUILD_EFFORT' '$SEAM_ARGV'"
seam_call HARNESS_EFFORT=$BUILD_EFFORT -- --model m
check "no --effort from the caller: the run-wide HARNESS_EFFORT is added, once" \
  bash -c "grep -q -- '--effort $BUILD_EFFORT' '$SEAM_ARGV' && [[ \$(grep -o -- '--effort' '$SEAM_ARGV' | wc -l) -eq 1 ]]"
seam_call -- --model m
check "neither set and no caller --effort: no --effort at all" bash -c "! grep -q -- '--effort' '$SEAM_ARGV'"

# The consumer: method direct, every stage on, so the dry run prints all the stage lines
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
  "prediction": "the dry run names the effort of every stage",
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
  env -u HARNESS_EFFORT -u HARNESS_REVIEW_EFFORT "$@" "$RUN" "$EXP" --consumer "$REPO" --dry-run > "$out" 2>&1
}

echo "=== review-effort: dry run, neither set ==="
NONE_OUT="$WORK/dry-none.txt"
dry "$NONE_OUT"
check "exits 0 with output" test -s "$NONE_OUT"
check "no stage line carries --effort" bash -c "! grep -q -- '--effort' '$NONE_OUT'"

echo "=== review-effort: dry run, HARNESS_EFFORT only ==="
BUILD_OUT="$WORK/dry-build.txt"
dry "$BUILD_OUT" HARNESS_EFFORT=$BUILD_EFFORT
check "method line carries the build effort" bash -c "grep -E 'methods/.*/run\.sh' '$BUILD_OUT' | grep -q -- '--effort $BUILD_EFFORT'"
check "review line follows the build effort (it falls back)" bash -c "grep 'review preamble' '$BUILD_OUT' | grep -q -- '--effort $BUILD_EFFORT '"
check "rework line carries the build effort" bash -c "grep 'rework preamble' '$BUILD_OUT' | grep -q -- '--effort $BUILD_EFFORT '"

echo "=== review-effort: dry run, both set ==="
SET_OUT="$WORK/dry-set.txt"
dry "$SET_OUT" HARNESS_EFFORT=$BUILD_EFFORT HARNESS_REVIEW_EFFORT=$REVIEW_EFFORT
check "method line keeps the build effort" bash -c "grep -E 'methods/.*/run\.sh' '$SET_OUT' | grep -q -- '--effort $BUILD_EFFORT'"
check "method line does not carry the review effort" bash -c "! grep -E 'methods/.*/run\.sh' '$SET_OUT' | grep -q -- '--effort $REVIEW_EFFORT'"
check "review line carries the review effort" bash -c "grep 'review preamble' '$SET_OUT' | grep -q -- '--effort $REVIEW_EFFORT '"
check "review line does not carry the build effort" bash -c "! grep 'review preamble' '$SET_OUT' | grep -q -- '--effort $BUILD_EFFORT'"
check "rework line stays on the build effort" bash -c "grep 'rework preamble' '$SET_OUT' | grep -q -- '--effort $BUILD_EFFORT '"
check "rework line does not carry the review effort" bash -c "! grep 'rework preamble' '$SET_OUT' | grep -q -- '--effort $REVIEW_EFFORT'"

echo "=== review-effort: dry run, HARNESS_REVIEW_EFFORT only ==="
ONLY_OUT="$WORK/dry-only.txt"
dry "$ONLY_OUT" HARNESS_REVIEW_EFFORT=$REVIEW_EFFORT
check "review line carries the review effort" bash -c "grep 'review preamble' '$ONLY_OUT' | grep -q -- '--effort $REVIEW_EFFORT '"
check "method and rework lines carry no --effort" bash -c "! grep -E 'methods/.*/run\.sh|rework preamble' '$ONLY_OUT' | grep -q -- '--effort'"

echo "=== review-effort: refusal ==="
BAD_OUT="$WORK/dry-bad.txt"
dry "$BAD_OUT" HARNESS_REVIEW_EFFORT=$BAD_EFFORT
bad_rc=$?
check "an invalid HARNESS_REVIEW_EFFORT makes the run exit non-zero" test "$bad_rc" -ne 0
check "... naming the value and the levels" bash -c "grep -q '$BAD_EFFORT' '$BAD_OUT' && grep -q 'low medium high xhigh max' '$BAD_OUT'"

echo ""
if (( failures > 0 )); then
  echo "review-effort: $failures check(s) FAILED"
  exit 1
fi
echo "review-effort: all checks passed"
