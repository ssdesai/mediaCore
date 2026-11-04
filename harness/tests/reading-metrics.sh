#!/usr/bin/env bash
set -uo pipefail

# harness/reading_metrics.py on fabricated transcripts, and the scorecard's reading table.
#
#   harness/tests/reading-metrics.sh
#
# A projects root under a `mktemp -d` directory holds one session (with a subagent), a
# second session that falls after the window, and a sibling project directory whose name
# merely starts with the tree's. The metrics are counted from the Read results before the
# first Edit inside a window; the scorecard section then renders a hand-built ledger.
#
# No network, no money, no repo.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
READING_METRICS="$HARNESS_DIR/reading_metrics.py"
SCORECARD="$HARNESS_DIR/scorecard.py"
ANALYSIS_DIR="$REPO_DIR/analysis"

# The window and the events in it
WINDOW_FROM="2026-01-01T10:00:00Z"
WINDOW_TO="2026-01-01T11:00:00Z"
T_BEFORE="2026-01-01T09:59:00Z"
T_README_1="2026-01-01T10:01:00.123Z"
T_A_FIRST="2026-01-01T10:02:00Z"
T_ERROR="2026-01-01T10:02:30Z"
T_B_SUB="2026-01-01T10:03:00.456Z"
T_A_REPEAT="2026-01-01T10:04:00Z"
T_EDIT="2026-01-01T10:05:00Z"
T_README_2="2026-01-01T10:06:00Z"
T_AFTER="2026-01-01T11:01:00Z"

# The tree and its project directory
TREE_NAME="repo-cellBranch"
SESSION_ID="s1"
SUBAGENT_FILE="agent-x.jsonl"

# Tool-result texts: R1 holds a two-byte character (é) so bytes differ from characters
RESULT_README_1="readme é one"
RESULT_A_BLOCK_1="alpha block"
RESULT_A_BLOCK_2="second block"
RESULT_A_REPEAT="alpha again"
RESULT_README_2="docs readme five"
RESULT_B="lib b six"
RESULT_ERROR="no such file"
RESULT_OUTSIDE="outside the window"
RESULT_LATE="late read"
RESULT_SIBLING="sibling project read"

# The scorecard fixture
EXPERIMENT_NAME="readingMetrics"
FIXTURE="f"
METHOD="m"
ARM="only"
SHA="1111111111111111111111111111111111111111"
FILES_READ=12
BYTES_READ=123456
README_BYTES=7890
FILES_READ_GROUPED="12"
BYTES_READ_GROUPED="123,456"
README_BYTES_GROUPED="7,890"
READING_HEADING="## Reading before the first edit"
ROW_MEASURED="| $FILES_READ_GROUPED | $BYTES_READ_GROUPED | $README_BYTES_GROUPED |"
ROW_UNMEASURED="| — | — | — |"

# Exit statuses
USAGE_STATUS=2
EXPECTED_FILES=3
EXPECTED_TRANSCRIPTS=2

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
check() { if eval "$2"; then pass "$1"; else fail "$1 — [$2]"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/reading-metrics.XXXXXX")"
[[ -n "$WORK" && -d "$WORK" ]] || { echo "could not make a work directory" >&2; exit 1; }
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

TREE="$WORK/$TREE_NAME"
MANGLED="$(printf '%s' "$TREE" | tr '/.' '--')"
PROJECTS="$WORK/projects"
PROJECT_DIR="$PROJECTS/$MANGLED"
SIBLING_DIR="$PROJECTS/${MANGLED}2"
mkdir -p "$PROJECT_DIR/$SESSION_ID/subagents" "$SIBLING_DIR"

# bytes <text>: the UTF-8 size of a string, as wc counts it (trimmed of padding).
bytes() { printf '%s' "$1" | wc -c | tr -d ' '; }

# read_call <file> <time> <id> <path>
read_call() {
  jq -c -n --arg t "$2" --arg id "$3" --arg p "$4" \
    '{type:"assistant",timestamp:$t,message:{content:[{type:"tool_use",id:$id,name:"Read",input:{file_path:$p}}]}}' >> "$1"
}
# edit_call <file> <time> <id> <path>
edit_call() {
  jq -c -n --arg t "$2" --arg id "$3" --arg p "$4" \
    '{type:"assistant",timestamp:$t,message:{content:[{type:"tool_use",id:$id,name:"Edit",input:{file_path:$p}}]}}' >> "$1"
}
# result_str <file> <time> <id> <text>: a result whose content is a string
result_str() {
  jq -c -n --arg t "$2" --arg id "$3" --arg x "$4" \
    '{type:"user",timestamp:$t,message:{content:[{type:"tool_result",tool_use_id:$id,content:$x}]}}' >> "$1"
}
# result_list <file> <time> <id> <text> <text>: a result whose content is text blocks
result_list() {
  jq -c -n --arg t "$2" --arg id "$3" --arg x "$4" --arg y "$5" \
    '{type:"user",timestamp:$t,message:{content:[{type:"tool_result",tool_use_id:$id,content:[{type:"text",text:$x},{type:"text",text:$y}]}]}}' >> "$1"
}
# result_error <file> <time> <id> <text>
result_error() {
  jq -c -n --arg t "$2" --arg id "$3" --arg x "$4" \
    '{type:"user",timestamp:$t,message:{content:[{type:"tool_result",tool_use_id:$id,content:$x,is_error:true}]}}' >> "$1"
}

# The reads, without the Edit line (the no-edit case reuses them)
write_reads() {
  # write_reads <session file> <subagent file>
  local s="$1" sub="$2"
  read_call  "$s" "$T_BEFORE"   "u0" "$TREE/README.md"
  result_str "$s" "$T_BEFORE"   "u0" "$RESULT_OUTSIDE"
  read_call  "$s" "$T_README_1" "u1" "$TREE/README.md"
  result_str "$s" "$T_README_1" "u1" "$RESULT_README_1"
  read_call  "$s" "$T_A_FIRST"  "u2" "$TREE/src/a.py"
  result_list "$s" "$T_A_FIRST" "u2" "$RESULT_A_BLOCK_1" "$RESULT_A_BLOCK_2"
  read_call  "$s" "$T_ERROR"    "ue" "$TREE/missing.py"
  result_error "$s" "$T_ERROR"  "ue" "$RESULT_ERROR"
  read_call  "$s" "$T_A_REPEAT" "u3" "$TREE/src/a.py"
  result_str "$s" "$T_A_REPEAT" "u3" "$RESULT_A_REPEAT"
  read_call  "$s" "$T_README_2" "u5" "$TREE/docs/README.md"
  result_str "$s" "$T_README_2" "u5" "$RESULT_README_2"
  read_call  "$sub" "$T_B_SUB"  "u6" "$TREE/lib/b.py"
  result_str "$sub" "$T_B_SUB"  "u6" "$RESULT_B"
}

S1="$PROJECT_DIR/$SESSION_ID.jsonl"
SUB="$PROJECT_DIR/$SESSION_ID/subagents/$SUBAGENT_FILE"
write_reads "$S1" "$SUB"
edit_call "$S1" "$T_EDIT" "u4" "$TREE/src/a.py"
read_call  "$PROJECT_DIR/s2.jsonl" "$T_AFTER" "u7" "$TREE/late.py"
result_str "$PROJECT_DIR/s2.jsonl" "$T_AFTER" "u7" "$RESULT_LATE"
read_call  "$SIBLING_DIR/sib.jsonl" "$T_A_FIRST" "us" "$TREE/sibling.py"
result_str "$SIBLING_DIR/sib.jsonl" "$T_A_FIRST" "us" "$RESULT_SIBLING"

metrics() {
  # metrics <projects root>  → stdout, status
  python3 "$READING_METRICS" "$ANALYSIS_DIR" "$TREE" \
    --from "$WINDOW_FROM" --to "$WINDOW_TO" --projects-root "$1"
}

B_R1="$(bytes "$RESULT_README_1")"
B_R2="$(bytes "$RESULT_A_BLOCK_1$RESULT_A_BLOCK_2")"
B_R3="$(bytes "$RESULT_A_REPEAT")"
B_R5="$(bytes "$RESULT_README_2")"
B_R6="$(bytes "$RESULT_B")"

# ── The full world ───────────────────────────────────────────────────────────
echo "=== reading-metrics: the window, the first edit, the subagent ==="
OUT="$(metrics "$PROJECTS" 2>"$WORK/stderr.txt")"; STATUS=$?
check "exit 0 and one line of JSON" \
  "(( $STATUS == 0 )) && [[ \$(printf '%s\n' '$OUT' | wc -l | tr -d ' ') -eq 1 ]] && printf '%s' '$OUT' | jq -e . >/dev/null"
field() { printf '%s' "$OUT" | jq -r ".$1"; }
check "read_files_before_edit == $EXPECTED_FILES (repeat once, errored read and post-edit reads not at all)" \
  "[[ \$(field read_files_before_edit) == '$EXPECTED_FILES' ]]"
EXPECTED_BYTES=$(( B_R1 + B_R2 + B_R3 + B_R6 ))
check "read_bytes_before_edit == $EXPECTED_BYTES" \
  "[[ \$(field read_bytes_before_edit) == '$EXPECTED_BYTES' ]]"
EXPECTED_README=$(( B_R1 + B_R5 ))
check "readme_bytes_read == $EXPECTED_README (README reads after the edit count; the one before the window does not)" \
  "[[ \$(field readme_bytes_read) == '$EXPECTED_README' ]]"
check "transcripts == $EXPECTED_TRANSCRIPTS (session and subagent; not the late session, not the sibling directory)" \
  "[[ \$(field transcripts) == '$EXPECTED_TRANSCRIPTS' ]]"

# ── No edit ──────────────────────────────────────────────────────────────────
echo ""
echo "=== reading-metrics: no edit ==="
NOEDIT="$WORK/noedit"
NOEDIT_PROJECT="$NOEDIT/$MANGLED"
mkdir -p "$NOEDIT_PROJECT/$SESSION_ID/subagents"
write_reads "$NOEDIT_PROJECT/$SESSION_ID.jsonl" "$NOEDIT_PROJECT/$SESSION_ID/subagents/$SUBAGENT_FILE"
OUT="$(metrics "$NOEDIT" 2>/dev/null)"; STATUS=$?
NOEDIT_FILES=4
NOEDIT_BYTES=$(( B_R1 + B_R2 + B_R3 + B_R5 + B_R6 ))
check "no Edit line: every in-window read counts, R5's file included ($NOEDIT_FILES files)" \
  "(( $STATUS == 0 )) && [[ \$(field read_files_before_edit) == '$NOEDIT_FILES' ]]"
check "... and its bytes ($NOEDIT_BYTES)" \
  "[[ \$(field read_bytes_before_edit) == '$NOEDIT_BYTES' ]]"

# ── No transcripts ───────────────────────────────────────────────────────────
echo ""
echo "=== reading-metrics: no transcripts ==="
EMPTY_ROOT="$WORK/empty-projects"
mkdir -p "$EMPTY_ROOT"
OUT="$(metrics "$EMPTY_ROOT" 2>/dev/null)"; STATUS=$?
check "no project directory: the three figures are null" \
  "(( $STATUS == 0 )) && [[ \$(field read_files_before_edit) == null && \$(field read_bytes_before_edit) == null && \$(field readme_bytes_read) == null ]]"
check "... and transcripts == 0" "[[ \$(field transcripts) == 0 ]]"

# ── Usage ────────────────────────────────────────────────────────────────────
echo ""
echo "=== reading-metrics: usage errors ==="
NO_ANALYSIS="$WORK/no-analysis"
mkdir -p "$NO_ANALYSIS"
python3 "$READING_METRICS" "$NO_ANALYSIS" "$TREE" --from "$WINDOW_FROM" --to "$WINDOW_TO" \
  --projects-root "$PROJECTS" >/dev/null 2>&1
STATUS=$?
check "an analysis directory without capture_planning.py exits $USAGE_STATUS" "(( $STATUS == $USAGE_STATUS ))"
python3 "$READING_METRICS" "$ANALYSIS_DIR" "$TREE" --from "not-a-time" --to "$WINDOW_TO" \
  --projects-root "$PROJECTS" >/dev/null 2>&1
STATUS=$?
check "--from not-a-time exits $USAGE_STATUS" "(( $STATUS == $USAGE_STATUS ))"

# ── The scorecard's reading table ────────────────────────────────────────────
echo ""
echo "=== reading-metrics: the scorecard table ==="
CARD="$WORK/card"
mkdir -p "$CARD"
cat > "$CARD/experiment.json" <<EXPERIMENT
{
  "name": "$EXPERIMENT_NAME",
  "fixtures": ["$FIXTURE"],
  "methods": ["$METHOD"],
  "repeats": 1,
  "noise_band_pct": 15,
  "agent_tooling": {"$ARM": "$SHA"},
  "prediction": "the reading table renders only for measured ledgers"
}
EXPERIMENT

render() {
  # render <jq filter extras: extra row json>
  python3 "$SCORECARD" "$CARD" > "$CARD/stdout.txt" 2>&1
}
card_row() {
  # card_row <extra JSON object merged into the row>
  jq -c -n --arg f "$FIXTURE" --arg m "$METHOD" --arg a "$ARM" --arg s "$SHA" --argjson extra "$1" \
    '{fixture:$f,method:$m,repeat:1,arm:$a,agent_tooling:$s,branch:"b",cost_method_usd:1.0,cost_green_usd:1.0} + $extra'
}

card_row "{\"read_files_before_edit\":$FILES_READ,\"read_bytes_before_edit\":$BYTES_READ,\"readme_bytes_read\":$README_BYTES}" > "$CARD/results.jsonl"
render
check "scorecard.py renders" "(( $? == 0 )) && [[ -s '$CARD/SCORECARD.md' ]]"
check "a measured row renders the '$READING_HEADING' heading" "grep -qF '$READING_HEADING' '$CARD/SCORECARD.md'"
check "... and a table row with grouped digits ($ROW_MEASURED)" "grep -qF -e '$ROW_MEASURED' '$CARD/SCORECARD.md'"

card_row '{"read_files_before_edit":null,"read_bytes_before_edit":null,"readme_bytes_read":null}' > "$CARD/results.jsonl"
render
check "a row with the three fields null renders $ROW_UNMEASURED" "grep -qF -e '$ROW_UNMEASURED' '$CARD/SCORECARD.md'"

card_row '{}' > "$CARD/results.jsonl"
render
check "a ledger without the three keys renders no reading heading" "! grep -qF '$READING_HEADING' '$CARD/SCORECARD.md'"

echo ""
if (( failures > 0 )); then
  echo "=== reading-metrics: $failures check(s) FAILED ==="
  exit 1
fi
echo "=== reading-metrics: all checks passed ==="
