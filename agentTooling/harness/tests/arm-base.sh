#!/usr/bin/env bash
set -uo pipefail

# Base arms (experiment.json base_arms): lib.sh's arm-kind helpers on hand-written
# experiment.json files, and scorecard.py's base-arm rendering on a hand-built ledger.
#
#   harness/tests/arm-base.sh
#
# No network, no money, no repo: a `mktemp -d` directory, removed on exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCORECARD="$HARNESS_DIR/scorecard.py"

# The experiment
EXPERIMENT_NAME="scorecardBaseArms"
FIXTURE="f"
METHOD_A="a"
METHOD_B="b"
ARM_OLD="old"
ARM_NEW="new"
ARM_BEFORE="before"
SHA_OLD="3333333333333333333333333333333333333333"
SHA_NEW="4444444444444444444444444444444444444444"
NOISE_BAND_PCT=15
MALFORMED_BASE_ARMS="abc"

# The ledger: dollars to PR-open and to green per row (as scorecard-arms.sh).
A_OLD_OPEN="10.00"; A_OLD_GREEN="12.00"
A_NEW_OPEN="10.50"; A_NEW_GREEN="12.60"
B_OLD_OPEN="20.00"; B_OLD_GREEN="24.00"
B_NEW_OPEN="10.00"; B_NEW_GREEN="12.00"

# What lib.sh and scorecard.py print
MSG_EXCLUSIVE="never both"
MSG_MALFORMED_RE="base_arms in .* must be an object of <label>: <full sha>"
NO_ARMS_LINE="- -"
KIND_BASE="base"
KIND_AGENT_TOOLING="agent_tooling"
HEADER_BASE_ARMS="base arms: $ARM_OLD=${SHA_OLD:0:7}, $ARM_NEW=${SHA_NEW:0:7}"
HEADER_AT_ARMS="agentTooling arms:"
LABEL_NEW="$ARM_NEW (base ${SHA_NEW:0:7})"
LABEL_OLD="$ARM_OLD (base ${SHA_OLD:0:7})"
ARM_PAIR_A="**$FIXTURE · $METHOD_A**: arm $ARM_NEW vs arm $ARM_OLD"
ARM_PAIR_B="**$FIXTURE · $METHOD_B**: arm $ARM_NEW vs arm $ARM_OLD"
METHOD_PAIR_OLD="**$FIXTURE · arm $ARM_OLD**: $METHOD_A vs $METHOD_B"
METHOD_PAIR_NEW="**$FIXTURE · arm $ARM_NEW**: $METHOD_A vs $METHOD_B"
WHAT_OPEN="to PR-open"
WHAT_GREEN="to green"
VERDICT_TIE="tie inside the band"
VERDICT_OUTSIDE="outside the band"
COMPARISON_LINE_PREFIX="- **$FIXTURE · "
EXPECTED_COMPARISONS=4
EXPECTED_TIES=2
EXPECTED_OUTSIDES=2
READING_HEADING="## Reading before the first edit"

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
check() { if eval "$2"; then pass "$1"; else fail "$1 — [$2]"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/arm-base.XXXXXX")"
[[ -n "$WORK" && -d "$WORK" ]] || { echo "could not make a work directory" >&2; exit 1; }
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

lib_call() { ( source "$HARNESS_DIR/lib.sh"; "$@" ) 2>&1; }

# ── lib.sh: the arm-kind helpers ─────────────────────────────────────────────
echo "=== arm-base: lib.sh helpers ==="
NONE_JSON="$WORK/none.json"
AT_JSON="$WORK/at.json"
BASE_JSON="$WORK/base.json"
BOTH_JSON="$WORK/both.json"
BAD_JSON="$WORK/bad.json"

jq -n '{name: "x"}' > "$NONE_JSON"
jq -n --arg s "$SHA_OLD" --arg a "$ARM_BEFORE" '{name: "x", agent_tooling: {($a): $s}}' > "$AT_JSON"
jq -n --arg o "$SHA_OLD" --arg n "$SHA_NEW" --arg ao "$ARM_OLD" --arg an "$ARM_NEW" \
  '{name: "x", base_arms: {($ao): $o, ($an): $n}}' > "$BASE_JSON"
jq -n --arg o "$SHA_OLD" --arg n "$SHA_NEW" --arg ao "$ARM_OLD" --arg an "$ARM_NEW" --arg b "$ARM_BEFORE" \
  '{name: "x", agent_tooling: {($b): $o}, base_arms: {($ao): $o, ($an): $n}}' > "$BOTH_JSON"
jq -n --arg m "$MALFORMED_BASE_ARMS" '{name: "x", base_arms: $m}' > "$BAD_JSON"

check "no arm key: kind prints nothing" "[[ -z \"\$(lib_call harness_experiment_arm_kind '$NONE_JSON')\" ]]"
check "no arm key: arms prints '$NO_ARMS_LINE'" "[[ \"\$(lib_call harness_experiment_arms '$NONE_JSON')\" == '$NO_ARMS_LINE' ]]"
check "agent_tooling: kind $KIND_AGENT_TOOLING" "[[ \"\$(lib_call harness_experiment_arm_kind '$AT_JSON')\" == '$KIND_AGENT_TOOLING' ]]"
check "agent_tooling: arms line '$ARM_BEFORE $SHA_OLD'" "[[ \"\$(lib_call harness_experiment_arms '$AT_JSON')\" == '$ARM_BEFORE $SHA_OLD' ]]"
check "base_arms: kind $KIND_BASE" "[[ \"\$(lib_call harness_experiment_arm_kind '$BASE_JSON')\" == '$KIND_BASE' ]]"
check "base_arms: arms lines in order" \
  "[[ \"\$(lib_call harness_experiment_arms '$BASE_JSON')\" == \$'$ARM_OLD $SHA_OLD\n$ARM_NEW $SHA_NEW' ]]"

out="$(lib_call harness_experiment_arm_kind "$BOTH_JSON")"; rc=$?
check "both keys: arm_kind exits non-zero saying '$MSG_EXCLUSIVE'" "(( $rc != 0 )) && grep -qF '$MSG_EXCLUSIVE' <<<\"\$out\""
out="$(lib_call harness_experiment_arms "$BOTH_JSON")"; rc=$?
check "both keys: arms exits non-zero saying '$MSG_EXCLUSIVE'" "(( $rc != 0 )) && grep -qF '$MSG_EXCLUSIVE' <<<\"\$out\""
out="$(lib_call harness_experiment_arms "$BAD_JSON")"; rc=$?
check "malformed base_arms: arms exits non-zero with the shape message" "(( $rc != 0 )) && grep -qE '$MSG_MALFORMED_RE' <<<\"\$out\""

# ── scorecard.py: base-arm rendering ─────────────────────────────────────────
echo ""
echo "=== arm-base: scorecard ==="
SC_DIR="$WORK/sc"
mkdir -p "$SC_DIR"
SC_RESULTS="$SC_DIR/results.jsonl"
SC_MD="$SC_DIR/SCORECARD.md"

jq -n --arg name "$EXPERIMENT_NAME" --arg f "$FIXTURE" --arg a "$METHOD_A" --arg b "$METHOD_B" \
  --argjson band "$NOISE_BAND_PCT" --arg ao "$ARM_OLD" --arg an "$ARM_NEW" \
  --arg so "$SHA_OLD" --arg sn "$SHA_NEW" \
  '{name: $name, fixtures: [$f], methods: [$a, $b], repeats: 1, noise_band_pct: $band,
    base_arms: {($ao): $so, ($an): $sn},
    prediction: "the scorecard labels base arms and compares them"}' > "$SC_DIR/experiment.json"

row() {
  # row <method> <arm> <sha> <to PR-open> <to green>
  jq -nc --arg f "$FIXTURE" --arg m "$1" --arg arm "$2" --arg sha "$3" \
    --argjson open "$4" --argjson green "$5" \
    '{fixture: $f, method: $m, repeat: 1, arm: $arm, arm_kind: "base", base: $sha, agent_tooling: "",
      branch: ($f + $m + $arm), cost_method_usd: $open, cost_green_usd: $green, accept_pass: true}'
}
{
  row "$METHOD_A" "$ARM_OLD" "$SHA_OLD" "$A_OLD_OPEN" "$A_OLD_GREEN"
  row "$METHOD_A" "$ARM_NEW" "$SHA_NEW" "$A_NEW_OPEN" "$A_NEW_GREEN"
  row "$METHOD_B" "$ARM_OLD" "$SHA_OLD" "$B_OLD_OPEN" "$B_OLD_GREEN"
  row "$METHOD_B" "$ARM_NEW" "$SHA_NEW" "$B_NEW_OPEN" "$B_NEW_GREEN"
} > "$SC_RESULTS"

python3 "$SCORECARD" "$SC_DIR" > "$SC_DIR/stdout.txt" 2>&1
render_rc=$?

comparison_lines() { grep -F -e "$COMPARISON_LINE_PREFIX" "$SC_MD"; }
line_for() { comparison_lines | grep -F -e "$1"; }

check "scorecard.py renders" "(( $render_rc == 0 )) && [[ -s '$SC_MD' ]]"
check "the header lists the base arms" "grep -qF '$HEADER_BASE_ARMS' '$SC_MD' && ! grep -qF '$HEADER_AT_ARMS' '$SC_MD'"
check "the runs table labels each base arm" "grep -qF '$LABEL_NEW' '$SC_MD' && grep -qF '$LABEL_OLD' '$SC_MD'"
for pair in "$ARM_PAIR_A" "$ARM_PAIR_B" "$METHOD_PAIR_OLD" "$METHOD_PAIR_NEW"; do
  check "the line '$pair' shows $WHAT_OPEN and $WHAT_GREEN" \
    "line_for '$pair' | grep -qF '$WHAT_OPEN' && line_for '$pair' | grep -qF '$WHAT_GREEN'"
done
check "exactly $EXPECTED_COMPARISONS comparison lines: $EXPECTED_TIES ties, $EXPECTED_OUTSIDES outside the band" \
  "[[ \$(comparison_lines | wc -l) -eq $EXPECTED_COMPARISONS ]] && [[ \$(comparison_lines | grep -cF '$VERDICT_OUTSIDE') -eq $EXPECTED_OUTSIDES ]] && [[ \$(comparison_lines | grep -F '$VERDICT_TIE' | grep -vF '$VERDICT_OUTSIDE' | grep -c .) -eq $EXPECTED_TIES ]] && [[ \$(comparison_lines | grep -oF '$VERDICT_TIE' | wc -l) -eq $(( EXPECTED_TIES * 2 )) ]]"
check "no reading section when the rows carry no reading fields" "! grep -qF '$READING_HEADING' '$SC_MD'"

echo ""
if (( failures > 0 )); then
  echo "=== arm-base: $failures check(s) FAILED ==="
  exit 1
fi
echo "=== arm-base: all checks passed ==="
