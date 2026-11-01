#!/usr/bin/env bash
set -uo pipefail

# Self-test for run-batch.sh surviving a closed stdout
# (self/features/tooling-backlog-2026-09-06/README.md, item 9). Run by self/gate.sh, or
# by hand: bash self/tests/batch-sigpipe.sh
#
# Same scaffolding as level-sentinel.sh: the real runner scripts copied into a
# throwaway agentTooling checkout under mktemp -d, a stub `claude` that emits one priced
# `result` event, a stub `self/gate.sh` that reports green, and everything driven with
# --self. No model, no network.
#
# The defect: `run_all` (plan-runner-lib.sh) traps SIGPIPE, so `run-plans.sh`,
# `run-verify.sh` and `run-review.sh` survive a consumer that stops reading their stdout
# (self/features/stream-capture-file-first, ruling 1). `run-batch.sh` is a separate
# process that sources only `plan-runner-roots.sh`, installs no such trap, and prints its
# banners to the same stdout — so a coordinator that backgrounds the batch with its
# output piped onward still killed the BATCH on its next banner. The child runner
# survived and filed its plan, so no cost record was lost; what was lost was the rest of
# the batch — the gate, the verify pass, the review pass and the PR — with no summary
# saying why (self/BACKLOG.md, raised by `stream-capture-file-first`).
#
# The consumer here is `head -2`: it takes the batch's first banner and the first line
# the build runner prints under it, then exits, which closes the pipe before the gate
# banner. `${PIPESTATUS[0]}` is the batch's own code — 141 is death by SIGPIPE.
#
# Asserts, in order:
#   1. a healthy consumer is the control: the batch exits 0 and both passes file their
#      plans, so phase 2's failures can only be the closed stdout;
#   2. with stdout closed after two lines the batch still exits 0 — not 141 — and the
#      build AND verify passes both ran and filed their plans with sidecars, which is
#      only reachable past the banner that used to kill it;
#   3. the exit code is the BATCH's, not a signal's: a build plan that fails under a
#      closed stdout still exits 1 and files the plan to auto/failed/.
#
# RED until the handler lands: phase 2 exits 141 with the verify plan still queued.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/batch-sigpipe.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
AT="$TMP/agentTooling"
mkdir -p "$AT/self/features" "$TMP/bin"
for f in run-plans.sh run-verify.sh run-review.sh run-batch.sh run-escalation-plan.sh plan-runner-lib.sh plan-runner-roots.sh; do
  cp "$HERE/$f" "$AT/$f"
done
# check-plans.sh is deliberately NOT copied: run-batch.sh's `-x` guard then skips the
# lint, so the batch's first stdout line is its own build-pass banner and "two lines"
# means the same thing on every run.

cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.25,"num_turns":1,"duration_ms":1000,"session_id":"stub","usage":{},"modelUsage":{}}\n'
exit "${CLAUDE_STUB_RC:-0}"
STUB
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

cat > "$AT/self/gate.sh" <<'STUB'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT="$HERE/self/gate-report.txt"
{ echo "# Gate report"; echo "level: ${1:-final}"; echo ""; echo "# VERDICT"; echo "all checks passed"; } > "$REPORT"
if [[ -n "${1:-}" ]]; then cp "$REPORT" "${REPORT%.txt}.$1.txt"; fi
exit 0
STUB
chmod +x "$AT/self/gate.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$AT/self/pr.sh"; chmod +x "$AT/self/pr.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "batch-sigpipe"

SLUG=bsp
F="$AT/self/features/$SLUG"
BUILD_PLAN=01-build-haiku
VERIFY_PLAN=02-verify-sonnet
# The consumer's appetite. Two lines is the batch's own first banner plus the first line
# the build runner writes under it, so the pipe closes while the batch is still inside
# its first pass — before the gate banner that used to kill it.
CONSUMER_LINES=2
# Bash's exit status for a process killed by SIGPIPE (128 + 13): the defect's signature.
SIGPIPE_RC=141

reset_feature() {
  rm -rf "$F" "$AT"/self/gate-report*.txt
  mkdir -p "$F/auto/incomplete" "$F/verify/incomplete" "$F/review/incomplete"
  cat > "$F/README.md" <<'MDEOF'
# bsp

Test fixture only, for self/tests/batch-sigpipe.sh.

```json
{"slug": "bsp", "plans": ["01-build-haiku", "02-verify-sonnet"], "branches": ["bsp"]}
```
MDEOF
  echo "build plan for bsp" > "$F/auto/incomplete/$BUILD_PLAN.md"
  echo "verify plan for bsp" > "$F/verify/incomplete/$VERIFY_PLAN.md"
}

OUT="$TMP/batch.out"
ERR="$TMP/batch.err"

# run_batch_closed <claude exit code> — the batch with its stdout closed after
# $CONSUMER_LINES lines. Prints the batch's own exit code, read from PIPESTATUS inside
# the subshell that ran the pipeline; the caller's $? is the substitution's, not the
# batch's, which is exactly the confusion this helper exists to remove.
run_batch_closed() {
  ( cd "$AT" && CLAUDE_STUB_RC="$1" \
      ./run-batch.sh --self "$SLUG" 2>"$ERR" | head -"$CONSUMER_LINES" > "$OUT"
    echo "${PIPESTATUS[0]}" )
}

# ── 1: the control — a healthy consumer ───────────────────────────────────────
reset_feature
( cd "$AT" && ./run-batch.sh --self "$SLUG" >"$OUT" 2>"$ERR" ); rc=$?
check "1a. with a healthy consumer the batch exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "1b. ...the build plan is filed with its sidecar" '[[ -f "$F/auto/complete/$BUILD_PLAN.md" && -f "$F/auto/complete/$BUILD_PLAN.usage.json" ]]'
check "1c. ...and the verify plan too, so the fixture reaches pass 2" '[[ -f "$F/verify/complete/$VERIFY_PLAN.md" && -f "$F/verify/complete/$VERIFY_PLAN.usage.json" ]]'
check "1d. ...and the batch printed more than $CONSUMER_LINES lines, so closing at $CONSUMER_LINES really cuts it off" '(( $(wc -l < "$OUT") > CONSUMER_LINES ))'

# ── 2: stdout closed after two lines ──────────────────────────────────────────
reset_feature
rc="$(run_batch_closed 0)"
check "2a. the batch exits with its own code, not $SIGPIPE_RC (got $rc)" '[[ "$rc" == "0" ]]'
check "2b. the consumer really stopped at $CONSUMER_LINES lines" '(( $(wc -l < "$OUT") == CONSUMER_LINES ))'
check "2c. the build pass ran and filed its plan with a sidecar" '[[ -f "$F/auto/complete/$BUILD_PLAN.md" && -f "$F/auto/complete/$BUILD_PLAN.usage.json" ]]'
check "2d. the verify pass ran too — past the banner that used to kill the batch" '[[ -f "$F/verify/complete/$VERIFY_PLAN.md" && -f "$F/verify/complete/$VERIFY_PLAN.usage.json" ]]'
check "2e. the batch stamped its own batch_end" 'grep -q "\"event\":\"batch_end\"" "$F/timing.jsonl"'

# ── 3: the code it exits with is the batch's ──────────────────────────────────
# A dead consumer must not turn a real failure into 141 either: the caller reads the
# batch's code to decide what to do next, and 141 tells it nothing.
reset_feature
rc="$(run_batch_closed 1)"
check "3a. a failing build under a closed stdout exits 1, not $SIGPIPE_RC (got $rc)" '[[ "$rc" == "1" ]]'
check "3b. ...and the plan is filed to auto/failed/" '[[ -f "$F/auto/failed/$BUILD_PLAN.md" ]]'
check "3c. ...and the verify pass was skipped, as a failed build always skips it" '[[ -f "$F/verify/incomplete/$VERIFY_PLAN.md" ]]'

echo
if (( fails > 0 )); then echo "batch-sigpipe: $fails assertion(s) FAILED"; exit 1; fi
echo "batch-sigpipe: all assertions passed"
