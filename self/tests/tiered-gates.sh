#!/usr/bin/env bash
set -uo pipefail

# Self-test for the red-gate tier ladder (RUNNER.md → "Red gates: the tier ladder").
# Run by self/gate.sh, or by hand: bash self/tests/tiered-gates.sh
#
# Same scaffolding as level-sentinel.sh — a throwaway checkout, a stub `claude`, a stub
# gate — with two additions: the gate's verdict comes from a FILE the stub claude can
# flip to green (so "the fix session fixed it" is observable), and the stub records the
# flags it was called with (so the per-plan budget is observable).
#
# Asserts, in order:
#   1. tier 1 flips the gate green → no escalation written, build resumes, batch exits 0;
#      the level-verify ran under LEVEL_VERIFY_BUDGET_USD and its prompt carried the
#      tier-1 charge;
#   2. tier 1 leaves it red → NN-escalation-opus is synthesized into verify/, runs under
#      ESCALATION_BUDGET_USD with the escalation preamble, flips green → batch exits 0;
#   3. red after both tiers → batch exits 1 and a re-run does not synthesize a second
#      escalation;
#   4. a resumed batch settles a crossed-but-unsettled level BEFORE building on it;
#   5. run-review.sh opens the PR when the budget cap fires after the report was written,
#      and still exits non-zero.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
AT="$TMP/agentTooling"
mkdir -p "$AT/self/features" "$TMP/bin"
for f in run-plans.sh run-verify.sh run-review.sh run-batch.sh run-escalation-plan.sh plan-runner-lib.sh plan-runner-roots.sh; do
  cp "$HERE/$f" "$AT/$f"
done
VERDICT="$AT/self/verdict.txt"
CALLS="$TMP/claude-calls.log"

# Stub claude. Records its argv (one line per call) and the prompt's first line, then
# emits one result event. CLAUDE_STUB_FIX_AT=tier1|tier2 makes it flip the gate verdict
# green when it is running that tier (recognised from the prompt's opening words).
# CLAUDE_STUB_BUDGET_CAP=1 makes it report budget exhaustion after writing the review
# report named in CLAUDE_STUB_REPORT.
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
prompt="${@: -1}"
first="${prompt%%$'\n'*}"
plan_line="$(grep -m1 '^- Plan:' <<<"$prompt")"
printf '%s\t%s\t%s\n' "${*:1:$#-1}" "$plan_line" "$first" >> "$CLAUDE_STUB_CALLS"
case "$first" in
  *"LEVEL-VERIFY"*|*"VERIFY plan"*) tier=tier1 ;;
  *"ESCALATION plan"*) tier=tier2 ;;
  *) tier=other ;;
esac
# The tier-1 charge lives further down the verify prompt; detect it anywhere.
if [[ "$prompt" == *"THIS IS A LEVEL-VERIFY"* ]]; then tier=tier1; echo "tier1-charge:$plan_line" >> "$CLAUDE_STUB_CALLS"; fi
if [[ "${CLAUDE_STUB_FIX_AT:-}" == "$tier" ]]; then echo "all checks passed" > "$CLAUDE_STUB_VERDICT"; fi
if [[ -n "${CLAUDE_STUB_REPORT:-}" ]]; then echo "# verdict: no findings" > "$CLAUDE_STUB_REPORT"; fi
if [[ "${CLAUDE_STUB_BUDGET_CAP:-0}" == 1 ]]; then
  printf '{"type":"result","subtype":"error_max_budget_usd","is_error":true,"total_cost_usd":7,"num_turns":9,"session_id":"stub","usage":{}}\n'
  exit 1
fi
printf '{"type":"result","subtype":"success","total_cost_usd":0,"num_turns":1,"session_id":"stub","usage":{}}\n'
exit 0
STUB
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"
export CLAUDE_STUB_CALLS="$CALLS" CLAUDE_STUB_VERDICT="$VERDICT"

cat > "$AT/self/gate.sh" <<'STUB'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT="$HERE/self/gate-report.txt"
verdict="$(cat "$HERE/self/verdict.txt" 2>/dev/null || echo "one or more checks FAILED")"
# A sentinel that hands the gate expectations makes this level green by construction.
if [[ -n "${GATE_EXPECTED_RED:-}" || -n "${GATE_DEFERRED:-}" ]]; then verdict="all checks passed"; fi
{ echo "# Gate report"; echo "level: ${1:-final}"; echo "expected-red: ${GATE_EXPECTED_RED:-}"; echo "deferred: ${GATE_DEFERRED:-}"; echo ""; echo "# VERDICT"; echo "$verdict"; } > "$REPORT"
if [[ -n "${1:-}" ]]; then cp "$REPORT" "${REPORT%.txt}.$1.txt"; fi
exit 0
STUB
chmod +x "$AT/self/gate.sh"
printf '#!/usr/bin/env bash\ntouch "$(dirname "$0")/pr-opened"\nexit 0\n' > "$AT/self/pr.sh"; chmod +x "$AT/self/pr.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

SLUG=tier
F="$AT/self/features/$SLUG"
reset_feature() {
  rm -rf "$F" "$AT"/self/gate-report*.txt "$VERDICT" "$AT/self/pr-opened" "$AT/self/review-report.md"
  : > "$CALLS"
  mkdir -p "$F/auto/incomplete" "$F/verify/incomplete" "$F/review/incomplete"
  echo '{"slug":"tier","plans":[],"branches":[]}' > "$F/README.md"
  echo "one or more checks FAILED" > "$VERDICT"
}
queue_levelled_batch() {
  echo "plan" > "$F/auto/incomplete/01-x-haiku.md"
  echo "# level 1" > "$F/auto/incomplete/05-gate.md"
  echo "plan" > "$F/auto/incomplete/06-y-haiku.md"
  echo "brief" > "$F/verify/incomplete/05-level-x-sonnet.md"
  echo "brief" > "$F/verify/incomplete/10-verify-sonnet.md"
}

# ── 1: tier 1 fixes it ───────────────────────────────────────────────────────
reset_feature; queue_levelled_batch
out="$(cd "$AT" && CLAUDE_STUB_FIX_AT=tier1 ./run-batch.sh --self "$SLUG" 2>&1)"; rc=$?
check "tier-1 fix: batch exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "tier-1 fix: reported green after tier 1" 'grep -q "green after tier 1" <<<"$out"'
check "tier-1 fix: no escalation plan written" '[[ -z "$(find "$F/verify" -name "05-escalation-*")" ]]'
check "tier-1 fix: build resumed" '[[ -f "$F/auto/complete/06-y-haiku.md" ]]'
check "level-verify ran with the level budget (6.00)" 'grep -q -- "--max-budget-usd 6.00.*THIS IS A LEVEL-VERIFY\|--max-budget-usd 6.00" <<<"$(grep "05-level-x" "$CALLS")"'
check "level-verify prompt carried the tier-1 charge" 'grep -q "^tier1-charge:.*05-level-x" "$CALLS"'
check "final verify prompt did NOT carry the tier-1 charge" '! grep -q "^tier1-charge:.*10-verify" "$CALLS"'
check "final verify ran with the verify budget (3.00)" 'grep "10-verify" "$CALLS" | grep -q -- "--max-budget-usd 3.00"'

# ── 2: tier 1 fails, tier 2 fixes it ────────────────────────────────────────
reset_feature; queue_levelled_batch
out="$(cd "$AT" && CLAUDE_STUB_FIX_AT=tier2 ./run-batch.sh --self "$SLUG" 2>&1)"; rc=$?
check "tier-2 fix: batch exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "tier-2 fix: escalation plan synthesized and completed" '[[ -f "$F/verify/complete/05-escalation-opus.md" && -f "$F/verify/complete/05-escalation-opus.usage.json" ]]'
check "tier-2 fix: escalation brief names the manifest and the note" 'grep -q "self/features/tier/README.md" "$F/verify/complete/05-escalation-opus.md" && grep -q "escalations/05.md" "$F/verify/complete/05-escalation-opus.md"'
check "escalation ran on opus with the escalation budget (8.00)" 'grep "05-escalation" "$CALLS" | grep -q -- "--model opus.*--max-budget-usd 8.00"'
check "escalation prompt used the escalation preamble" 'grep "05-escalation" "$CALLS" | grep -q "ESCALATION plan"'
check "tier-2 fix: reported green after tier 2" 'grep -q "green after tier 2" <<<"$out"'
check "tier-2 fix: build resumed" '[[ -f "$F/auto/complete/06-y-haiku.md" ]]'

# ── 3: red after both tiers → stop; re-run does not escalate twice ──────────
reset_feature; queue_levelled_batch
out="$(cd "$AT" && ./run-batch.sh --self "$SLUG" 2>&1)"; rc=$?
check "tier 3: batch exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "tier 3: reported" 'grep -q "tier 3: still red" <<<"$out"'
check "tier 3: next level NOT built" '[[ -f "$F/auto/incomplete/06-y-haiku.md" ]]'
n_before="$(wc -l < "$CALLS")"
out="$(cd "$AT" && ./run-batch.sh --self "$SLUG" 2>&1)"; rc=$?
check "re-run: still exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "re-run: did not buy a second escalation" 'grep -q "not buying it twice" <<<"$out" && [[ "$(wc -l < "$CALLS")" -eq "$n_before" ]]'
check "re-run: run-escalation-plan refuses a duplicate" '! (cd "$AT" && ./run-escalation-plan.sh --self "$SLUG" 05 >/dev/null 2>&1)'

# ── 4: resume settles the crossed level before building ─────────────────────
reset_feature
mkdir -p "$F/auto/complete"
echo "# level 1" > "$F/auto/complete/05-gate.md"          # crossed on a previous run
echo "plan" > "$F/auto/incomplete/06-y-haiku.md"           # next level still queued
echo "brief" > "$F/verify/incomplete/05-level-x-sonnet.md" # level-verify never ran
out="$(cd "$AT" && CLAUDE_STUB_FIX_AT=tier1 ./run-batch.sh --self "$SLUG" 2>&1)"; rc=$?
check "resume: batch exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "resume: settled the level first" 'grep -q "resuming — level 05 was crossed but is not settled" <<<"$out"'
check "resume: level-verify ran before the next build plan" '[[ "$(grep -n "05-level-x\|06-y-haiku" "$CALLS" | head -1)" == *05-level-x* ]]'

# ── 4b: sentinel expectations reach the gate and are scoped to that level ──────
reset_feature
printf '# level 1\nexpected-red: tests/test_acceptance_x.py tests/test_api_*.py\ndefer: npm run typecheck, npm run build\n' > "$F/auto/incomplete/05-gate.md"
echo "plan" > "$F/auto/incomplete/06-y-haiku.md"
echo "brief" > "$F/verify/incomplete/05-level-x-sonnet.md"
out="$(cd "$AT" && ./run-batch.sh --self "$SLUG" 2>&1)"; rc=$?
check "expectations: gate saw expected-red globs" 'grep -q "^expected-red: tests/test_acceptance_x.py tests/test_api_\*.py$" "$AT/self/gate-report.05.txt"'
check "expectations: gate saw deferred labels" 'grep -q "^deferred: npm run typecheck, npm run build$" "$AT/self/gate-report.05.txt"'
check "expectations: level green → no tier ran, batch exits 0 (got $rc)" '[[ $rc -eq 0 && -f "$F/verify/complete/05-level-x-sonnet.md" ]] && ! grep -q "tier 1" <<<"$out"'
check "expectations: final gate saw none" 'grep -q "^expected-red: $" "$AT/self/gate-report.txt" && grep -q "^level: final" "$AT/self/gate-report.txt"'

# ── 5: review capped after writing its report still opens the PR ───────────
reset_feature
echo "brief" > "$F/review/incomplete/11-review-opus.md"
out="$(cd "$AT" && CLAUDE_STUB_BUDGET_CAP=1 CLAUDE_STUB_REPORT="$AT/self/review-report.md" ./run-review.sh --self "$SLUG" 2>&1)"; rc=$?
check "capped review: exits non-zero (got $rc)" '[[ $rc -ne 0 ]]'
check "capped review: plan filed to failed/" '[[ -f "$F/review/failed/11-review-opus.md" ]]'
check "capped review: PR opened" '[[ -f "$AT/self/pr-opened" ]]'
check "capped review: report carries the cap banner" 'grep -q "reached its budget cap" "$AT/self/review-report.md"'
rm -f "$AT/self/pr-opened" "$AT/self/review-report.md"
reset_feature
echo "brief" > "$F/review/incomplete/11-review-opus.md"
out="$(cd "$AT" && CLAUDE_STUB_BUDGET_CAP=1 ./run-review.sh --self "$SLUG" 2>&1)"; rc=$?
check "capped review with NO report: no PR" '[[ ! -f "$AT/self/pr-opened" ]]'

if (( fails > 0 )); then echo "tiered-gates: $fails assertion(s) FAILED"; exit 1; fi
echo "tiered-gates: all assertions passed"
