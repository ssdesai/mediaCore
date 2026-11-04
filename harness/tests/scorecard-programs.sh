#!/usr/bin/env bash
set -uo pipefail

# The scorecard's program section, driven through scorecard.py on a hand-built ledger:
# rows with kind "program" (harness/README.md → "File shapes") get their own tables and
# their own comparison line, and an ordinary ledger renders exactly as it did before they
# existed.
#
#   harness/tests/scorecard-programs.sh                  run the checks
#   harness/tests/scorecard-programs.sh --write-expected rewrite the byte-identity fixture
#
# Two program rows (arms before and after, program pr1), each with two features, plus two
# ordinary cell rows. The arm pair is inside the ±15% band on to-PR-open and outside it on
# to-green; the before arm opens 2/2 PRs, the after arm 1/2, and the after arm's second
# feature was meant to start from the first's branch and does not.
#
# The byte-identity check compares the scorecard of the cell rows alone against
# scorecard-programs.cells.md, committed beside this script: the text scorecard.py rendered
# for exactly this experiment.json and these two rows before program rows existed, written
# once with --write-expected from that earlier scorecard.py. It is a fixture file, not a
# run of origin/main's scorecard.py, so it needs no network and no second checkout.
#
# No network, no money, no repo: a `mktemp -d` directory holding an experiment.json and a
# results.jsonl, removed on exit. Needs jq (the rows are written pretty and compacted).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCORECARD="$(cd "$SCRIPT_DIR/.." && pwd)/scorecard.py"
EXPECTED_CELLS="$SCRIPT_DIR/scorecard-programs.cells.md"

# The experiment
EXPERIMENT_NAME="scorecardPrograms"
FIXTURE="f"
METHOD_A="a"
METHOD_B="b"
PROGRAM="pr1"
ARM_BEFORE="before"
ARM_AFTER="after"
SHA_BEFORE="1111111111111111111111111111111111111111"
SHA_AFTER="2222222222222222222222222222222222222222"
NOISE_BAND_PCT=15
BRANCH_BEFORE="pr1OrchestratorBefore"
BRANCH_AFTER="pr1OrchestratorAfter"
FEATURE_PR_URL="https://example.test/pr/1"

# What scorecard.py prints (render() / render_programs() / compare()).
PROGRAMS_HEADING="## Programs"
PER_PROGRAM_CELL_HEADING="## Per program cell"
CELL_RUNS_HEADING="## Runs"
BAND_HEADING_PREFIX="## Cost against the"
INTERVENTIONS_HEADING="## Interventions and failures"
GATE_HEADING="## Gate counts"
DEPENDS_BROKEN="✗"
DEPENDS_OK="✓"
PROGRAM_LINE_PREFIX="- **$PROGRAM · orchestrator**"
CELL_LINE_PREFIX="- **$FIXTURE · "
# after vs before: to PR-open $20.50 vs $20.00 is -2% (inside); to green $32.00 vs $24.00
# is -25% (outside, the right-hand arm cheaper). PRs open 1/2 vs 2/2, overhead 4.20/20.50
# against 4.00/20.00.
PROGRAM_LINE="$PROGRAM_LINE_PREFIX: arm $ARM_AFTER vs arm $ARM_BEFORE — to PR-open \$20.50 vs \$20.00 (-2%, tie inside the band); to green \$32.00 vs \$24.00 (-25%, arm $ARM_BEFORE cheaper, outside the band); PRs open 1/2 vs 2/2, green 1/2 vs 2/2, overhead 20.5% vs 20.0% (n=1)."

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
check() { if eval "$2"; then pass "$1"; else fail "$1 — [$2]"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scorecard-programs.XXXXXX")"
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
  "prediction": "the scorecard reads a program cell as one feature set"
}
EXPERIMENT

# Two ordinary cell rows: one passing, with an intervention and gate counts; one failing its
# acceptance probe with the lines it printed. Between them the runs table, the method pair,
# the notes and the gate-count table all have something to render.
cell_rows() {
  jq -c . <<CELLS
{"fixture":"$FIXTURE","method":"$METHOD_A","repeat":1,"arm":"$ARM_BEFORE","agent_tooling":"$SHA_BEFORE",
 "branch":"fABefore","pr_url":"https://example.test/pr/10","t_method_start":"2026-10-30T10:00:00Z",
 "t_pr_open":"2026-10-30T10:30:00Z","cost_method_usd":10.00,"cost_review_usd":1.00,"cost_rework_usd":0,
 "cost_green_usd":11.00,"review_fixed":2,"review_escalated":0,"rework_ran":false,
 "gate_counts_pr_open":"40 pass","gate_counts_green":"41 pass","accept_pass":true,
 "interventions":[{"t":"2026-10-30T10:10:00Z","what":"re-queued after a usage limit"}]}
{"fixture":"$FIXTURE","method":"$METHOD_B","repeat":1,"arm":"$ARM_BEFORE","agent_tooling":"$SHA_BEFORE",
 "branch":"fBBefore","pr_url":"https://example.test/pr/11","cost_method_usd":20.00,"cost_review_usd":2.00,
 "cost_rework_usd":3.00,"cost_green_usd":25.00,"review_fixed":1,"review_escalated":1,"rework_ran":true,
 "gate_counts_pr_open":"38 pass","gate_counts_green":"41 pass","accept_pass":false,
 "accept_lines":["FAIL export drops the header row"]}
CELLS
}

# One program row. program_row <arm> <sha> <branch> <repeat>, then the rest from the
# variables each arm's block sets before calling it.
program_row() {
  jq -c . <<PROGRAM_ROW
{"kind":"program","experiment":"$EXPERIMENT_NAME","program":"$PROGRAM","method":"orchestrator","repeat":$4,
 "arm":"$1","agent_tooling":"$2","branch":"$3","slug":"pr1-orchestrator","orchestration_record":"self/orchestrations/pr1/README.md",
 "orchestrator_sessions":["sess-orch"],"cost_overhead_usd":$OVERHEAD,"cost_group_usd":$GROUP_OPEN,
 "cost_group_green_usd":$GROUP_GREEN,"overhead_pct":$OVERHEAD_PCT,"features_count":2,
 "features_pr_open":$PRS_OPEN,"features_green":$GREEN,"method_failed":false,"record_report":$RECORD_REPORT,
 "features":[
  {"position":1,"fixture":"fx1","depends_on_previous":false,"method":"direct","branch":"fx1Pr1$5","slug":"fx1-pr1",
   "session":"s1","pr_url":"$FEATURE_PR_URL","pr_base":"main","brief_written":true,"dependency_ok":null,
   "cost_method_usd":$F1_OPEN,"cost_review_usd":$F1_REVIEW,"cost_rework_usd":$F1_REWORK,"cost_green_usd":$F1_GREEN,
   "unpriced_reason":null,"review_fixed":1,"review_escalated":0,"rework_ran":$F1_REWORK_RAN,"accept_pass":true,
   "accept_lines":[],"gate_counts_green":"$F1_GATE","green":true,"method_failed":false},
  {"position":2,"fixture":"fx2","depends_on_previous":true,"method":"direct","branch":"fx2Pr1$5","slug":"fx2-pr1",
   "session":"s2","pr_url":"$F2_PR","pr_base":"fx1Pr1$5","brief_written":true,"dependency_ok":$F2_DEP_OK,
   "cost_method_usd":$F2_OPEN,"cost_review_usd":$F2_REVIEW,"cost_rework_usd":$F2_REWORK,"cost_green_usd":$F2_GREEN,
   "unpriced_reason":null,"review_fixed":0,"review_escalated":1,"rework_ran":$F2_REWORK_RAN,"accept_pass":$F2_ACCEPT,
   "accept_lines":$F2_ACCEPT_LINES,"gate_counts_green":"$F2_GATE","green":$F2_ACCEPT,"method_failed":$F2_FAILED}],
 "interventions":$INTERVENTIONS}
PROGRAM_ROW
}

# Arm before: overhead 4.00 + features 10.00 + 6.00 = 20.00 to PR-open; the features add
# 1.00 + 2.00 of review and 1.00 of rework, so 24.00 to green. Both PRs open, both green.
before_row() {
  OVERHEAD="4.00"; GROUP_OPEN="20.00"; GROUP_GREEN="24.00"; OVERHEAD_PCT="20.0"; PRS_OPEN=2; GREEN=2
  RECORD_REPORT='{"group_total_usd":20.00,"overhead_pct":20.0,"unpriced_count":0}'
  F1_OPEN="10.00"; F1_REVIEW="1.00"; F1_REWORK="0"; F1_GREEN="11.00"; F1_REWORK_RAN="false"; F1_GATE="50 pass"
  F2_OPEN="6.00"; F2_REVIEW="2.00"; F2_REWORK="1.00"; F2_GREEN="9.00"; F2_REWORK_RAN="true"; F2_DEP_OK="true"; F2_ACCEPT="true"
  F2_ACCEPT_LINES="[]"; F2_GATE="51 pass"; F2_FAILED="false"; F2_PR="https://example.test/pr/2"
  INTERVENTIONS='[]'
  program_row "$ARM_BEFORE" "$SHA_BEFORE" "$BRANCH_BEFORE" "${1:-1}" "Before"
}

# Arm after: overhead 4.20 + features 11.30 + 5.00 = 20.50 to PR-open; the first feature
# adds 3.00 of review and 8.50 of rework, so 32.00 to green. Only the first PR opens: the
# second feature's branch does not contain the first's tip and its method failed.
after_row() {
  OVERHEAD="4.20"; GROUP_OPEN="20.50"; GROUP_GREEN="32.00"; OVERHEAD_PCT="20.4878"; PRS_OPEN=1; GREEN=1
  RECORD_REPORT='null'
  F1_OPEN="11.30"; F1_REVIEW="3.00"; F1_REWORK="8.50"; F1_GREEN="22.80"; F1_REWORK_RAN="true"; F1_GATE="52 pass"
  F2_OPEN="5.00"; F2_REVIEW="0"; F2_REWORK="0"; F2_GREEN="5.00"; F2_REWORK_RAN="false"; F2_DEP_OK="false"; F2_ACCEPT="false"
  F2_ACCEPT_LINES='["FAIL feature two never started"]'; F2_GATE="12 pass, 3 fail"; F2_FAILED="true"; F2_PR=""
  INTERVENTIONS='[{"t":"2026-10-30T12:00:00Z","what":"orchestrator resumed after a restart"}]'
  program_row "$ARM_AFTER" "$SHA_AFTER" "$BRANCH_AFTER" 1 "After"
}

render() {
  python3 "$SCORECARD" "$WORK" > "$WORK/scorecard-stdout.txt" 2>&1
}

# A section of the rendered scorecard: from its heading to the next "## " heading.
section() { sed -n "/^$1/,/^## /p" "$SCORECARD_MD" | sed '1!{/^## /d}'; }
# The line number of a heading, for ordering checks.
line_of() { grep -n -m1 -e "^$1" "$SCORECARD_MD" | cut -d: -f1; }

if [[ "${1:-}" == "--write-expected" ]]; then
  cell_rows > "$RESULTS"
  render || { cat "$WORK/scorecard-stdout.txt" >&2; exit 1; }
  cp "$SCORECARD_MD" "$EXPECTED_CELLS"
  echo "wrote $EXPECTED_CELLS"
  exit 0
fi

# ── Cell rows alone: byte-identical to the scorecard before program rows existed ──
echo "=== scorecard-programs: cell rows alone ==="
cell_rows > "$RESULTS"
render
check "scorecard.py renders a ledger with no program row" "(( $? == 0 )) && [[ -s '$SCORECARD_MD' ]]"
check "... and it is byte-identical to the committed pre-program rendering" \
  "cmp -s '$SCORECARD_MD' '$EXPECTED_CELLS'"
check "... which has no Programs section and no program count in its header" \
  "! grep -qF -e '$PROGRAMS_HEADING' -e 'programs:' '$SCORECARD_MD'"

# ── Two program rows and two cell rows ──
echo ""
echo "=== scorecard-programs: two program rows, two cell rows ==="
{ cell_rows; before_row; after_row; } > "$RESULTS"
render
check "scorecard.py renders" "(( $? == 0 )) && [[ -s '$SCORECARD_MD' ]]"
check "the header counts the program rows" "grep -qF 'programs: 2' '$SCORECARD_MD'"
check "the Programs section follows the cost-band section, which follows the runs" \
  "(( \$(line_of '$CELL_RUNS_HEADING') < \$(line_of '$BAND_HEADING_PREFIX') && \$(line_of '$BAND_HEADING_PREFIX') < \$(line_of '$PROGRAMS_HEADING') ))"

echo "-- the Programs table"
check "arm $ARM_BEFORE's row: group, overhead, overhead %, to green, PRs open, green, the record's figure" \
  "grep -qF '| $PROGRAM | $ARM_BEFORE (${SHA_BEFORE:0:7}) | 1 | \`$BRANCH_BEFORE\` | \$20.00 | \$4.00 | 20.0% | \$24.00 | 2/2 | 2/2 | \$20.00 |' '$SCORECARD_MD'"
check "arm $ARM_AFTER's row: overhead % is cost_overhead / cost_group, 1/2 PRs open, no record figure" \
  "grep -qF '| $PROGRAM | $ARM_AFTER (${SHA_AFTER:0:7}) | 1 | \`$BRANCH_AFTER\` | \$20.50 | \$4.20 | 20.5% | \$32.00 | 1/2 | 1/2 | — |' '$SCORECARD_MD'"

echo "-- the per-feature tables"
check "a heading per program cell" \
  "grep -qxF '### $PROGRAM · arm $ARM_BEFORE #1' '$SCORECARD_MD' && grep -qxF '### $PROGRAM · arm $ARM_AFTER #1' '$SCORECARD_MD'"
check "the first feature depends on nothing: —, its review counts, no rework, its PR" \
  "grep -qF '| 1 | fx1 | — | \`fx1Pr1Before\` | direct | \$10.00 | 1/0 | — | \$11.00 | pass | $FEATURE_PR_URL |' '$SCORECARD_MD'"
check "a dependent feature whose branch holds the previous tip reads $DEPENDS_OK" \
  "grep -qF '| 2 | fx2 | $DEPENDS_OK | \`fx2Pr1Before\` | direct | \$6.00 | 0/1 | \$1.00 | \$9.00 | pass | https://example.test/pr/2 |' '$SCORECARD_MD'"
check "a dependent feature whose branch lacks it reads $DEPENDS_BROKEN, fails accept, has no PR" \
  "grep -qF '| 2 | fx2 | $DEPENDS_BROKEN | \`fx2Pr1After\` | direct | \$5.00 | 0/1 | — | \$5.00 | method failed | — |' '$SCORECARD_MD'"
check "a feature that re-ran rework shows its cost" \
  "grep -qF '| 1 | fx1 | — | \`fx1Pr1After\` | direct | \$11.30 | 1/0 | \$8.50 | \$22.80 | pass |' '$SCORECARD_MD'"

echo "-- the comparison line"
check "one program line, in the cell lines' wording, with the counts suffix" \
  "grep -qxF -e '$PROGRAM_LINE' '$SCORECARD_MD'"
check "... under the same band heading as the cell lines, which kept their own line" \
  "[[ \$(section '$BAND_HEADING_PREFIX' | grep -c -F -e '$PROGRAM_LINE_PREFIX') -eq 1 && \$(section '$BAND_HEADING_PREFIX' | grep -c -F -e '$CELL_LINE_PREFIX') -eq 1 ]]"

echo "-- program rows stay out of the cell sections"
check "the runs table holds the two cell rows and neither program branch" \
  "[[ \$(section '$CELL_RUNS_HEADING' | grep -c '^| $FIXTURE | ') -eq 2 ]] && ! section '$CELL_RUNS_HEADING' | grep -qF -e '$BRANCH_BEFORE' -e '$BRANCH_AFTER'"
check "no cell comparison names the program, an orchestrator or a group figure" \
  "! grep -F -e '$CELL_LINE_PREFIX' '$SCORECARD_MD' | grep -qF -e '$PROGRAM' -e orchestrator"
check "no Per cell section (every cell ran once)" "! grep -q '^## Per cell' '$SCORECARD_MD'"

echo "-- interventions, failures and gate counts"
check "a program's own intervention is listed under its branch" \
  "section '$INTERVENTIONS_HEADING' | grep -qF '\`$BRANCH_AFTER\` 2026-10-30T12:00:00Z: orchestrator resumed after a restart'"
check "a feature whose method failed is listed under its own branch" \
  "section '$INTERVENTIONS_HEADING' | grep -qF '\`fx2Pr1After\`: the method did not reach an open PR.'"
check "a feature whose dependency is not satisfied is listed" \
  "section '$INTERVENTIONS_HEADING' | grep -qF '\`fx2Pr1After\`: its branch does not contain the previous feature'"
check "a failing cell still lists its accept lines (cell notes unchanged)" \
  "section '$INTERVENTIONS_HEADING' | grep -qF '\`fBBefore\` accept: FAIL export drops the header row'"
check "each feature's gate count at green joins the gate-counts table" \
  "section '$GATE_HEADING' | grep -qF '| \`fx1Pr1Before\` | — | 50 pass |' && section '$GATE_HEADING' | grep -qF '| \`fx2Pr1After\` | — | 12 pass, 3 fail |'"

# ── A re-run of arm before: means and spread ──
echo ""
echo "=== scorecard-programs: a repeat ==="
before_row 2 | sed 's/Before"/Before2"/g' >> "$RESULTS"
render
check "scorecard.py renders" "(( $? == 0 ))"
check "a Per program cell block appears" "grep -qxF '$PER_PROGRAM_CELL_HEADING' '$SCORECARD_MD'"
check "... with arm $ARM_BEFORE's two runs, mean to green \$24.00, spread \$0.00, mean overhead 20.0%" \
  "section '$PER_PROGRAM_CELL_HEADING' | grep -qF '| $PROGRAM | $ARM_BEFORE | 2 | \$24.00 | \$0.00 | 20.0% | 2 | 2 |'"
check "the repeat's own table is headed with its number" "grep -qxF '### $PROGRAM · arm $ARM_BEFORE #2' '$SCORECARD_MD'"
check "the comparison line uses the repeats' means (identical here) and is still marked n=1, for arm $ARM_AFTER has one run" \
  "grep -qxF -e '$PROGRAM_LINE' '$SCORECARD_MD'"

# ── Programs only, with null summary fields: counted from features[], never a crash ──
echo ""
echo "=== scorecard-programs: programs only, null summary fields ==="
{ before_row; after_row; } | jq -c '.features_count = null | .features_pr_open = null
  | .features_green = null | .overhead_pct = null' > "$RESULTS"
render
check "scorecard.py renders" "(( $? == 0 )) && [[ -s '$SCORECARD_MD' ]]"
check "no Runs section without a cell row" "! grep -qxF '$CELL_RUNS_HEADING' '$SCORECARD_MD'"
check "the counts and overhead % fall back to features[] and cost_overhead / cost_group" \
  "grep -qF '| \$20.50 | \$4.20 | 20.5% | \$32.00 | 1/2 | 1/2 | — |' '$SCORECARD_MD'"

echo ""
if (( failures > 0 )); then
  echo "=== scorecard-programs: $failures check(s) FAILED ==="
  exit 1
fi
echo "=== scorecard-programs: all checks passed ==="
