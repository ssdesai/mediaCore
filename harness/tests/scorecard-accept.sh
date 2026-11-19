#!/usr/bin/env bash
set -uo pipefail

# The scorecard's failed-run handling, its Per cell outcome columns and its Acceptance
# section, driven through scorecard.py on a hand-built ledger.
#
#   harness/tests/scorecard-accept.sh
#
# Rows (fixture f, base-arm-free, arms none): method a three times — two good ($10 and $12
# to PR-open, $12 and $14 to green, the second with $5 lost to a killed attempt) and one
# method_failed at $0, which is the discogsPrefillStructure shape that once turned a tie into
# "+54%, outside the band" — and method b twice ($11 and $11). Then a ledger with neither
# accept-at-PR-open fields nor check ids. No network, no money, no repo: a `mktemp -d`
# directory, removed on exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCORECARD="$(cd "$SCRIPT_DIR/.." && pwd)/scorecard.py"

FIXTURE="f"
METHOD_A="a"
METHOD_B="b"

# What the tables should print
A_CELL_ROW="| f | a | — | 3 | \$13.00 | \$2.00 | \$11.00 | 30m | 70m | 60m | 1 | \$31.00 |"
B_CELL_ROW="| f | b | — | 2 | \$12.00 | \$0.00 | \$11.00 | 30m | 70m | 60m | 0 | \$24.00 |"
A_FAILED_MEAN="\$8.67"          # what a mean over the failed row too would give to green
COMPARISON="to PR-open \$11.00 vs \$11.00 (+0%, tie inside the band)"
ACCEPT_HEADING="## Acceptance"
A_COUNTS="| f | a | — | 3 | 1/2 | 2/2 |"
B_COUNTS="| f | b | — | 2 | — | 1/2 |"
A1_CHECKS="| \`fA1\` | pass → pass | FAIL → pass |"
A2_CHECKS="| \`fA2\` | pass → pass | pass → pass |"
B1_CHECKS="| \`fB1\` | pass | FAIL |"
PR_OPEN_NOTE="\`fA1\` accept at PR-open: FAIL  A2  key not followed"

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
check() { if eval "$2"; then pass "$1"; else fail "$1 — [$2]"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scorecard-accept.XXXXXX")"
[[ -n "$WORK" && -d "$WORK" ]] || { echo "could not make a work directory" >&2; exit 1; }
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

SCORECARD_MD="$WORK/SCORECARD.md"

cat > "$WORK/experiment.json" <<EXPERIMENT
{
  "name": "scorecardAccept",
  "fixtures": ["$FIXTURE"],
  "methods": ["$METHOD_A", "$METHOD_B"],
  "repeats": 3,
  "prediction": "a failed run neither drags a mean nor hides its spend"
}
EXPERIMENT

# Every good row: 30m to PR, 60m to green, 70m in total.
T='"t_setup_start":"2026-11-01T10:00:00Z","t_method_start":"2026-11-01T10:10:00Z","t_pr_open":"2026-11-01T10:40:00Z","t_green":"2026-11-01T11:10:00Z"'
OK_LINES='["PASS  A1  store written","PASS  A2  key followed","2 passed"]'
cat > "$WORK/results.jsonl" <<ROWS
{"fixture":"f","method":"a","repeat":1,"branch":"fA1",$T,"cost_method_usd":10,"cost_green_usd":12,"cost_lost_usd":0,"method_failed":false,"accept_pass":true,"accept_lines":$OK_LINES,"accept_pr_open_pass":false,"accept_pr_open_lines":["PASS  A1  store written","FAIL  A2  key not followed","1 passed, 1 failed"]}
{"fixture":"f","method":"a","repeat":2,"branch":"fA2",$T,"cost_method_usd":12,"cost_green_usd":14,"cost_lost_usd":5,"method_failed":false,"accept_pass":true,"accept_lines":$OK_LINES,"accept_pr_open_pass":true,"accept_pr_open_lines":$OK_LINES}
{"fixture":"f","method":"a","repeat":3,"branch":"fA3","t_setup_start":"2026-11-01T12:00:00Z","t_method_start":"2026-11-01T12:00:00Z","t_pr_open":"","t_green":"","cost_method_usd":0,"cost_green_usd":0,"cost_lost_usd":0,"method_failed":true,"accept_pass":false,"accept_lines":[],"accept_pr_open_pass":null,"accept_pr_open_lines":null}
{"fixture":"f","method":"b","repeat":1,"branch":"fB1",$T,"cost_method_usd":11,"cost_green_usd":12,"method_failed":false,"accept_pass":false,"accept_lines":["PASS  A1  store written","FAIL  A2  key not followed"]}
{"fixture":"f","method":"b","repeat":2,"branch":"fB2",$T,"cost_method_usd":11,"cost_green_usd":12,"method_failed":false,"accept_pass":true,"accept_lines":["all good"]}
ROWS

python3 "$SCORECARD" "$WORK" > "$WORK/stdout.txt" 2>&1
check "scorecard.py renders" "(( $? == 0 )) && [[ -s '$SCORECARD_MD' ]]"

echo "=== scorecard-accept: failed runs and the Per cell outcomes ==="
check "the Per cell header carries Mean wall to green, Failed and Spend" \
  "grep -qF 'Mean wall to PR | Mean total | Mean wall to green | Failed | Spend |' '$SCORECARD_MD'"
check "a: means over the two good runs, 1 failed, spend \$31 (lost \$5 charged to it)" \
  "grep -qF '$A_CELL_ROW' '$SCORECARD_MD'"
check "a: the failed \$0 run is not in the mean to green" "! grep -qF '$A_FAILED_MEAN' '$SCORECARD_MD'"
check "b: no failures, spend \$24" "grep -qF '$B_CELL_ROW' '$SCORECARD_MD'"
check "the band line compares the finished runs only: a tie" "grep -qF '$COMPARISON' '$SCORECARD_MD'"
check "the cost-means footnote is printed" "grep -qF 'Cost means, spreads and the band comparisons leave out' '$SCORECARD_MD'"

echo ""
echo "=== scorecard-accept: the Acceptance section ==="
check "the section is rendered" "grep -qxF '$ACCEPT_HEADING' '$SCORECARD_MD'"
check "a: 1/2 at PR-open (the failed run's null is not counted), 2/2 at green" \
  "grep -qF '$A_COUNTS' '$SCORECARD_MD'"
check "b: not measured at PR-open (—), 1/2 at green" "grep -qF '$B_COUNTS' '$SCORECARD_MD'"
check "the per-check header lists A1 and A2" "grep -qF '| Branch | A1 | A2 |' '$SCORECARD_MD'"
check "a #1: A2 failed at PR-open and passed at green" "grep -qF '$A1_CHECKS' '$SCORECARD_MD'"
check "a #2: both checks passed at both" "grep -qF '$A2_CHECKS' '$SCORECARD_MD'"
check "b #1: green results alone, A2 failed" "grep -qF '$B1_CHECKS' '$SCORECARD_MD'"
check "a PR-open failure is listed under failures" "grep -qF '$PR_OPEN_NOTE' '$SCORECARD_MD'"

echo ""
echo "=== scorecard-accept: a ledger without the fields ==="
cat > "$WORK/results.jsonl" <<ROWS
{"fixture":"f","method":"a","repeat":1,"branch":"fA1",$T,"cost_method_usd":10,"cost_green_usd":12,"accept_pass":true,"accept_lines":["ok"]}
{"fixture":"f","method":"b","repeat":1,"branch":"fB1",$T,"cost_method_usd":11,"cost_green_usd":12,"accept_pass":false,"accept_lines":["FAIL export drops the header row"]}
ROWS
python3 "$SCORECARD" "$WORK" > "$WORK/stdout.txt" 2>&1
check "no Acceptance section when no row measured PR-open and no line carries a check id" \
  "! grep -qF '$ACCEPT_HEADING' '$SCORECARD_MD'"

# The accept stage off: run.sh still writes the keys, as null, and accept_pass is the false
# it was initialized to — nothing was measured, so there is nothing to count.
cat > "$WORK/results.jsonl" <<ROWS
{"fixture":"f","method":"a","repeat":1,"branch":"fA1",$T,"cost_method_usd":10,"cost_green_usd":12,"accept_pass":false,"accept_lines":[],"accept_pr_open_pass":null,"accept_pr_open_lines":null}
{"fixture":"f","method":"b","repeat":1,"branch":"fB1",$T,"cost_method_usd":11,"cost_green_usd":12,"accept_pass":false,"accept_lines":[],"accept_pr_open_pass":null,"accept_pr_open_lines":null}
ROWS
python3 "$SCORECARD" "$WORK" > "$WORK/stdout.txt" 2>&1
check "no Acceptance section when every row carries the PR-open keys as null (accept off)" \
  "! grep -qF '$ACCEPT_HEADING' '$SCORECARD_MD'"

echo ""
if (( failures > 0 )); then
  echo "=== scorecard-accept: $failures check(s) FAILED ==="
  exit 1
fi
echo "=== scorecard-accept: all checks passed ==="
