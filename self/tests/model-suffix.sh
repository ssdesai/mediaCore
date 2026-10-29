#!/usr/bin/env bash
set -uo pipefail

# Self-test for the plan-filename model suffix (self/features/fable-plan-model/README.md).
# Run by self/gate.sh, or by hand: bash self/tests/model-suffix.sh
#
# A plan, verify or review file is NN-description-MODEL.md with MODEL one of haiku,
# sonnet, opus, fable. The four are spelled in three places — check-plans.sh's MODEL_RE
# (covered by check-plans.sh 8d/8e), plan-runner-lib.sh's extract_model and
# analysis/manifest.py's PLAN_STEM_RE — and this test covers the other two, plus the
# price a fable transcript is billed at. Copies plan-runner-lib.sh and analysis/manifest.py
# with what it imports (routing, pricing, roots, transcript; rates_history.json and
# litellm_prices.py beside pricing) into a mktemp -d, with RATES_LIVE_LOOKUP=off and HOME
# redirected. No model, no network.
#
# Asserts:
#   M1. extract_model passes each of the four suffixes through as-is — the CLI alias
#       `claude --model` is given — with no WARN on stderr;
#   M2. an unknown suffix (gpt) and a suffix-less stem fall back to sonnet with a WARN;
#   M3. manifest.py set-plans accepts a NN-review-fable stem and writes it to plans[];
#   M4. it still refuses an unknown suffix, naming the stem, and leaves plans[] alone;
#   M5. pricing prices claude-fable-5-1 — the id a `--model fable` transcript carries —
#       from the history (not live), at the history's rates.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features" "$AT/.git" "$TMP/home"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
export HOME="$TMP/home"

cp "$HERE/plan-runner-lib.sh" "$AT/plan-runner-lib.sh"
# manifest.py imports routing, which imports pricing, roots and transcript; pricing loads
# rates_history.json from beside itself.
ANALYSIS_FILES=(pricing.py litellm_prices.py rates_history.json roots.py transcript.py routing.py manifest.py)
for f in "${ANALYSIS_FILES[@]}"; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# The fable model id the CLI's alias resolves to, and its rates in the history
FABLE_MODEL_ID="claude-fable-5-1"
FABLE_AS_OF="2026-10-28"

echo "model-suffix"

# ── M1/M2. extract_model ───────────────────────────────────────────────────────
PLAN_KIND=plan
# shellcheck source=/dev/null
source "$AT/plan-runner-lib.sh"

for m in haiku sonnet opus fable; do
  got="$(extract_model "$TMP/01-review-$m.md" 2>"$TMP/err")"
  check "M1. extract_model 01-review-$m.md -> $m, no warning (got $got)" \
    '[[ "$got" == "$m" && ! -s "$TMP/err" ]]'
done
for stem in 01-review-gpt 01-review; do
  got="$(extract_model "$TMP/$stem.md" 2>"$TMP/err")"
  check "M2. extract_model $stem.md -> sonnet with a WARN (got $got)" \
    '[[ "$got" == "sonnet" ]] && grep -q "^WARN: $stem.md has no recognized model suffix" "$TMP/err"'
done

# ── M3/M4. manifest.py set-plans / PLAN_STEM_RE ────────────────────────────────
SLUG="fable-probe"
FEAT="$AT/self/features/$SLUG"
mkdir -p "$FEAT"
{
  echo "# $SLUG"
  echo ""
  echo '```json'
  printf '{"slug": "%s", "plans": [], "branches": ["%s"], "session_window": {"from": "2026-10-28T00:00:00Z", "to": null}, "method": "hand"}\n' "$SLUG" "$SLUG"
  echo '```'
} > "$FEAT/README.md"

out="$(python3 -B "$AT/analysis/manifest.py" --self "$SLUG" set-plans 01-review-fable 2>&1)"; rc=$?
check "M3. set-plans 01-review-fable: exit 0 and plans[] written (got $rc: $out)" \
  '[[ $rc -eq 0 ]] && grep -q "\"01-review-fable\"" "$FEAT/README.md"'

out="$(python3 -B "$AT/analysis/manifest.py" --self "$SLUG" set-plans 02-review-gpt 2>&1)"; rc=$?
check "M4. set-plans 02-review-gpt: refused naming the stem, plans[] unchanged (got $rc)" \
  '[[ $rc -ne 0 ]] && grep -q "not a plan stem.*02-review-gpt" <<<"$out" && ! grep -q "02-review-gpt" "$FEAT/README.md"'

# ── M5. pricing ────────────────────────────────────────────────────────────────
cat > "$TMP/price.py" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
import json
import pricing
model, as_of = sys.argv[2], sys.argv[3]
tokens = {"input": 1_000_000, "output": 1_000_000}
cost, rates = pricing.compute_cost(model, tokens, as_of)
entry = pricing.load_history()["models"][model][-1]
expected = entry["input"] + entry["output"]
priced = cost is not None and not pricing.is_live(rates) and abs(cost - expected) < 1e-9
print(json.dumps({"cost": cost, "expected": expected, "priced": priced}))
PYEOF
res="$(python3 -B "$TMP/price.py" "$AT/analysis" "$FABLE_MODEL_ID" "$FABLE_AS_OF" 2>&1)"
check "M5. $FABLE_MODEL_ID priced from the history at its rates ($res)" \
  'grep -q "\"priced\": true" <<<"$res"'

echo
if [[ $fails -eq 0 ]]; then
  echo "model-suffix: all checks passed"
  exit 0
fi
echo "model-suffix: $fails check(s) failed"
exit 1
