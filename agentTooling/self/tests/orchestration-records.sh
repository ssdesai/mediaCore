#!/usr/bin/env bash
set -uo pipefail

# Self-test for the orchestration record (self/features/orchestration-records): the record
# an orchestrator session keeps of the group of features it spawned, its capture and its
# group report. Run by self/gate.sh, or by hand: bash self/tests/orchestration-records.sh
#
# Asserts:
#   S1. `orchestration-start.sh <slug>` writes self/orchestrations/<slug>/README.md whose
#       fence carries the slug, the session id, the checkout's full HEAD as
#       `agent_tooling`, an open window and no features; the prose says the orchestrator
#       commits only its record;
#   S2. it refuses a bad slug, an existing record and a run with no session id (exit 1),
#       and writes nothing on a refusal;
#   S3. `manifest.py --orchestration` round-trips: add-feature, a replacement with the same
#       repo and slug, set-feature (null clears), get, set-window-to now / an instant, and
#       refuses a key outside the entry, an unknown feature and a window not after `from`;
#       the existing subcommands are untouched;
#   S4. `manifest.py init --orchestration` writes the optional fence key, `get
#       orchestration` reads it, a bad slug is refused, and a fence without it reads empty;
#   S5. `orchestration-capture.sh` prices the session across two project directories (the
#       one with the later instant), inside the window only, and a record whose session has
#       no transcript is refused;
#   S6. `report.py --orchestration`: one row per feature (priced from report.json; unpriced
#       with the reason for no path, a missing path and a file with no total), the overhead
#       line, the group total (priced features + overhead), the overhead percentage and the
#       count of unpriced features, in report.md and in report.json alike; an uncaptured
#       overhead reads `unpriced: not captured`.
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/orchestration-records.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
FAKE_HOME="$TMP/home"
export HOME="$FAKE_HOME"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
unset CLAUDE_CODE_SESSION_ID

mkdir -p "$AT/analysis" "$AT/templates/plans/features" "$AT/self/features" "$FAKE_HOME/.claude/projects"
for f in pricing.py litellm_prices.py rates_history.json roots.py transcript.py routing.py manifest.py capture_planning.py report.py orchestration_capture.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done
cp "$HERE/templates/plans/features/TEMPLATE.md" "$AT/templates/plans/features/TEMPLATE.md"
cp "$HERE/orchestration-start.sh" "$HERE/orchestration-capture.sh" "$AT/"
# A real checkout, so `agent_tooling` has a commit to name.
git -C "$AT" init -q
git -C "$AT" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
HEAD_ID="$(git -C "$AT" rev-parse HEAD)"

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

MANIFEST=(python3 -B "$AT/analysis/manifest.py")
REPORT=(python3 -B "$AT/analysis/report.py")
SLUG="wave-one"
SESSION="oooooooo-0000-0000-0000-000000000001"
RECORD="$AT/self/orchestrations/$SLUG/README.md"
FOLDER="$AT/self/orchestrations/$SLUG"
# fence_get FILE EXPR — a python expression over the record's last fence `d`.
fence_get() {
  python3 -c '
import json, re, sys
text = open(sys.argv[1]).read()
d = json.loads(re.findall(r"```json\n(.*?)\n```", text, re.S)[-1])
print(eval(sys.argv[2]))' "$1" "$2"
}
json_get() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }

echo "== S1 start =="
out="$("$AT/orchestration-start.sh" "$SLUG" --session "$SESSION" 2>&1)"
check "S1 start exits 0 and writes the record" '[[ -f "$RECORD" ]]'
check "S1 fence slug and session" '[[ "$(fence_get "$RECORD" "d[\"slug\"]+\" \"+d[\"session\"]")" == "$SLUG $SESSION" ]]'
check "S1 agent_tooling is the full HEAD" '[[ "$(fence_get "$RECORD" "d[\"agent_tooling\"]")" == "$HEAD_ID" ]]'
check "S1 window is open and features empty" '[[ "$(fence_get "$RECORD" "(d[\"session_window\"][\"to\"], d[\"features\"])")" == "(None, [])" ]]'
check "S1 window from is a UTC instant" '[[ "$(fence_get "$RECORD" "d[\"session_window\"][\"from\"]")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]'
check "S1 prose: orchestrator commits only its record" 'grep -q "commits nothing except this record" "$RECORD"'

echo "== S2 start refusals =="
before="$(find "$AT/self/orchestrations" | sort)"
"$AT/orchestration-start.sh" "Bad_Slug" --session "$SESSION" >/dev/null 2>&1; rc=$?
check "S2 a bad slug is refused (1)" '[[ $rc -eq 1 ]]'
"$AT/orchestration-start.sh" "$SLUG" --session "$SESSION" >/dev/null 2>&1; rc=$?
check "S2 an existing record is refused (1)" '[[ $rc -eq 1 ]]'
"$AT/orchestration-start.sh" "no-session" >/dev/null 2>&1; rc=$?
check "S2 no session id is refused (1)" '[[ $rc -eq 1 ]]'
check "S2 nothing was written by a refusal" '[[ "$(find "$AT/self/orchestrations" | sort)" == "$before" ]]'
"$AT/orchestration-start.sh" >/dev/null 2>&1; rc=$?
check "S2 no slug is a usage error (2)" '[[ $rc -eq 2 ]]'

echo "== S3 manifest --orchestration =="
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=agentTooling slug=feat-a session=s-a branch=claude/feat-a pr=https://example.test/pr/1 report=self/features/feat-a/report.json >/dev/null
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=agentTooling slug=feat-b branch=claude/feat-b report=self/features/feat-b/report.json >/dev/null
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=humanNetworkMap slug=feat-c >/dev/null
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=agentTooling slug=feat-d report=self/features/feat-d/report.json >/dev/null
check "S3 four entries added in order" '[[ "$(fence_get "$RECORD" "[f[\"slug\"] for f in d[\"features\"]] == [\"feat-a\", \"feat-b\", \"feat-c\", \"feat-d\"]")" == "True" ]]'
check "S3 an unset field is null" '[[ "$(fence_get "$RECORD" "d[\"features\"][2][\"report\"]")" == "None" ]]'
out="$("${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=agentTooling slug=feat-b branch=claude/feat-b2 2>&1)"
check "S3 the same repo and slug replaces, never duplicates" '[[ "$out" == replaced* && "$(fence_get "$RECORD" "len(d[\"features\"])")" == "4" && "$(fence_get "$RECORD" "[f[\"branch\"] for f in d[\"features\"] if f[\"slug\"]==\"feat-b\"][0]")" == "claude/feat-b2" ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=agentTooling slug=feat-b branch=claude/feat-b report=self/features/feat-b/report.json >/dev/null
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=other slug=feat-b >/dev/null
check "S3 the same slug in another repo is a different entry" '[[ "$(fence_get "$RECORD" "len(d[\"features\"])")" == "5" ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" set-feature repo=humanNetworkMap slug=feat-c pr=https://example.test/pr/3 session=s-c >/dev/null
check "S3 set-feature sets fields" '[[ "$(fence_get "$RECORD" "d[\"features\"][2][\"pr\"]")" == "https://example.test/pr/3" ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" set-feature repo=humanNetworkMap slug=feat-c pr=null >/dev/null
check "S3 set-feature null clears a field" '[[ "$(fence_get "$RECORD" "d[\"features\"][2][\"pr\"]")" == "None" ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" set-feature repo=agentTooling slug=feat-a colour=red >/dev/null 2>&1; rc=$?
check "S3 a key outside the entry is refused (1)" '[[ $rc -eq 1 ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" set-feature repo=agentTooling slug=nope pr=x >/dev/null 2>&1; rc=$?
check "S3 an unknown feature is refused (1)" '[[ $rc -eq 1 ]]'
check "S3 get reads a scalar and a dotted path" '[[ "$("${MANIFEST[@]}" --orchestration "$SLUG" get session)" == "$SESSION" && -n "$("${MANIFEST[@]}" --orchestration "$SLUG" get session_window.from)" ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" set-window-to 2099-01-01T00:00:00Z >/dev/null
check "S3 set-window-to stamps an instant" '[[ "$(fence_get "$RECORD" "d[\"session_window\"][\"to\"]")" == "2099-01-01T00:00:00Z" ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" set-window-to 2001-01-01T00:00:00Z >/dev/null 2>&1; rc=$?
check "S3 a window not after from is refused (1)" '[[ $rc -eq 1 ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" set-window-to now >/dev/null
check "S3 set-window-to now stamps the clock" '[[ "$(fence_get "$RECORD" "d[\"session_window\"][\"to\"]")" =~ ^20[0-9]{2}-.*Z$ ]]'
"${MANIFEST[@]}" --orchestration nope get session >/dev/null 2>&1; rc=$?
check "S3 a missing record is refused (1)" '[[ $rc -eq 1 ]]'

echo "== S4 feature manifest names its orchestration =="
"${MANIFEST[@]}" --self plain init --method direct --branch plain --base main --from 2026-07-01T00:00:00Z >/dev/null
"${MANIFEST[@]}" --self tied init --method direct --branch tied --base main --from 2026-07-01T00:00:00Z --orchestration "$SLUG" >/dev/null
check "S4 init --orchestration writes the key" '[[ "$("${MANIFEST[@]}" --self tied get orchestration)" == "$SLUG" ]]'
check "S4 a fence without it reads empty" '[[ -z "$("${MANIFEST[@]}" --self plain get orchestration)" ]]'
"${MANIFEST[@]}" --self bad init --method direct --branch bad --base main --from 2026-07-01T00:00:00Z --orchestration "Not/A Slug" >/dev/null 2>&1; rc=$?
check "S4 a bad orchestration slug is refused and writes nothing" '[[ $rc -eq 1 && ! -e "$AT/self/features/bad" ]]'
check "S4 the existing subcommands still read the fence" '[[ "$("${MANIFEST[@]}" --self tied get method)" == "direct" ]]'

echo "== S5 capture =="
MODEL="claude-sonnet-5"
P_OLD="$FAKE_HOME/.claude/projects/-old-container"
P_NEW="$FAKE_HOME/.claude/projects/-new-container"
mkdir -p "$P_OLD" "$P_NEW"
# The same session id filed twice: the older copy is a prefix, the newer one the whole run.
{
  session_line "$SESSION" /w main m1 "$MODEL" 2026-07-02T10:00:00.000Z 1000 500 0 0 0
} > "$P_OLD/$SESSION.jsonl"
{
  session_line "$SESSION" /w main m1 "$MODEL" 2026-07-02T10:00:00.000Z 1000 500 0 0 0
  session_line "$SESSION" /w main m2 "$MODEL" 2026-07-02T10:30:00.000Z 2000 700 0 0 0
  session_line "$SESSION" /w main m3 "$MODEL" 2026-07-03T09:00:00.000Z 9000 9000 0 0 0
} > "$P_NEW/$SESSION.jsonl"
mkdir -p "$P_NEW/$SESSION/subagents"
subagent_line "$SESSION" a0123456789abcdef /w main s1 "$MODEL" 2026-07-02T11:00:00.000Z 300 100 0 0 0 > "$P_NEW/$SESSION/subagents/agent-a0123456789abcdef.jsonl"
# The record's `from` is the clock; move it into the fixture's day so the window holds m1 and m2.
sed -i.bak 's/"from": "[^"]*"/"from": "2026-07-02T09:00:00Z"/' "$RECORD" && rm -f "$RECORD.bak"
"${MANIFEST[@]}" --orchestration "$SLUG" set-window-to 2026-07-02T12:00:00Z >/dev/null
"$AT/orchestration-capture.sh" "$SLUG" >"$TMP/capture.out" 2>&1; rc=$?
check "S5 capture exits 0 and writes planning.json" '[[ $rc -eq 0 && -f "$FOLDER/planning.json" ]]'
EXPECT="$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from pricing import compute_cost
def tok(i, o): return {"input": i, "output": o, "cache_read": 0, "cache_creation_5m": 0, "cache_creation_1h": 0}
main, _ = compute_cost(sys.argv[2], tok(3000, 1200), as_of="2026-07-02")
sub, _ = compute_cost(sys.argv[2], tok(300, 100), as_of="2026-07-02")
print(round(main + sub, 9))' "$AT/analysis" "$MODEL")"
check "S5 total is the in-window responses of the later transcript, subagent included" '[[ "$(json_get "$FOLDER/planning.json" "round(d[\"cost_usd\"][\"total\"], 9)")" == "$EXPECT" ]]'
check "S5 the subagent is priced as a subagent" '[[ "$(json_get "$FOLDER/planning.json" "len(d[\"subagents\"])")" == "1" && "$(json_get "$FOLDER/planning.json" "d[\"cost_usd\"][\"subagents\"] > 0")" == "True" ]]'
check "S5 two filings are named in warnings" '[[ "$(json_get "$FOLDER/planning.json" "len(d[\"warnings\"])")" == "1" ]]'
check "S5 the shape carries slug, captured_at, rates_source, session" '[[ "$(json_get "$FOLDER/planning.json" "sorted(k for k in (\"slug\",\"captured_at\",\"rates_source\",\"sessions\",\"priced\",\"cost_usd\",\"duration_s\") if k in d) == sorted([\"slug\",\"captured_at\",\"rates_source\",\"sessions\",\"priced\",\"cost_usd\",\"duration_s\"])")" == "True" ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=x slug=y >/dev/null
"$AT/orchestration-start.sh" ghost --session "ffffffff-0000-0000-0000-000000000009" >/dev/null 2>&1
"$AT/orchestration-capture.sh" ghost >/dev/null 2>&1; rc=$?
check "S5 a session with no transcript is refused (1)" '[[ $rc -eq 1 && ! -e "$AT/self/orchestrations/ghost/planning.json" ]]'

echo "== S6 group report =="
# Feature a: a total. b: a report with no total. c: no path (above). d: a path that is not there.
mkdir -p "$AT/self/features/feat-a" "$AT/self/features/feat-b"
printf '{"slug":"feat-a","cost":{"total":1.5}}\n' > "$AT/self/features/feat-a/report.json"
printf '{"slug":"feat-b","cost":{"method":"direct"}}\n' > "$AT/self/features/feat-b/report.json"
# Drop the filler entries S5 and S3 added so the table is exactly a, b, c, d.
python3 - "$RECORD" <<'PY'
import json, re, sys
path = sys.argv[1]
text = open(path).read()
d = json.loads(re.findall(r"```json\n(.*?)\n```", text, re.S)[-1])
d["features"] = [f for f in d["features"] if f["repo"] != "other" and f["slug"] != "y"]
d["features"][0]["pr"] = "https://example.test/pr/1"
text = re.sub(r"```json\n.*?\n```", lambda m: "```json\n" + json.dumps(d, indent=1) + "\n```", text, flags=re.S)
open(path, "w").write(text)
PY
"${REPORT[@]}" --orchestration "$SLUG" >/dev/null; rc=$?
check "S6 the report exits 0 and writes report.md and report.json" '[[ $rc -eq 0 && -f "$FOLDER/report.md" && -f "$FOLDER/report.json" ]]'
check "S6 one row per feature" '[[ "$(json_get "$FOLDER/report.json" "len(d[\"features\"])")" == "4" ]]'
check "S6 a feature with a total is priced from its report.json" '[[ "$(json_get "$FOLDER/report.json" "d[\"features\"][0][\"total_usd\"]")" == "1.5" ]]'
check "S6 no total in the file -> unpriced, reason says so" '[[ "$(json_get "$FOLDER/report.json" "d[\"features\"][1][\"unpriced_reason\"]")" == "no total in "* ]]'
check "S6 no path -> unpriced, reason says so" '[[ "$(json_get "$FOLDER/report.json" "d[\"features\"][2][\"unpriced_reason\"]")" == "no report path in the record" ]]'
check "S6 path missing -> unpriced, reason names the path" '[[ "$(json_get "$FOLDER/report.json" "d[\"features\"][3][\"unpriced_reason\"]")" == *"self/features/feat-d/report.json" ]]'
check "S6 three unpriced, one priced" '[[ "$(json_get "$FOLDER/report.json" "(d[\"unpriced_count\"], d[\"priced_count\"])")" == "(3, 1)" ]]'
check "S6 overhead is the orchestrator planning.json total" '[[ "$(json_get "$FOLDER/report.json" "round(d[\"overhead\"][\"usd\"], 9)")" == "$EXPECT" ]]'
check "S6 group total is priced features plus overhead" '[[ "$(json_get "$FOLDER/report.json" "round(d[\"group_total_usd\"] - 1.5 - d[\"overhead\"][\"usd\"], 9)")" == "0.0" ]]'
check "S6 overhead percentage is overhead over the group total" '[[ "$(json_get "$FOLDER/report.json" "round(d[\"overhead_pct\"] - d[\"overhead\"][\"usd\"] / d[\"group_total_usd\"] * 100, 6)")" == "0.0" ]]'
check "S6 report.json header: slug, session, short id, window" '[[ "$(json_get "$FOLDER/report.json" "d[\"slug\"]+\" \"+d[\"session\"]+\" \"+d[\"agent_tooling_short\"]+\" \"+d[\"session_window\"][\"from\"]")" == "$SLUG $SESSION ${HEAD_ID:0:7} 2026-07-02T09:00:00Z" ]]'
check "S6 report.md names the header, the rows, overhead and the unpriced count" 'grep -q "^# Orchestration report: $SLUG" "$FOLDER/report.md" && grep -q "agentTooling: \`${HEAD_ID:0:7}\`" "$FOLDER/report.md" && grep -q "| agentTooling | feat-a | https://example.test/pr/1 | \$1.5000 |" "$FOLDER/report.md" && grep -q "unpriced (no report path in the record)" "$FOLDER/report.md" && grep -q "^Overhead" "$FOLDER/report.md" && grep -q "3 feature(s) are unpriced and are NOT in the group total" "$FOLDER/report.md"'
rm -f "$FOLDER/planning.json"
"${REPORT[@]}" --orchestration "$SLUG" >/dev/null
check "S6 an uncaptured overhead reads unpriced: not captured, and the total is the features" '[[ "$(json_get "$FOLDER/report.json" "d[\"overhead\"][\"unpriced_reason\"]")" == "not captured" && "$(json_get "$FOLDER/report.json" "d[\"group_total_usd\"]")" == "1.5" && "$(json_get "$FOLDER/report.json" "d[\"overhead_pct\"]")" == "None" ]] && grep -q "unpriced: not captured" "$FOLDER/report.md"'

echo ""
if (( fails )); then
  echo "orchestration-records: $fails check(s) FAILED"
  exit 1
fi
echo "orchestration-records: all checks passed"
