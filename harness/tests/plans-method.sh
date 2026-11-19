#!/usr/bin/env bash
set -uo pipefail

# Self-test for the `plans` method's batch half (harness/methods/plans/run.sh). Run by
# self/gate.sh, or by hand: bash harness/tests/plans-method.sh
#
# A throwaway git tree under mktemp -d holds a finished architect corpus (the three
# incomplete/ queues and NOTES.md) and a stub agentTooling/run-batch.sh whose behaviour the
# test picks; the architect is a fake `claude` behind HARNESS_CLAUDE_BIN. No model, no
# network, no money.
#
# Asserts:
#   1. a batch that succeeds exits 0, leaves `git status` clean in the tree (nothing the
#      method wrote is a dirty path), and writes its log under HARNESS_LOG_DIR;
#   2. the log is appended, not truncated, across two runs;
#   3. a batch that exits non-zero with no usage-limit evidence exits 1 (METHOD_FAILED_RC)
#      at once: exactly one run-batch.sh call, the last lines of the log in the warning —
#      the exportStoreMethodEffortDefault close refusal is this shape;
#   4. a batch whose output carries the runners' usage-limit summary exits 2
#      (METHOD_USAGE_LIMIT_RC) after one call, and so does the interrupt summary;
#   5. evidence from an EARLIER run in the appended log does not make a later plain failure
#      resumable;
#   6. an escalation on disk fails the method even with usage-limit evidence;
#   7. the two evidence strings still appear in plan-runner-lib.sh, where the runners print
#      them;
#   8. a call with the batch already started (a plan in inprogress/, the incomplete/ queues
#      drained) skips the architect and goes straight to the batch — the call the harness
#      makes after exit 2. Test 1 asserts the converse: a first call runs the architect.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$HERE/harness/methods/plans/run.sh"
LIB="$HERE/plan-runner-lib.sh"

# Fixture names
SLUG="planscell"
BRANCH_NAME="exp-branch"
BATCH_CALLS_FILE="batch-calls"
# What the runners print (plan-runner-lib.sh exit_reason), as the stub batch reproduces it
LIMIT_SUMMARY="  Build pass [$SLUG]: stopped: Claude usage limit reached on 01-x.md (left in inprogress for next run)"
INTERRUPT_SUMMARY="  Build pass [$SLUG]: interrupted by signal (in-progress plan left for next run)"
REFUSAL_LINE="feature-close: refused — these dirty paths are not $SLUG's cost records"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TREE="$WORK/tree"
LOGS="$WORK/logs"
BIN="$WORK/bin"
mkdir -p "$TREE/agentTooling" "$LOGS" "$BIN"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ── The tree: a finished architect corpus, committed ─────────────────────────
FEATURE="$TREE/plans/features/$SLUG"
for queue in auto verify review; do
  mkdir -p "$FEATURE/$queue/incomplete"
  echo "# plan" > "$FEATURE/$queue/incomplete/01-x.md"
done
echo "# notes" > "$FEATURE/NOTES.md"

# The stub batch. BATCH_MODE picks what it prints and exits with; each call is counted in
# a file OUTSIDE the tree so the count cannot dirty it.
cat > "$TREE/agentTooling/run-batch.sh" <<STUB
#!/usr/bin/env bash
echo x >> "$WORK/$BATCH_CALLS_FILE"
case "\${BATCH_MODE:-ok}" in
  ok)        echo "batch: all done"; exit 0 ;;
  refuse)    echo "batch: review clean"; echo "$REFUSAL_LINE"; echo "plans/batch.log"; exit 1 ;;
  limit)     echo "$LIMIT_SUMMARY"; exit 1 ;;
  interrupt) echo "$INTERRUPT_SUMMARY"; exit 1 ;;
esac
STUB
chmod +x "$TREE/agentTooling/run-batch.sh"

# The architect: a fake claude that succeeds and says nothing about limits.
cat > "$BIN/claude" <<'FAKE'
#!/usr/bin/env bash
cat > /dev/null
echo x >> "$CLAUDE_CALLS_FILE"
printf '{"type":"result","subtype":"success","is_error":false,"session_id":"fake","total_cost_usd":0,"result":"architect ok"}\n'
FAKE
chmod +x "$BIN/claude"

git -C "$TREE" init -q
git -C "$TREE" add -A
git -C "$TREE" -c user.email=t@t -c user.name=t commit -q -m base

BRIEF="$LOGS/brief.md"
echo "# brief" > "$BRIEF"
LOG="$LOGS/$BRANCH_NAME-plans-batch.log"

# run_method <mode> -> sets rc, OUT (stdout+stderr)
run_method() {
  OUT="$(BATCH_MODE="$1" CLAUDE_CALLS_FILE="$WORK/claude-calls" HARNESS_CLAUDE_BIN="$BIN/claude" HARNESS_LOG_DIR="$LOGS" \
    HARNESS_BRANCH_NAME="$BRANCH_NAME" HARNESS_METHOD_RESULT="$LOGS/result.json" \
    bash "$RUN" "$TREE" "$BRIEF" "$SLUG" 2>&1)"
  rc=$?
}
calls() { wc -l < "$WORK/$BATCH_CALLS_FILE" 2>/dev/null || echo 0; }
reset_calls() { rm -f "$WORK/$BATCH_CALLS_FILE"; }

# ── 1, 2: a successful batch ─────────────────────────────────────────────────
reset_calls
rm -f "$WORK/claude-calls"
run_method ok
check "1a. a successful batch exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "1e. a first call (queues full, nothing started) runs the architect" '[[ -s "$WORK/claude-calls" ]]'
check "1b. the tree has no dirty path afterwards" '[[ -z "$(git -C "$TREE" status --porcelain)" ]]'
check "1c. the batch log is under HARNESS_LOG_DIR" 'grep -q "batch: all done" "$LOG"'
check "1d. nothing named batch.log is in the tree" '[[ -z "$(find "$TREE" -name "*.log" -not -path "*/.git/*")" ]]'
run_method ok
check "2a. a second run appends: both runs' output is in the log" '[[ "$(grep -c "batch: all done" "$LOG")" -eq 2 ]]'

# ── 3: a non-zero exit with no evidence fails at once ────────────────────────
reset_calls
run_method refuse
check "3a. a close refusal exits 1, not 2 (got $rc)" '[[ $rc -eq 1 ]]'
check "3b. run-batch.sh ran exactly once (got $(calls))" '[[ "$(calls)" -eq 1 ]]'
check "3c. the warning carries the log tail" 'grep -qF "$REFUSAL_LINE" <<<"$OUT" && grep -q "no usage-limit or interrupt evidence" <<<"$OUT"'
check "3d. the tree is still clean" '[[ -z "$(git -C "$TREE" status --porcelain)" ]]'

# ── 4: positive evidence stays resumable, after one call ─────────────────────
reset_calls
run_method limit
check "4a. a usage-limit summary exits 2 (got $rc)" '[[ $rc -eq 2 ]]'
check "4b. run-batch.sh ran exactly once (got $(calls))" '[[ "$(calls)" -eq 1 ]]'
reset_calls
run_method interrupt
check "4c. an interrupt summary exits 2 (got $rc)" '[[ $rc -eq 2 ]]'
check "4d. run-batch.sh ran exactly once (got $(calls))" '[[ "$(calls)" -eq 1 ]]'

# ── 5: earlier runs' evidence does not count ─────────────────────────────────
# The log now holds limit and interrupt summaries from 4. A plain failure must still fail.
reset_calls
run_method refuse
check "5a. old evidence in the appended log does not make a failure resumable (got $rc)" '[[ $rc -eq 1 ]]'
check "5b. the warning shows this run's output only, not an earlier run's limit message" '! grep -q "usage limit reached" <<<"$OUT"'

# ── 6: an escalation wins ────────────────────────────────────────────────────
mkdir -p "$FEATURE/escalations"
echo "# esc" > "$FEATURE/escalations/01.md"
reset_calls
run_method limit
check "6a. an escalation fails the method despite evidence (got $rc)" '[[ $rc -eq 1 ]]'
rm -rf "$FEATURE/escalations"

# ── 8: the call after exit 2 resumes the batch, without the architect ────────
# The harness re-runs the whole script after a usage-limit stop. By then the batch has
# drained incomplete/ into inprogress/ and complete/.
for queue in auto verify review; do rm -f "$FEATURE/$queue/incomplete"/*.md; done
mkdir -p "$FEATURE/auto/inprogress"
echo "# plan" > "$FEATURE/auto/inprogress/01-x.md"
reset_calls
rm -f "$WORK/claude-calls"
run_method ok
check "8a. the call after a limit stop exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "8b. the architect was not called again" '[[ ! -e "$WORK/claude-calls" ]]'
check "8c. run-batch.sh ran once (got $(calls))" '[[ "$(calls)" -eq 1 ]]'
run_method limit
check "8d. and a further limit stop is still resumable (got $rc)" '[[ $rc -eq 2 ]]'

# ── 7: the evidence strings are what the runners print ───────────────────────
check "7a. plan-runner-lib.sh still prints the usage-limit reason" "grep -qF 'stopped: Claude usage limit reached on ' '$LIB'"
check "7b. plan-runner-lib.sh still prints the interrupt reason" "grep -qF 'interrupted by signal (in-progress plan left for next run)' '$LIB'"

if (( fails > 0 )); then echo "plans-method: $fails assertion(s) FAILED"; exit 1; fi
echo "plans-method: all assertions passed"
