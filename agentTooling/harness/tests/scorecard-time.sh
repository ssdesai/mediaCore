#!/usr/bin/env bash
set -uo pipefail

# The scorecard's time columns, driven through scorecard.py on a hand-built ledger:
# the Runs table's "Wall to PR" / "Wall to green" / "Total", and the Per cell table's
# mean wall to PR and mean total, which leave out a `method_failed` row.
#
#   harness/tests/scorecard-time.sh
#
# Rows (fixture f): method a ran three times — two good, one failed — and method b once,
# with no t_green. No network, no money, no repo: a `mktemp -d` directory, removed on exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCORECARD="$(cd "$SCRIPT_DIR/.." && pwd)/scorecard.py"

FIXTURE="f"
METHOD_A="a"
METHOD_B="b"

# a #1: wall to PR 30m, wall to green 60m, total 65m
A1_SETUP="2026-11-01T10:00:00Z"; A1_METHOD="2026-11-01T10:05:00Z"
A1_PR="2026-11-01T10:35:00Z";    A1_GREEN="2026-11-01T11:05:00Z"
# a #2: wall to PR 40m, wall to green 81m, total 91m
A2_SETUP="2026-11-01T12:00:00Z"; A2_METHOD="2026-11-01T12:10:00Z"
A2_PR="2026-11-01T12:50:00Z";    A2_GREEN="2026-11-01T13:31:00Z"
# a #3: failed — its 10m to PR and 20m total must not reach the means
A3_SETUP="2026-11-01T14:00:00Z"; A3_METHOD="2026-11-01T14:00:00Z"
A3_PR="2026-11-01T14:10:00Z";    A3_GREEN="2026-11-01T14:20:00Z"
# b #1: no t_green; wall to PR 15m
B1_SETUP="2026-11-01T16:00:00Z"; B1_METHOD="2026-11-01T16:05:00Z"
B1_PR="2026-11-01T16:20:00Z"

# What the tables should print
A1_CELLS="| 30m | 60m | 65m |"
A2_CELLS="| 40m | 81m | 91m |"
A3_CELLS="| 10m | 20m | 20m |"
B1_CELLS="| 15m | — | — |"
A_MEAN_CELLS="| 35m | 78m |"
B_MEAN_CELLS="| 15m | — |"
NOTE_FRAGMENT="Time means leave out rows with \`method_failed\`"

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
check() { if eval "$2"; then pass "$1"; else fail "$1 — [$2]"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scorecard-time.XXXXXX")"
[[ -n "$WORK" && -d "$WORK" ]] || { echo "could not make a work directory" >&2; exit 1; }
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

SCORECARD_MD="$WORK/SCORECARD.md"

cat > "$WORK/experiment.json" <<EXPERIMENT
{
  "name": "scorecardTime",
  "fixtures": ["$FIXTURE"],
  "methods": ["$METHOD_A", "$METHOD_B"],
  "repeats": 3,
  "prediction": "the scorecard shows time as plainly as cost"
}
EXPERIMENT

row() {
  # row <method> <repeat> <extra json> <setup> <method start> <pr open> [green]
  local green=""
  [[ $# -ge 7 ]] && green="$7"
  printf '{"fixture":"%s","method":"%s","repeat":%s,"branch":"%s%s%s",%s"t_setup_start":"%s","t_method_start":"%s","t_pr_open":"%s","t_green":"%s","cost_method_usd":1,"cost_green_usd":2}\n' \
    "$FIXTURE" "$1" "$2" "$FIXTURE" "$1" "$2" "$3" "$4" "$5" "$6" "$green"
}

{
  row "$METHOD_A" 1 "" "$A1_SETUP" "$A1_METHOD" "$A1_PR" "$A1_GREEN"
  row "$METHOD_A" 2 "" "$A2_SETUP" "$A2_METHOD" "$A2_PR" "$A2_GREEN"
  row "$METHOD_A" 3 '"method_failed":true,' "$A3_SETUP" "$A3_METHOD" "$A3_PR" "$A3_GREEN"
  row "$METHOD_B" 1 "" "$B1_SETUP" "$B1_METHOD" "$B1_PR"
} > "$WORK/results.jsonl"

python3 "$SCORECARD" "$WORK" > "$WORK/stdout.txt" 2>&1
check "scorecard.py renders" "(( $? == 0 )) && [[ -s '$SCORECARD_MD' ]]"

runs_row() { grep -F -e "\`$FIXTURE$1$2\`" "$SCORECARD_MD" | head -n 1; }
cell_row() { grep -E -e "^\\| $FIXTURE \\| $1 \\|" "$SCORECARD_MD" | tail -n 1; }

echo "=== scorecard-time: the Runs table ==="
check "the header names Wall to PR, Wall to green and Total" \
  "grep -qF 'Wall to PR | Wall to green | Total |' '$SCORECARD_MD'"
check "a #1: 30m / 60m / 65m" "runs_row $METHOD_A 1 | grep -qF '$A1_CELLS'"
check "a #2: 40m / 81m / 91m" "runs_row $METHOD_A 2 | grep -qF '$A2_CELLS'"
check "a #3 (failed): its own times are still shown" "runs_row $METHOD_A 3 | grep -qF '$A3_CELLS'"
check "b #1: a missing t_green renders NA in Wall to green and Total" \
  "runs_row $METHOD_B 1 | grep -qF '$B1_CELLS'"

echo ""
echo "=== scorecard-time: the Per cell table ==="
check "the Per cell header names the two time means" \
  "grep -qF 'Mean wall to PR | Mean total |' '$SCORECARD_MD'"
check "a: mean wall to PR 35m and mean total 78m, the failed row left out" \
  "cell_row $METHOD_A | grep -qF '$A_MEAN_CELLS'"
check "a: the failed row would have given 27m, and does not" \
  "! cell_row $METHOD_A | grep -qF '27m'"
check "b: a mean over a missing instant renders NA, not 0m" \
  "cell_row $METHOD_B | grep -qF '$B_MEAN_CELLS'"
check "the footnote says failed rows are left out of the time means" \
  "grep -qF '$NOTE_FRAGMENT' '$SCORECARD_MD'"

echo ""
echo "=== scorecard-time: the Per cell section is gated as before ==="
{
  row "$METHOD_A" 1 "" "$A1_SETUP" "$A1_METHOD" "$A1_PR" "$A1_GREEN"
  row "$METHOD_B" 1 "" "$B1_SETUP" "$B1_METHOD" "$B1_PR"
} > "$WORK/results.jsonl"
python3 "$SCORECARD" "$WORK" > "$WORK/stdout.txt" 2>&1
check "one run per cell: no Per cell section and no footnote" \
  "! grep -qF '## Per cell' '$SCORECARD_MD' && ! grep -qF '$NOTE_FRAGMENT' '$SCORECARD_MD'"

echo ""
if (( failures > 0 )); then
  echo "=== scorecard-time: $failures check(s) FAILED ==="
  exit 1
fi
echo "=== scorecard-time: all checks passed ==="
