#!/usr/bin/env bash
set -uo pipefail

# Long runs: run.sh's time budget (exit 75 and a resume line), repeated --only, the --from
# refusal on a cell with no worktree, the per-experiment lock, and --reset. Black-box:
# everything goes through harness/run.sh against a throwaway consumer per case.
#
#   harness/tests/long-runs.sh
#
# No network, no money, no model stage runs: a `mktemp -d` directory, removed on exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_TOOLING_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
RUN="$HARNESS_DIR/run.sh"

# The consumer
FIXTURE_NAME="lrfix"
BRANCH_STEM="lrStem"
EXPERIMENT_NAME="longRuns"
REPEATS=2
BRANCH_1="lrStemNull1"      # harness_branch_name lrStem null 1 2 ""
BRANCH_2="lrStemNull2"      # harness_branch_name lrStem null 2 2 ""
SPEC_1="$FIXTURE_NAME:null:1"
SPEC_2="$FIXTURE_NAME:null:2"
SPEC_BOTH="$FIXTURE_NAME:null"
SPEC_NONE="nosuch:null:1"
SPEC_UNKNOWN="nosuch"
GATE_GREEN="gate-is-green"   # what the fixture's gate prints, and what counts as green
GIT_USER_EMAIL="long-runs@example.invalid"
GIT_USER_NAME="Harness Long Runs"

# Exit codes and wording the harness is held to
EXIT_BUDGET_STOP=75
RESUME_PREFIX="resume: "
MSG_RESET_HINT="--reset"
MSG_IN_PROGRESS="in progress"
MSG_NOTHING_TO_RESET="nothing to reset"
MSG_ESTIMATE_EXCEEDS="exceeds the budget"
MSG_FROM_REFUSAL="needs the earlier stages"

# Time budgets (minutes), and the stage durations of the finished cell
BUDGET_TOO_SMALL=1
BUDGET_MID=150
FINISHED_CELL_MINUTES=200
FINISHED_STATE_NAME="doneNull"
STAGE_SETUP_START="2026-01-01T00:00:00Z"
STAGE_SETUP_END="2026-01-01T01:00:00Z"
STAGE_RECORD_START="2026-01-01T02:00:00Z"
STAGE_RECORD_END="2026-01-01T04:20:00Z"

# The on-disk cell
COST_LOST_USD="1.25"
UNTRACKED_FILE="untracked-note.txt"
COMMITTED_FILE="committed-note.txt"
KILLED_INFIX="Killed"
LOCK_DIR_NAME="harness-locks"
LOCK_SUFFIX=".lock"

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/long-runs.XXXXXX")"
[[ -n "$WORK" && -d "$WORK" ]] || { echo "long-runs: cannot create a work directory" >&2; exit 1; }
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

# setup_consumer <case> — a fresh consumer under $WORK/<case>; sets REPO, EXP, STATE_DIR,
# RESULTS and LOCK_DIR.
setup_consumer() {
  local case_name="$1" base_sha
  REPO="$WORK/$case_name/repo"
  mkdir -p "$REPO/plans"
  ln -s "$AGENT_TOOLING_DIR" "$REPO/agentTooling"
  printf '# Spec\n\n## 1. Nothing\n\nNothing.\n' > "$REPO/SPEC.md"
  printf 'plans/experiments/*/logs/\n' > "$REPO/.gitignore"
  local fixture_dir="$REPO/plans/experiments/fixtures/$FIXTURE_NAME"
  mkdir -p "$fixture_dir"
  printf 'facts\n' > "$fixture_dir/facts.md"
  printf 'brief\n' > "$fixture_dir/review-brief.md"
  EXP="$REPO/plans/experiments/$EXPERIMENT_NAME"
  mkdir -p "$EXP"
  printf '# %s\n' "$EXPERIMENT_NAME" > "$EXP/README.md"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email "$GIT_USER_EMAIL"
  git -C "$REPO" config user.name "$GIT_USER_NAME"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "base"
  base_sha="$(git -C "$REPO" rev-parse HEAD)"
  cat > "$fixture_dir/fixture.json" <<FIXTURE
{
  "name": "$FIXTURE_NAME",
  "base": "$base_sha",
  "spec": {"commit": "$base_sha", "path": "SPEC.md", "sections": ["1"]},
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
  "methods": ["null"],
  "repeats": $REPEATS,
  "stages": {"review": false, "rework": false, "accept": false},
  "noise_band_pct": 15,
  "prediction": "the harness stops, resets and refuses as the long-runs test says",
  "compare_to": ""
}
EXPERIMENT
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "fixture and experiment"
  git init -q --bare "$WORK/$case_name/remote.git"
  git -C "$REPO" remote add origin "$WORK/$case_name/remote.git"
  git -C "$REPO" push -q -u origin HEAD 2>/dev/null
  STATE_DIR="$EXP/state"
  RESULTS="$EXP/results.jsonl"
  LOCK_DIR="$REPO/.git/$LOCK_DIR_NAME/$(basename "$EXP")$LOCK_SUFFIX"
  OUT="$WORK/$case_name/out.txt"
}

# make_cell_on_disk <n> — the cell's branch (one commit), worktree (one untracked file) and
# a state file carrying cost_lost_usd.
make_cell_on_disk() {
  local n="$1" branch tree
  branch="$BRANCH_STEM"Null"$n"
  tree="$REPO-$branch"
  git -C "$REPO" worktree add -q -b "$branch" "$tree" HEAD
  printf 'work\n' > "$tree/$COMMITTED_FILE"
  git -C "$tree" add "$COMMITTED_FILE"
  git -C "$tree" commit -q -m "cell work"
  printf 'scratch\n' > "$tree/$UNTRACKED_FILE"
  mkdir -p "$STATE_DIR"
  cat > "$STATE_DIR/$branch.json" <<STATE
{"t_setup_start":"$STAGE_SETUP_START","cost_lost_usd":$COST_LOST_USD,"stages":{"setup":{"start":"$STAGE_SETUP_START","end":"$STAGE_SETUP_END","outcome":"ok"}}}
STATE
}

# seed_finished_cell — a finished cell's state file whose stage durations sum to
# FINISHED_CELL_MINUTES: the run's estimate for every cell, however fast the real ones are.
seed_finished_cell() {
  mkdir -p "$STATE_DIR"
  cat > "$STATE_DIR/$FINISHED_STATE_NAME.json" <<STATE
{"stages":{"setup":{"start":"$STAGE_SETUP_START","end":"$STAGE_SETUP_END","outcome":"ok"},"record":{"start":"$STAGE_RECORD_START","end":"$STAGE_RECORD_END","outcome":"ok"}}}
STATE
}

# run_harness <args…> — run.sh against this case's experiment; sets rc, output in $OUT.
run_harness() {
  "$RUN" "$EXP" --consumer "$REPO" "$@" > "$OUT" 2>&1
  rc=$?
}

out_has() { grep -q -- "$1" "$OUT"; }
state_files() { ls "$STATE_DIR"/*.json 2>/dev/null; }
no_state_files() { [[ -z "$(state_files)" ]]; }
lock_gone() { [[ ! -e "$LOCK_DIR" ]]; }
hold_lock() { mkdir -p "$LOCK_DIR"; printf '%s\n' "$1" > "$LOCK_DIR/pid"; }

# ── 1. --only may be repeated ────────────────────────────────────────────────
echo "=== long-runs: repeated --only ==="
setup_consumer c1
run_harness --dry-run --only "$SPEC_1" --only "$SPEC_2"
check "two --only specs dry-run exits 0" test "$rc" -eq 0
check "two --only specs name both branches" bash -c "grep -q '$BRANCH_1' '$OUT' && grep -q '$BRANCH_2' '$OUT'"
run_harness --dry-run --only "$SPEC_1"
check "one --only spec dry-runs exits 0" test "$rc" -eq 0
check "one --only spec names its branch" out_has "$BRANCH_1"
check "one --only spec does not name the other" bash -c "! grep -q '$BRANCH_2' '$OUT'"

# ── 2. A spec that matches nothing is refused before any cell starts ─────────
echo "=== long-runs: unknown --only ==="
setup_consumer c2
run_harness --only "$SPEC_1" --only "$SPEC_UNKNOWN"
check "unmatched --only exits non-zero" test "$rc" -ne 0
check "unmatched --only names the spec" out_has "$SPEC_UNKNOWN"
check "unmatched --only starts no cell" no_state_files

# ── 3. --from past setup on a cell with no worktree ──────────────────────────
echo "=== long-runs: --from without a worktree ==="
setup_consumer c3
mkdir -p "$STATE_DIR"
printf '{"t_setup_start":"%s","stages":{}}\n' "$STAGE_SETUP_START" > "$STATE_DIR/$BRANCH_1.json"
cp "$STATE_DIR/$BRANCH_1.json" "$WORK/c3/state.before"
run_harness --from method --only "$SPEC_1"
check "--from method with no worktree exits non-zero" test "$rc" -ne 0
check "--from refusal points at --reset" out_has "$MSG_RESET_HINT"
check "--from refusal appends no row" test ! -e "$RESULTS"
check "--from refusal leaves the state file byte-identical" cmp "$STATE_DIR/$BRANCH_1.json" "$WORK/c3/state.before"

# ── 3b. --from record needs no worktree ──────────────────────────────────────
echo "=== long-runs: --from record without a worktree ==="
setup_consumer c3b
mkdir -p "$STATE_DIR"
printf '{"t_setup_start":"%s","stages":{}}\n' "$STAGE_SETUP_START" > "$STATE_DIR/$BRANCH_1.json"
run_harness --from record --only "$SPEC_1"
check "--from record with no worktree is not refused by the precondition" bash -c "! grep -q -e '$MSG_FROM_REFUSAL' '$OUT'"
check "--from record with no worktree prints no --reset hint" bash -c "! grep -q -e '$MSG_RESET_HINT' '$OUT'"
check "--from record with no worktree reaches the record stage" out_has "record"
check "--from record with no worktree appends a row" test -s "$RESULTS"

# ── 4. The time budget with nothing finished ─────────────────────────────────
# The first cell of an invocation always starts (the fake claude fails it at once, which is
# all this test needs: it started, and a state file says so); the budget decides only
# whether the second does.
echo "=== long-runs: time budget smaller than any cell ==="
setup_consumer c4
seed_finished_cell
run_harness --time-budget "$BUDGET_TOO_SMALL"
check "budget stop exits $EXIT_BUDGET_STOP" test "$rc" -eq "$EXIT_BUDGET_STOP"
check "the first cell started despite the budget" test -f "$STATE_DIR/$BRANCH_1.json"
check "the second cell did not start" test ! -e "$STATE_DIR/$BRANCH_2.json"
check "the over-budget first cell is warned about" out_has "$MSG_ESTIMATE_EXCEEDS"
check "budget stop prints a resume line" out_has "^$RESUME_PREFIX"
check "resume line does not name the first cell" bash -c "! grep '^$RESUME_PREFIX' '$OUT' | grep -q -e '--only $SPEC_1'"
check "resume line names the second cell" bash -c "grep '^$RESUME_PREFIX' '$OUT' | grep -q -e '--only $SPEC_2'"
check "budget stop leaves no lock" lock_gone
# The resume line is a command: run it with --dry-run appended and it names exactly the
# remaining cell (here the second only).
resume_line="$(grep "^$RESUME_PREFIX" "$OUT" | head -n 1)"
resume_line="${resume_line#"$RESUME_PREFIX"}"
bash -c "$resume_line --dry-run" > "$OUT.resume" 2>&1
resume_rc=$?
check "the resume line, with --dry-run appended, exits 0" test "$resume_rc" -eq 0
check "the resume line's dry run names the second cell" grep -q "$BRANCH_2" "$OUT.resume"
check "the resume line's dry run does not name the first" bash -c "! grep -q '$BRANCH_1' '$OUT.resume'"
check "the resume line's dry run starts no cell" test ! -e "$STATE_DIR/$BRANCH_2.json"

# ── 5. The estimate comes from a finished cell ───────────────────────────────
echo "=== long-runs: time budget, finished cell ==="
setup_consumer c5
seed_finished_cell
run_harness --time-budget "$BUDGET_MID"
check "a $FINISHED_CELL_MINUTES-minute cell stops the second cell of a $BUDGET_MID-minute budget (exit $EXIT_BUDGET_STOP)" test "$rc" -eq "$EXIT_BUDGET_STOP"
check "the first cell started anyway" test -f "$STATE_DIR/$BRANCH_1.json"
check "the second cell did not start" test ! -e "$STATE_DIR/$BRANCH_2.json"
check "the warning names the $FINISHED_CELL_MINUTES-minute estimate" bash -c "grep '$MSG_ESTIMATE_EXCEEDS' '$OUT' | grep -q '$FINISHED_CELL_MINUTES'"
check "the warning names the ${BUDGET_MID}-minute budget" bash -c "grep '$MSG_ESTIMATE_EXCEEDS' '$OUT' | grep -q '${BUDGET_MID}m'"
check "the resume line names only the second cell" bash -c "grep '^$RESUME_PREFIX' '$OUT' | grep -q -e '--only $SPEC_2' && ! grep '^$RESUME_PREFIX' '$OUT' | grep -q -e '--only $SPEC_1'"

# ── 6. --reset on a killed cell ──────────────────────────────────────────────
echo "=== long-runs: --reset ==="
setup_consumer c6
make_cell_on_disk 1
tree_1="$REPO-$BRANCH_1"
commit_1="$(git -C "$REPO" rev-parse "$BRANCH_1")"
printf '{"branch":"%s","method_failed":true}\n' "$BRANCH_1" > "$RESULTS"
cp "$RESULTS" "$WORK/c6/results.before"
run_harness --reset "$SPEC_1"
check "--reset exits 0" test "$rc" -eq 0
check "--reset moves the old worktree path away" test ! -e "$tree_1"
killed_trees=( "$REPO-$BRANCH_1$KILLED_INFIX"* )
check "--reset leaves exactly one killed worktree" test "${#killed_trees[@]}" -eq 1
killed_tree="${killed_trees[0]}"
killed_branch="${killed_tree##*/repo-}"
check "the killed worktree keeps the untracked file" test -f "$killed_tree/$UNTRACKED_FILE"
check "the killed worktree is on the renamed branch" test "$(git -C "$killed_tree" branch --show-current)" = "$killed_branch"
check "the renamed branch carries the Killed infix" test "$killed_branch" != "$BRANCH_1" -a "${killed_branch#"$BRANCH_1$KILLED_INFIX"}" != "$killed_branch"
check "no local branch is left under the old name" bash -c "! git -C '$REPO' show-ref --verify --quiet 'refs/heads/$BRANCH_1'"
check "the commit is still reachable" git -C "$REPO" merge-base --is-ancestor "$commit_1" "$killed_branch"
check "the old state moved to state/killed/" test -f "$STATE_DIR/killed/$killed_branch.json"
new_state="$STATE_DIR/$BRANCH_1.json"
check "the fresh state carries cost_lost_usd" jq -e ".cost_lost_usd == $COST_LOST_USD" "$new_state"
check "the fresh state has no t_setup_start" jq -e 'has("t_setup_start") | not' "$new_state"
check "the fresh state has no stages" jq -e 'has("stages") | not' "$new_state"
check "the fresh state has one intervention" jq -e '.interventions | length == 1' "$new_state"
check "--reset leaves results.jsonl byte-for-byte" cmp "$RESULTS" "$WORK/c6/results.before"
check "--reset leaves no lock" lock_gone

# ── 7. Reset refused when the cell has a live row ────────────────────────────
echo "=== long-runs: --reset refused on a recorded cell ==="
setup_consumer c7
make_cell_on_disk 1
printf '{"branch":"%s","method_failed":false}\n' "$BRANCH_1" > "$RESULTS"
run_harness --reset "$SPEC_1"
check "reset of a recorded cell exits non-zero" test "$rc" -ne 0
check "recorded cell keeps its worktree" test -d "$REPO-$BRANCH_1"
check "recorded cell keeps its branch" git -C "$REPO" show-ref --verify --quiet "refs/heads/$BRANCH_1"
check "recorded cell keeps its state file" test -f "$STATE_DIR/$BRANCH_1.json"

# ── 8. Reset under the lock ──────────────────────────────────────────────────
echo "=== long-runs: --reset and the lock ==="
setup_consumer c8
make_cell_on_disk 1
hold_lock "$$"
run_harness --reset "$SPEC_1"
check "reset under a live lock exits non-zero" test "$rc" -ne 0
check "reset under a live lock says in progress" out_has "$MSG_IN_PROGRESS"
check "reset under a live lock moves nothing" test -d "$REPO-$BRANCH_1"
check "reset under a live lock keeps the branch" git -C "$REPO" show-ref --verify --quiet "refs/heads/$BRANCH_1"
true &
dead_pid=$!
wait "$dead_pid" 2>/dev/null
hold_lock "$dead_pid"
run_harness --reset "$SPEC_1"
check "reset under a stale lock exits 0" test "$rc" -eq 0
check "reset under a stale lock leaves no lock" lock_gone

# ── 9. An ordinary run under the lock ────────────────────────────────────────
echo "=== long-runs: run and the lock ==="
setup_consumer c9
hold_lock "$$"
run_harness --only "$SPEC_1"
check "a run under a live lock exits non-zero" test "$rc" -ne 0
check "a run under a live lock says in progress" out_has "$MSG_IN_PROGRESS"
check "a run under a live lock creates no state" no_state_files
run_harness --dry-run --only "$SPEC_1"
check "a dry run ignores the lock" test "$rc" -eq 0

# ── 10. Reset refusals ───────────────────────────────────────────────────────
echo "=== long-runs: --reset refusals ==="
setup_consumer c10
run_harness --reset "$SPEC_NONE"
check "reset of a spec matching no cell exits non-zero" test "$rc" -ne 0
run_harness --reset "$SPEC_BOTH"
check "reset of a spec matching two cells exits non-zero" test "$rc" -ne 0
check "the ambiguity names both branches" bash -c "grep -q '$BRANCH_1' '$OUT' && grep -q '$BRANCH_2' '$OUT'"
run_harness --reset "$SPEC_2"
check "reset of a cell with nothing on disk exits non-zero" test "$rc" -ne 0
check "the refusal says nothing to reset" out_has "$MSG_NOTHING_TO_RESET"

# ── 11. --reset is exclusive ─────────────────────────────────────────────────
echo "=== long-runs: --reset usage errors ==="
setup_consumer c11
make_cell_on_disk 1
run_harness --reset "$SPEC_1" --only "$SPEC_1"
check "--reset with --only is a usage error" test "$rc" -ne 0
run_harness --reset "$SPEC_1" --from method
check "--reset with --from is a usage error" test "$rc" -ne 0
check "usage errors move nothing" test -d "$REPO-$BRANCH_1"

echo ""
if (( failures > 0 )); then
  echo "=== long-runs: $failures check(s) FAILED ==="
  exit 1
fi
echo "=== long-runs: all checks passed ==="
