#!/usr/bin/env bash
set -uo pipefail

# Self-test for level sentinels (RUNNER.md → "Level sentinels"). Run by self/gate.sh as
# `record "level sentinel self-test" …`, or by hand: bash self/tests/level-sentinel.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d — the real runner scripts, a
# stub `claude` that succeeds instantly, a stub `self/gate.sh` whose verdict the test sets
# — and drives it with --self. Nothing here touches this checkout's own queue, gate
# report or PATH beyond the subshell. No model, no network; runs in a few seconds.
#
# Asserts, in order:
#   1. a sentinel is filed to auto/complete/ with NO progress/stream/usage sidecar, and
#      the gate ran with its number as the label (gate-report.NN.txt exists);
#   2. run-plans.sh exits LEVEL_PAUSE_RC (64) when a level-verify ≤ NN is queued and the
#      gate is red, and 0 when none is queued;
#   3. D3: with a green gate the queued level-verify is filed to verify/complete/ as
#      skipped and the run continues (exit 0);
#   4. run-verify.sh --up-to 08 drains 08 and leaves 09 queued (zero-padded numbers are
#      not read as octal);
#   5. a claude that exits 64 is reported as a failure (exit 1), never as a pause;
#   6. run-batch.sh resolves level_nn to the pausing sentinel, runs the level-verify, and —
#      the gate here is red forever — stops at tier 3 without building the next level.
#      The green-after-fix paths are tiered-gates.sh's.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
AT="$TMP/agentTooling"
mkdir -p "$AT/self/features" "$TMP/bin"
for f in run-plans.sh run-verify.sh run-review.sh run-batch.sh run-escalation-plan.sh plan-runner-lib.sh plan-runner-roots.sh; do
  cp "$HERE/$f" "$AT/$f"
done

# Stub claude: one result event, exit code from CLAUDE_STUB_RC (default 0).
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '{"type":"result","subtype":"success","total_cost_usd":0,"num_turns":1,"session_id":"stub","usage":{}}\n'
exit "${CLAUDE_STUB_RC:-0}"
STUB
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

# Stub gate: honours the label contract; verdict comes from GATE_STUB_VERDICT.
cat > "$AT/self/gate.sh" <<'STUB'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT="$HERE/self/gate-report.txt"
{ echo "# Gate report"; echo "level: ${1:-final}"; echo ""; echo "# VERDICT"; echo "${GATE_STUB_VERDICT:-all checks passed}"; } > "$REPORT"
if [[ -n "${1:-}" ]]; then cp "$REPORT" "${REPORT%.txt}.$1.txt"; fi
exit "${GATE_STUB_RC:-0}"
STUB
chmod +x "$AT/self/gate.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$AT/self/pr.sh"; chmod +x "$AT/self/pr.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

SLUG=lvl
F="$AT/self/features/$SLUG"
reset_feature() {
  rm -rf "$F" "$AT"/self/gate-report*.txt
  mkdir -p "$F/auto/incomplete" "$F/verify/incomplete" "$F/review/incomplete"
  echo '{"slug":"lvl","plans":[],"branches":[]}' > "$F/README.md"
}

# ── 1 + 2b: sentinel alone, with one build plan before it ────────────────────
reset_feature
echo "plan" > "$F/auto/incomplete/01-x-haiku.md"
echo "# level 1" > "$F/auto/incomplete/05-gate.md"
( cd "$AT" && ./run-plans.sh --self "$SLUG" >/dev/null 2>&1 ); rc=$?
check "sentinel-only run exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "05-gate.md filed to auto/complete/" '[[ -f "$F/auto/complete/05-gate.md" ]]'
check "sentinel has no sidecars" '[[ -z "$(find "$F" -name "05-gate.progress.md" -o -name "05-gate.stream.jsonl" -o -name "05-gate.usage.json")" ]]'
check "gate ran with label 05 (gate-report.05.txt)" '[[ -f "$AT/self/gate-report.05.txt" ]] && grep -q "^level: 05" "$AT/self/gate-report.05.txt"'
check "ordinary plan 01 still filed complete with usage" '[[ -f "$F/auto/complete/01-x-haiku.usage.json" ]]'

# ── 2a: red gate + queued level-verify → LEVEL_PAUSE_RC ───────────────────────
reset_feature
echo "# level 1" > "$F/auto/incomplete/05-gate.md"
echo "plan" > "$F/auto/incomplete/06-y-haiku.md"
echo "brief" > "$F/verify/incomplete/05-level-x-sonnet.md"
echo "brief" > "$F/verify/incomplete/10-verify-sonnet.md"
( cd "$AT" && GATE_STUB_VERDICT="one or more checks FAILED" ./run-plans.sh --self "$SLUG" >/dev/null 2>&1 ); rc=$?
check "red gate + level-verify queued exits 64 (got $rc)" '[[ $rc -eq 64 ]]'
check "pause leaves next build plan queued" '[[ -f "$F/auto/incomplete/06-y-haiku.md" ]]'
check "pause leaves level-verify queued" '[[ -f "$F/verify/incomplete/05-level-x-sonnet.md" ]]'

# ── 3: green gate + queued level-verify → skipped, continue ──────────────────
reset_feature
echo "# level 1" > "$F/auto/incomplete/05-gate.md"
echo "plan" > "$F/auto/incomplete/06-y-haiku.md"
echo "brief" > "$F/verify/incomplete/05-level-x-sonnet.md"
echo "brief" > "$F/verify/incomplete/10-verify-sonnet.md"
( cd "$AT" && GATE_STUB_VERDICT="all checks passed" ./run-plans.sh --self "$SLUG" >/dev/null 2>&1 ); rc=$?
check "green gate does not pause (exit 0, got $rc)" '[[ $rc -eq 0 ]]'
check "level-verify filed to verify/complete/ as skipped" '[[ -f "$F/verify/complete/05-level-x-sonnet.md" ]] && grep -q "^skipped: level 05" "$F/verify/complete/05-level-x-sonnet.progress.md"'
check "final verify (10) left queued" '[[ -f "$F/verify/incomplete/10-verify-sonnet.md" ]]'
check "build continued past the sentinel" '[[ -f "$F/auto/complete/06-y-haiku.md" ]]'

# ── 4: --up-to 08 includes 08, excludes 09 ───────────────────────────────────
reset_feature
echo "brief" > "$F/verify/incomplete/08-a-haiku.md"
echo "brief" > "$F/verify/incomplete/09-b-haiku.md"
( cd "$AT" && ./run-verify.sh --self --up-to 08 "$SLUG" >/dev/null 2>&1 ); rc=$?
check "--up-to 08 exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "--up-to 08 drained 08" '[[ -f "$F/verify/complete/08-a-haiku.md" ]]'
check "--up-to 08 left 09 queued" '[[ -f "$F/verify/incomplete/09-b-haiku.md" ]]'

# ── 5: claude exiting 64 is a failure, not a pause ───────────────────────────
reset_feature
echo "plan" > "$F/auto/incomplete/01-x-haiku.md"
( cd "$AT" && CLAUDE_STUB_RC=64 ./run-plans.sh --self "$SLUG" >/dev/null 2>&1 ); rc=$?
check "claude exit 64 is remapped to 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "that plan is in failed/" '[[ -f "$F/auto/failed/01-x-haiku.md" ]]'

# ── 6: run-batch resolves level_nn and completes ─────────────────────────────
reset_feature
echo "# level 1" > "$F/auto/incomplete/05-gate.md"
echo "plan" > "$F/auto/incomplete/06-y-haiku.md"
echo "brief" > "$F/verify/incomplete/05-level-x-sonnet.md"
echo "brief" > "$F/verify/incomplete/10-verify-sonnet.md"
out="$(cd "$AT" && GATE_STUB_VERDICT="one or more checks FAILED" ./run-batch.sh --self "$SLUG" 2>&1)"; rc=$?
check "run-batch on a red-forever gate exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "run-batch named level 05 for the level-verify" 'grep -q "level 05 — tier 1, the level-verify" <<<"$out"'
check "level-verify ran; final verify did not" '[[ -f "$F/verify/complete/05-level-x-sonnet.usage.json" && -f "$F/verify/incomplete/10-verify-sonnet.md" ]]'
check "escalation ran once" '[[ -f "$F/verify/complete/05-escalation-opus.usage.json" ]]'
check "build did NOT resume past a red level" '[[ -f "$F/auto/incomplete/06-y-haiku.md" ]]'

if (( fails > 0 )); then echo "level-sentinel: $fails assertion(s) FAILED"; exit 1; fi
echo "level-sentinel: all assertions passed"
