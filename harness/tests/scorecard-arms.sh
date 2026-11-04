#!/usr/bin/env bash
set -uo pipefail

# The scorecard's arm-aware comparisons, driven through scorecard.py on a hand-built
# ledger. smoke.sh's experiment has one arm and one method, so neither comparison loop in
# scorecard.py's render() ever produced a line there; this test is where they do.
#
#   harness/tests/scorecard-arms.sh
#
# Four rows — fixture f, methods a and b, arms before and after — priced so that two
# comparisons fall inside the ±15% band and two outside it. Then a fifth row with no arm
# (a run with no agentTooling pin): it is never paired with a pinned row.
#
# No network, no money, no repo: a `mktemp -d` directory holding an experiment.json and a
# results.jsonl, removed on exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCORECARD="$(cd "$SCRIPT_DIR/.." && pwd)/scorecard.py"

# The experiment
EXPERIMENT_NAME="scorecardArms"
FIXTURE="f"
METHOD_A="a"
METHOD_B="b"
ARM_BEFORE="before"
ARM_AFTER="after"
SHA_BEFORE="1111111111111111111111111111111111111111"
SHA_AFTER="2222222222222222222222222222222222222222"
NOISE_BAND_PCT=15

# The ledger: dollars to PR-open (cost_method_usd) and to green (cost_green_usd) per row.
# a: after is 5% under before (inside the band); b: before costs double after (outside).
# Within arm before, b costs double a (outside); within arm after, b is 5% under a (inside).
A_BEFORE_OPEN="10.00"; A_BEFORE_GREEN="12.00"
A_AFTER_OPEN="10.50";  A_AFTER_GREEN="12.60"
B_BEFORE_OPEN="20.00"; B_BEFORE_GREEN="24.00"
B_AFTER_OPEN="10.00";  B_AFTER_GREEN="12.00"
# The unpinned row is priced next to the pinned a rows, so a wrong pairing would show.
UNPINNED_OPEN="10.20"; UNPINNED_GREEN="12.30"

# What scorecard.py prints (render() / compare()): the bold label, then "<left> vs <right>".
ARM_PAIR_A="**$FIXTURE · $METHOD_A**: arm $ARM_AFTER vs arm $ARM_BEFORE"
ARM_PAIR_B="**$FIXTURE · $METHOD_B**: arm $ARM_AFTER vs arm $ARM_BEFORE"
METHOD_PAIR_BEFORE="**$FIXTURE · arm $ARM_BEFORE**: $METHOD_A vs $METHOD_B"
METHOD_PAIR_AFTER="**$FIXTURE · arm $ARM_AFTER**: $METHOD_A vs $METHOD_B"
WHAT_OPEN="to PR-open"
WHAT_GREEN="to green"
VERDICT_TIE="tie inside the band"
VERDICT_OUTSIDE="outside the band"
COMPARISON_LINE_PREFIX="- **$FIXTURE · "
EXPECTED_COMPARISONS=4

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
check() { if eval "$2"; then pass "$1"; else fail "$1 — [$2]"; fi; }

# An explicit template, as in smoke.sh: GNU mktemp refuses `-t <prefix>` with no X's.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scorecard-arms.XXXXXX")"
[[ -n "$WORK" && -d "$WORK" ]] || { echo "could not make a work directory" >&2; exit 1; }
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

EXPERIMENT_JSON="$WORK/experiment.json"
RESULTS="$WORK/results.jsonl"
SCORECARD_MD="$WORK/SCORECARD.md"

cat > "$EXPERIMENT_JSON" <<EXPERIMENT
{
  "name": "$EXPERIMENT_NAME",
  "fixtures": ["$FIXTURE"],
  "methods": ["$METHOD_A", "$METHOD_B"],
  "repeats": 1,
  "noise_band_pct": $NOISE_BAND_PCT,
  "agent_tooling": {"$ARM_BEFORE": "$SHA_BEFORE", "$ARM_AFTER": "$SHA_AFTER"},
  "prediction": "the scorecard compares arms against arms and methods within an arm"
}
EXPERIMENT

row() {
  # row <method> <arm> <agent_tooling sha> <to PR-open> <to green>
  printf '{"fixture":"%s","method":"%s","repeat":1,"arm":"%s","agent_tooling":"%s","branch":"%s%s%s","cost_method_usd":%s,"cost_green_usd":%s}\n' \
    "$FIXTURE" "$1" "$2" "$3" "$FIXTURE" "$1" "$2" "$4" "$5"
}

# The comparison lines of the rendered scorecard, one per line.
# (-e: the prefix starts with "- ", which grep would otherwise read as an option.)
comparison_lines() { grep -F -e "$COMPARISON_LINE_PREFIX" "$SCORECARD_MD"; }
line_for() { comparison_lines | grep -F -e "$1"; }

render() {
  python3 "$SCORECARD" "$WORK" > "$WORK/scorecard-stdout.txt" 2>&1
}

# ── Four rows: both comparison loops produce lines ───────────────────────────
echo "=== scorecard-arms: four rows ==="
{
  row "$METHOD_A" "$ARM_BEFORE" "$SHA_BEFORE" "$A_BEFORE_OPEN" "$A_BEFORE_GREEN"
  row "$METHOD_A" "$ARM_AFTER"  "$SHA_AFTER"  "$A_AFTER_OPEN"  "$A_AFTER_GREEN"
  row "$METHOD_B" "$ARM_BEFORE" "$SHA_BEFORE" "$B_BEFORE_OPEN" "$B_BEFORE_GREEN"
  row "$METHOD_B" "$ARM_AFTER"  "$SHA_AFTER"  "$B_AFTER_OPEN"  "$B_AFTER_GREEN"
} > "$RESULTS"
render
check "scorecard.py renders" "(( $? == 0 )) && [[ -s '$SCORECARD_MD' ]]"
check "the header names both arms with their abbreviated commits" \
  "grep -q 'agentTooling arms: $ARM_BEFORE=${SHA_BEFORE:0:7}, $ARM_AFTER=${SHA_AFTER:0:7}' '$SCORECARD_MD'"
check "the runs table carries each row's arm" \
  "grep -q '$ARM_BEFORE (${SHA_BEFORE:0:7})' '$SCORECARD_MD' && grep -q '$ARM_AFTER (${SHA_AFTER:0:7})' '$SCORECARD_MD'"
check "exactly $EXPECTED_COMPARISONS comparison lines (two arm pairs, two method pairs)" \
  "[[ \$(comparison_lines | wc -l) -eq $EXPECTED_COMPARISONS ]]"

check "an arm-vs-arm line exists for method $METHOD_A" "line_for '$ARM_PAIR_A' >/dev/null"
check "an arm-vs-arm line exists for method $METHOD_B" "line_for '$ARM_PAIR_B' >/dev/null"
check "a method-vs-method line exists within arm $ARM_BEFORE" "line_for '$METHOD_PAIR_BEFORE' >/dev/null"
check "a method-vs-method line exists within arm $ARM_AFTER" "line_for '$METHOD_PAIR_AFTER' >/dev/null"
for pair in "$ARM_PAIR_A" "$ARM_PAIR_B" "$METHOD_PAIR_BEFORE" "$METHOD_PAIR_AFTER"; do
  check "the line '$pair' shows both $WHAT_OPEN and $WHAT_GREEN" \
    "line_for '$pair' | grep -qF '$WHAT_OPEN' && line_for '$pair' | grep -qF '$WHAT_GREEN'"
done

# The arm is the left-hand side only because the arms sort as after < before; the figures
# are (right - left) / left, with the left's mean first.
check "arm after vs arm before ($METHOD_A): inside the band reads \"$VERDICT_TIE\" on both figures" \
  "[[ \$(line_for '$ARM_PAIR_A' | grep -oF '$VERDICT_TIE' | wc -l) -eq 2 ]]"
check "... and shows the dollars: \$$A_AFTER_OPEN vs \$$A_BEFORE_OPEN to PR-open" \
  "line_for '$ARM_PAIR_A' | grep -qF '$WHAT_OPEN \$$A_AFTER_OPEN vs \$$A_BEFORE_OPEN (-5%, $VERDICT_TIE)'"
check "... and \$$A_AFTER_GREEN vs \$$A_BEFORE_GREEN to green" \
  "line_for '$ARM_PAIR_A' | grep -qF '$WHAT_GREEN \$$A_AFTER_GREEN vs \$$A_BEFORE_GREEN (-5%, $VERDICT_TIE)'"
check "arm after vs arm before ($METHOD_B): outside the band names the dearer arm, never a tie" \
  "line_for '$ARM_PAIR_B' | grep -qF 'arm $ARM_BEFORE dearer, $VERDICT_OUTSIDE' && ! line_for '$ARM_PAIR_B' | grep -qF '$VERDICT_TIE'"
check "$METHOD_A vs $METHOD_B within arm $ARM_BEFORE: outside the band" \
  "line_for '$METHOD_PAIR_BEFORE' | grep -qF '$METHOD_B dearer, $VERDICT_OUTSIDE' && ! line_for '$METHOD_PAIR_BEFORE' | grep -qF '$VERDICT_TIE'"
check "$METHOD_A vs $METHOD_B within arm $ARM_AFTER: inside the band reads \"$VERDICT_TIE\" on both figures" \
  "[[ \$(line_for '$METHOD_PAIR_AFTER' | grep -oF '$VERDICT_TIE' | wc -l) -eq 2 ]]"

# ── A fifth row, with no arm ─────────────────────────────────────────────────
echo ""
echo "=== scorecard-arms: an unpinned row ==="
row "$METHOD_A" "" "" "$UNPINNED_OPEN" "$UNPINNED_GREEN" >> "$RESULTS"
render
check "scorecard.py still renders" "(( $? == 0 ))"
check "the unpinned row is in the runs table (five rows)" \
  "[[ \$(grep -c '^| $FIXTURE | ' '$SCORECARD_MD') -eq 5 ]]"
check "... and gained no comparison line (still $EXPECTED_COMPARISONS)" \
  "[[ \$(comparison_lines | wc -l) -eq $EXPECTED_COMPARISONS ]]"
check "... no comparison line carries its figures (\$$UNPINNED_OPEN, \$$UNPINNED_GREEN)" \
  "! comparison_lines | grep -qF -e '\$$UNPINNED_OPEN' -e '\$$UNPINNED_GREEN'"
check "... none pairs an empty arm against $ARM_BEFORE or $ARM_AFTER" \
  "! comparison_lines | grep -qE 'arm  vs|vs arm  |arm vs|vs arm —'"
check "... the four pinned comparison lines are unchanged" \
  "line_for '$ARM_PAIR_A' >/dev/null && line_for '$ARM_PAIR_B' >/dev/null && line_for '$METHOD_PAIR_BEFORE' >/dev/null && line_for '$METHOD_PAIR_AFTER' >/dev/null"

echo ""
if (( failures > 0 )); then
  echo "=== scorecard-arms: $failures check(s) FAILED ==="
  exit 1
fi
echo "=== scorecard-arms: all checks passed ==="
