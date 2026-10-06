#!/usr/bin/env bash
set -uo pipefail

# Self-test for the resumable gate (self/DESIGN-2026-10-05-cloud-execution.md §8): a gate
# killed with the container re-runs only what had not finished. Run by self/gate.sh, or by
# hand: bash self/tests/gate-resume.sh
#
# Both gates carry the mechanism — templates/plans/gate.sh (what a consuming repo seeds)
# and self/gate.sh (this checkout's own, which tracks the template's version) — so every
# scenario runs against each. Each sandbox is a throwaway git repo holding a COPY of the
# real gate whose checks block is replaced by four stub checks (`c1`, `unit tests/fast`,
# `c3`, `c4`); the stub lives outside the repo, appends its name to a run log, and can be
# told to hang (so the test kills the gate mid-run, as a container restart would) or to
# fail. No model, no network.
#
# Asserts, for each gate:
#   K1. a gate killed while check 3 runs leaves checks 1 and 2 recorded under
#       <state>/<tree-sha>/<label>, the label sanitised for a filename, check 3 unrecorded;
#       the real index is byte-identical (a staged change survives), and the gate's
#       outputs leave `git status` as it was;
#   K2. re-run under GATE_RESUME=1 on the same tree it runs from check 3 on, and its report
#       is complete — every section in order, the verdict `all checks passed`;
#   K3. a third resumed run on the same tree runs nothing, and still reports all four;
#   K4. without GATE_RESUME every check runs;
#   K5. a changed tracked file is a changed tree: everything runs, and only the current
#       tree's state is kept;
#   K6. so is an untracked file (the tree is `git write-tree` with untracked inputs
#       included), while the gate's own report and state never move the sha;
#   K7. a recorded FAILURE is not reused — only a pass is; the failed check re-runs alone;
#   K8. a check whose command line changed (a level gate's expected-red flags) re-runs;
#   K9. a `git write-tree` that fails runs everything (never skips on an unknown tree);
#  K10. with no git at all, everything runs every time and no state is written.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gate-resume.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
unset GATE_RESUME GATE_EXPECTED_RED GATE_DEFERRED

# How long the test waits for the hanging check to start, in tenths of a second
HANG_WAIT_TENTHS=300
STUB="$TMP/stub.sh"
RUN_LOG="$TMP/run.log"
HANG_PID="$TMP/hang.pid"
REAL_GIT="$(command -v git)"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# The stub check: appends its name to the run log; hangs (pid recorded, for the kill) or
# fails when told to by name.
cat > "$STUB" <<'STUB'
#!/usr/bin/env bash
echo "$1" >> "${GATE_TEST_RUN_LOG:?}"
if [[ "${GATE_TEST_HANG_AT:-}" == "$1" ]]; then echo "$$" > "${GATE_TEST_HANG_PID:?}"; exec sleep 120; fi
if [[ "${GATE_TEST_FAIL_AT:-}" == "$1" ]]; then echo "stub $1 failing"; exit 1; fi
echo "stub $1 ok"
STUB
chmod +x "$STUB"
export GATE_TEST_RUN_LOG="$RUN_LOG" GATE_TEST_HANG_PID="$HANG_PID"

# A failing write-tree, for K9: every other git call is the real one.
mkdir -p "$TMP/badgit"
cat > "$TMP/badgit/git" <<BADGIT
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == write-tree ]] && exit 1; done
exec "$REAL_GIT" "\$@"
BADGIT
chmod +x "$TMP/badgit/git"

# stub_gate <source-gate> <checks-header-regex> — the gate's text with its checks block
# (from the header to the closing `# ────` rule) replaced by the four stub checks.
stub_gate() {
  awk -v header="$2" '
    skipping && /^# ───/ && !/[A-Za-z]/ {
      print "record \"c1\" bash \"$GATE_TEST_STUB\" c1 ${GATE_TEST_EXTRA_ARG:-}"
      print "record \"unit tests/fast\" bash \"$GATE_TEST_STUB\" c2"
      print "record \"c3\" bash \"$GATE_TEST_STUB\" c3"
      print "record \"c4\" bash \"$GATE_TEST_STUB\" c4"
      print; skipping = 0; next
    }
    skipping { next }
    $0 ~ header { print; skipping = 1; next }
    { print }
  ' "$1"
}
export GATE_TEST_STUB="$STUB"

log_line() { tr '\n' ' ' < "$RUN_LOG" 2>/dev/null | sed 's/ *$//'; }
index_sum() { shasum -a 256 "$1/.git/index" | awk '{print $1}'; }
state_dirs() { find "$1" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
verdict() { awk '/^# VERDICT/{getline; print; exit}' "$1" 2>/dev/null; }

# run_gate <gate> [VAR=value...] — one foreground run, the run log fresh.
run_gate() {
  local gate="$1"; shift
  : > "$RUN_LOG"
  env "$@" bash "$gate" > "$TMP/out" 2>&1
}

# kill_gate <gate> [VAR=value...] — a run whose check c3 hangs, killed (-9, as a container
# restart would) once c3 has started, its stub with it.
kill_gate() {
  local gate="$1" gpid i; shift
  : > "$RUN_LOG"; rm -f "$HANG_PID"
  env "$@" GATE_TEST_HANG_AT=c3 bash "$gate" > "$TMP/out" 2>&1 &
  gpid=$!
  for (( i = 0; i < HANG_WAIT_TENTHS; i++ )); do
    [[ -s "$HANG_PID" ]] && break
    sleep 0.1
  done
  kill -9 "$gpid" 2>/dev/null
  [[ -s "$HANG_PID" ]] && kill -9 "$(cat "$HANG_PID")" 2>/dev/null
  wait "$gpid" 2>/dev/null
  return 0
}

# scenarios <kind> <gate-rel> <report-rel> <state-rel> <source-gate> <header-regex> <ignore>
scenarios() {
  local kind="$1" gate_rel="$2" report_rel="$3" state_rel="$4" src="$5" header="$6" ignore="$7" corpus_rel="$8"
  local R="$TMP/$kind" G report state before_index before_status
  G="$R/$gate_rel"; report="$R/$report_rel"; state="$R/$state_rel"
  mkdir -p "$(dirname "$G")" "$R/$corpus_rel/lvl"
  echo '{"at":"x","event":"pass_start"}' > "$R/$corpus_rel/lvl/timing.jsonl"
  stub_gate "$src" "$header" > "$G"
  chmod +x "$G"
  printf '%s\n' "$ignore" > "$R/${ignore_file_rel}"
  echo "tracked" > "$R/tracked.txt"
  echo "staged before" > "$R/staged.txt"
  git init -q "$R"
  git -C "$R" config user.email test@example.invalid
  git -C "$R" config user.name "gate resume test"
  git -C "$R" add -A
  git -C "$R" commit -q -m init
  echo "staged after" > "$R/staged.txt"
  git -C "$R" add staged.txt
  before_index="$(index_sum "$R")"
  before_status="$(git -C "$R" status --porcelain)"
  check "$kind: the stub gate replaced the checks block" \
    'grep -q "GATE_TEST_STUB" "$G" && [[ "$(grep -c "GATE_TEST_STUB" "$G")" == 4 ]]'

  kill_gate "$G" GATE_RESUME=1
  check "K1a. $kind: killed during c3 — c1, c2, c3 had started (got '$(log_line)')" \
    '[[ "$(log_line)" == "c1 c2 c3" ]]'
  check "K1b. $kind: one tree's state, c1 and the sanitised 'unit tests/fast' recorded, c3 not" \
    '[[ "$(state_dirs "$state")" == 1 ]] && ls "$state"/*/c1 >/dev/null 2>&1 && ls "$state"/*/unit_tests_fast >/dev/null 2>&1 && ! ls "$state"/*/c3 >/dev/null 2>&1'
  check "K1c. $kind: the real index is byte-identical, the staged change still staged" \
    '[[ "$(index_sum "$R")" == "$before_index" ]] && [[ "$(git -C "$R" diff --cached --name-only)" == staged.txt ]]'
  check "K1d. $kind: the gate's report and state leave git status as it was" \
    '[[ "$(git -C "$R" status --porcelain)" == "$before_status" ]]'

  run_gate "$G" GATE_RESUME=1; local rc=$?
  check "K2a. $kind: resumed on the same tree, it runs from c3 (got '$(log_line)', rc $rc)" \
    '[[ "$(log_line)" == "c3 c4" && $rc -eq 0 ]]'
  check "K2b. $kind: ... says which checks it reused" 'grep -q "c1.*resumed" "$TMP/out"'
  check "K2c. $kind: ... and its report is complete, in order, all checks passed" \
    '[[ "$(grep "^## " "$report" | tr "\n" "|")" == "## c1|## unit tests/fast|## c3|## c4|" && "$(verdict "$report")" == "all checks passed" ]]'
  check "K2d. $kind: the real index is still byte-identical" '[[ "$(index_sum "$R")" == "$before_index" ]]'

  run_gate "$G" GATE_RESUME=1
  check "K3. $kind: a third resumed run on the same tree runs nothing, reports all four (got '$(log_line)')" \
    '[[ -z "$(log_line)" && "$(grep -c "^## " "$report")" == 4 && "$(verdict "$report")" == "all checks passed" ]]'

  run_gate "$G"
  check "K4. $kind: without GATE_RESUME every check runs (got '$(log_line)')" \
    '[[ "$(log_line)" == "c1 c2 c3 c4" ]]'

  echo "changed" >> "$R/tracked.txt"
  run_gate "$G" GATE_RESUME=1
  check "K5a. $kind: a changed tracked file re-runs everything (got '$(log_line)')" \
    '[[ "$(log_line)" == "c1 c2 c3 c4" ]]'
  check "K5b. $kind: ... and only the current tree's state is kept" '[[ "$(state_dirs "$state")" == 1 ]]'

  echo "new" > "$R/untracked.txt"
  run_gate "$G" GATE_RESUME=1
  check "K6a. $kind: an untracked file re-runs everything (got '$(log_line)')" \
    '[[ "$(log_line)" == "c1 c2 c3 c4" ]]'
  run_gate "$G" GATE_RESUME=1
  check "K6b. $kind: ... and the report and state the gate itself wrote do not move the sha (got '$(log_line)')" \
    '[[ -z "$(log_line)" ]]'

  echo "again" > "$R/untracked2.txt"
  run_gate "$G" GATE_RESUME=1 GATE_TEST_FAIL_AT=c2
  run_gate "$G" GATE_RESUME=1
  check "K7. $kind: a recorded failure is re-run, the recorded passes are not (got '$(log_line)')" \
    '[[ "$(log_line)" == "c2" && "$(verdict "$report")" == "all checks passed" ]]'

  run_gate "$G" GATE_RESUME=1 GATE_TEST_EXTRA_ARG=--ignore-glob=x
  check "K8. $kind: a check whose command line changed re-runs, alone (got '$(log_line)')" \
    '[[ "$(log_line)" == "c1" ]]'

  run_gate "$G" GATE_RESUME=1 GATE_TEST_EXTRA_ARG=--ignore-glob=x PATH="$TMP/badgit:$PATH"
  check "K9. $kind: a failing git write-tree runs everything (got '$(log_line)')" \
    '[[ "$(log_line)" == "c1 c2 c3 c4" ]]'

  # The features corpus holds the runners' records, not gate inputs (escalation 01, NOTES
  # ruling 42): editing it keeps the state, editing anything else resets it.
  run_gate "$G" GATE_RESUME=1
  run_gate "$G" GATE_RESUME=1
  check "K11a. $kind: settled — a resumed run on an unchanged tree runs nothing (got '$(log_line)')" \
    '[[ -z "$(log_line)" ]]'
  echo "a stamped line" >> "$R/$corpus_rel/lvl/timing.jsonl"
  echo "a new record" > "$R/$corpus_rel/lvl/new-record.md"
  mkdir -p "$R/$corpus_rel/lvl/auto/complete"
  mv "$R/$corpus_rel/lvl/new-record.md" "$R/$corpus_rel/lvl/auto/complete/new-record.md"
  run_gate "$G" GATE_RESUME=1
  check "K11b. $kind: an edit, an addition and a move inside the features corpus keep the state (got '$(log_line)')" \
    '[[ -z "$(log_line)" ]]'
  echo "outside" > "$R/outside.txt"
  run_gate "$G" GATE_RESUME=1
  check "K11c. $kind: a change outside the corpus still resets it (got '$(log_line)')" \
    '[[ "$(log_line)" == "c1 c2 c3 c4" ]]'

  local N="$TMP/$kind-nogit"
  mkdir -p "$(dirname "$N/$gate_rel")"
  cp "$G" "$N/$gate_rel"
  run_gate "$N/$gate_rel" GATE_RESUME=1 GIT_CEILING_DIRECTORIES="$TMP"
  run_gate "$N/$gate_rel" GATE_RESUME=1 GIT_CEILING_DIRECTORIES="$TMP"
  check "K10. $kind: with no git, the second resumed run still runs everything, writing no state (got '$(log_line)')" \
    '[[ "$(log_line)" == "c1 c2 c3 c4" && ! -e "$N/$state_rel" ]]'
}

echo "gate-resume"

ignore_file_rel="plans/.gitignore"
mkdir -p "$TMP/template/plans"
scenarios template plans/gate.sh plans/gate-report.txt plans/gate-state \
  "$HERE/templates/plans/gate.sh" "^# ── REPO-SPECIFIC: the checks themselves" \
  "$(cat "$HERE/templates/plans/.gitignore")" plans/features

ignore_file_rel=".gitignore"
mkdir -p "$TMP/self"
scenarios self self/gate.sh self/gate-report.txt self/gate-state \
  "$HERE/self/gate.sh" "^# ── The checks" \
  "$(grep -E '^self/gate-(report|state)' "$HERE/.gitignore")" self/features

# ── Through a runner (escalation 01): the template gate under run-plans.sh ───
# The gate scripts alone resume; the runners write into the checkout between gate runs —
# stamp_timing's line in timing.jsonl before every gate, the sentinel's move between
# incomplete/, inprogress/ and complete/ — so this drives the real entry point
# (run_level_gate, from run-plans.sh on a level sentinel) in a consuming-repo layout:
# <repo>/agentTooling/ (the runner), <repo>/plans/gate.sh (the stubbed template gate),
# <repo>/plans/features/lvl/ (the feature directory, which stamp_timing needs to write).
RUNNER_SCRIPTS="run-plans.sh plan-runner-lib.sh plan-runner-roots.sh"
RUNNER_SLUG=lvl
RUNNER_LEVEL=05
RR="$TMP/runner"
RAT="$RR/agentTooling"
RF="$RR/plans/features/$RUNNER_SLUG"
mkdir -p "$RAT" "$RR/plans" "$TMP/bin"
for f in $RUNNER_SCRIPTS; do cp "$HERE/$f" "$RAT/$f"; done
chmod +x "$RAT/run-plans.sh"
cat > "$TMP/bin/claude" <<'CLAUDE'
#!/usr/bin/env bash
printf '{"type":"result","subtype":"success","total_cost_usd":0,"num_turns":1,"session_id":"stub","usage":{}}\n'
CLAUDE
chmod +x "$TMP/bin/claude"
stub_gate "$HERE/templates/plans/gate.sh" "^# ── REPO-SPECIFIC: the checks themselves" > "$RR/plans/gate.sh"
chmod +x "$RR/plans/gate.sh"
cp "$HERE/templates/plans/.gitignore" "$RR/plans/.gitignore"
echo "tracked" > "$RR/tracked.txt"
git init -q "$RR"
git -C "$RR" config user.email test@example.invalid
git -C "$RR" config user.name "gate resume test"

# reset_runner_feature — a fresh feature with one level sentinel queued, committed
reset_runner_feature() {
  rm -rf "$RF" "$RR/outside.txt" "$RR/plans/gate-state"
  mkdir -p "$RF/auto/incomplete"
  echo "{\"slug\":\"$RUNNER_SLUG\",\"plans\":[],\"branches\":[]}" > "$RF/README.md"
  echo "# level 1" > "$RF/auto/incomplete/$RUNNER_LEVEL-gate.md"
  git -C "$RR" add -A
  git -C "$RR" commit -q --allow-empty -m "reset"
}

# runner_pass [VAR=value...] — one run-plans.sh pass, foreground
runner_pass() {
  : > "$RUN_LOG"
  ( cd "$RAT" && env PATH="$TMP/bin:$PATH" "$@" ./run-plans.sh "$RUNNER_SLUG" ) > "$TMP/out" 2>&1
}

# runner_kill — a pass whose c3 hangs, killed with its whole process group (-9, as a
# container restart would) once c3 has started. The group comes from bash's own job
# control (`set -m` puts a background job in a process group of its own, led by $!), not
# from `setsid`, which macOS does not ship.
runner_kill() {
  local gpid i
  : > "$RUN_LOG"; rm -f "$HANG_PID"
  set -m
  ( cd "$RAT" && exec env PATH="$TMP/bin:$PATH" GATE_TEST_HANG_AT=c3 ./run-plans.sh "$RUNNER_SLUG" ) > "$TMP/out" 2>&1 &
  gpid=$!
  set +m
  for (( i = 0; i < HANG_WAIT_TENTHS; i++ )); do
    [[ -s "$HANG_PID" ]] && break
    sleep 0.1
  done
  kill -9 -- "-$gpid" 2>/dev/null
  [[ -s "$HANG_PID" ]] && kill -9 "$(cat "$HANG_PID")" 2>/dev/null
  wait "$gpid" 2>/dev/null
  return 0
}

reset_runner_feature
runner_kill
check "R1a. runner: run-plans.sh killed during c3 — c1, c2, c3 had started (got '$(log_line)')" \
  '[[ "$(log_line)" == "c1 c2 c3" ]]'
check "R1b. runner: stamp_timing was live — the gate_start line is in the feature's timing.jsonl" \
  'grep -q "\"event\":\"gate_start\"" "$RF/timing.jsonl"'
runner_pass
check "R2. runner: re-run through the same entry point runs only c3 and c4 (got '$(log_line)')" \
  '[[ "$(log_line)" == "c3 c4" ]]'
check "R2b. runner: ... the sentinel is filed complete, and the gate ran with its label" \
  '[[ -f "$RF/auto/complete/$RUNNER_LEVEL-gate.md" && -f "$RR/plans/gate-report.$RUNNER_LEVEL.txt" ]]'

reset_runner_feature
runner_kill
echo "an architect's note" > "$RF/NOTES.md"
echo "# hand edit" >> "$RF/README.md"
runner_pass
check "R3. runner: a corpus edit between the runs keeps the state (got '$(log_line)')" \
  '[[ "$(log_line)" == "c3 c4" ]]'

reset_runner_feature
runner_kill
echo "outside" > "$RR/outside.txt"
runner_pass
check "R4. runner: a change outside the corpus between the runs resets it (got '$(log_line)')" \
  '[[ "$(log_line)" == "c1 c2 c3 c4" ]]'

echo
if (( fails > 0 )); then echo "gate-resume: $fails assertion(s) FAILED"; exit 1; fi
echo "gate-resume: all assertions passed"
