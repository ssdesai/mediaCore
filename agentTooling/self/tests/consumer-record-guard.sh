#!/usr/bin/env bash
set -uo pipefail

# Self-test for the write guard on a vendored copy's own record root (self/features/
# consumer-record-guard/): when agentTooling is vendored in a consuming repo, no record tool
# writes under the vendored `agentTooling/self/orchestrations/` — not even under `--self` —
# because a file there is a local edit to code every repo receives; each writer refuses
# before any write, naming `plans/orchestrations/<slug>/`. agentTooling's own standalone
# checkout writes there under `--self` as before, and a shipped record in a vendored copy
# still reads. Run by self/gate.sh, or by hand: bash self/tests/consumer-record-guard.sh
#
# Asserts:
#   C1. in a consuming repo with a vendored copy, `orchestration-start.sh --self <slug>` —
#       orchestrator and `--coordinator` — refuses (1) with roots.py's
#       VENDORED_SELF_WRITE_REFUSAL naming `plans/orchestrations/<slug>/`, and writes nothing:
#       no record folder in either root, no ledger line;
#   C2. against a record shipped under the vendored `self/orchestrations/` (with a transcript
#       a capture could price, so only the guard stands in the way): `manifest.py --self
#       --orchestration … add-feature`, `set-feature` and `set-window-to`,
#       `orchestration-capture.sh --self`, `orchestration_capture.py --self` and
#       `report.py --self --orchestration` each refuse (1) with the same text and write
#       nothing — the record byte for byte, no planning.json, no report files;
#   C3. reading that shipped record is unaffected: `manifest.py --self --orchestration … get`
#       exits 0 with the value, hooks/orchestrator_role.py still finds its session's role, and
#       analysis/coordinator_check.py still counts it as naming its session (a session no
#       record names still draws the advisory);
#   C4. the no-`--self` start in the consumer still writes `plans/orchestrations/<slug>/`;
#   C5. in a standalone agentTooling checkout every one of those writers still works under
#       `--self`: both starts, add-feature, set-feature, set-window-to, the capture
#       (planning.json) and the report (report.json, report.md);
#   C6. the decision is roots.py's: `roots.py self-write <slug>` (what the shell start asks)
#       exits 1 printing the refusal in the vendored copy and 0 in the standalone checkout;
#       with roots.py missing, the standalone `--self` start refuses (1) — it fails closed —
#       and writes nothing.
#   C7. (orchestrator-move-length-cap) the standalone `roots.py self-write` go-ahead is exit 0
#       printing exactly shared_rules.ROOTS_CLI_GO_AHEAD; with roots.py emptied, or a stub that
#       exits 0 printing nothing or another line, the `--self` start refuses (1) and writes nothing.
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/consumer-record-guard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
CONSUMER="$TMP/consumer"
AT="$CONSUMER/agentTooling"
SA="$TMP/standalone/agentTooling"
FAKE_HOME="$TMP/home"
export HOME="$FAKE_HOME"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
unset CLAUDE_CODE_SESSION_ID

ANALYSIS_FILES="pricing.py litellm_prices.py rates_history.json roots.py transcript.py routing.py manifest.py capture_planning.py report.py orchestration_capture.py coordinator_check.py"
# vendor_tooling <dir>: the scripts this test runs, copied to <dir>
vendor_tooling() {
  mkdir -p "$1/analysis" "$1/hooks" "$1/templates/plans/features" "$1/self/features"
  for f in $ANALYSIS_FILES; do
    cp "$HERE/analysis/$f" "$1/analysis/$f"
  done
  # roots.py imports shared_rules.py; capture_planning.py brief_header.py
  cp "$HERE/hooks/shared_rules.py" "$HERE/hooks/brief_header.py" "$HERE/hooks/orchestrator_role.py" "$1/hooks/"
  cp "$HERE/templates/plans/features/TEMPLATE.md" "$1/templates/plans/features/TEMPLATE.md"
  cp "$HERE/orchestration-start.sh" "$HERE/orchestration-capture.sh" "$HERE/plan-runner-roots.sh" "$1/"
  # The start decides the profile through env-profile.sh (orchestration-start-branch-v2)
  cp "$HERE/env-profile.sh" "$1/"; cp "$HERE/hooks/env_profile.py" "$1/hooks/"
}
# Pinned local: the cloud branch rule is orchestrator-role.sh's B
export AGENTTOOLING_PROFILE=local
GIT_ID=(-c user.name=t -c user.email=t@example.com)
mkdir -p "$FAKE_HOME/.claude/projects"
# The consuming repo is the checkout; the vendored agentTooling has no `.git` of its own.
vendor_tooling "$AT"
git -C "$CONSUMER" init -q -b main
git -C "$CONSUMER" "${GIT_ID[@]}" commit -q --allow-empty -m init
# agentTooling's own checkout, with no consuming repo above it.
vendor_tooling "$SA"
git -C "$SA" init -q -b main
git -C "$SA" "${GIT_ID[@]}" commit -q --allow-empty -m init

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

PLANS_REL="plans/orchestrations"
SELF_REL="self/orchestrations"
LEDGER_REL=".git/agenttooling-orchestrators"
MODEL="claude-sonnet-5"
O="dddddddd-0000-0000-0000-00000000000b"
K="cccccccc-0000-0000-0000-00000000000a"
L="eeeeeeee-0000-0000-0000-00000000000c"  # the shipped record's orchestrator
SHIPPED="shipped"
# refusal_text <slug>: roots.py's own refusal, formatted for <slug>
refusal_text() {
  python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import roots; print(roots.VENDORED_SELF_WRITE_REFUSAL.format(slug=sys.argv[2]))' \
    "$HERE/analysis" "$1"
}
# The one line roots.py's self-write prints on the go-ahead (a shared rule, read, not restated)
GO_AHEAD="$(python3 -B "$HERE/hooks/shared_rules.py" ROOTS_CLI_GO_AHEAD)"
# snap: every path and its content hash under both record roots and the ledger
snap() {
  find "$CONSUMER/plans" "$AT/self" "$CONSUMER/$LEDGER_REL" -type f -exec cksum {} + 2>/dev/null | sort
  find "$CONSUMER/plans" "$AT/self" -type d 2>/dev/null | sort
}
json_get() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }
# A transcript for <session> a capture would price
transcript() {
  mkdir -p "$FAKE_HOME/.claude/projects/-w"
  session_line "$1" /w main m1 "$MODEL" 2026-07-02T10:00:00.000Z 1000 500 0 0 0 > "$FAKE_HOME/.claude/projects/-w/$1.jsonl"
}
transcript "$L"
transcript "$O"

echo "== C1 a --self start in a vendored copy refuses before any write =="
before="$(snap)"
out="$("$AT/orchestration-start.sh" --self wave --session "$O" 2>&1)"; rc=$?
check "C1 orchestrator start refuses (1) naming plans/orchestrations/wave/ (got $rc)" '[[ $rc -eq 1 && "$out" == *"$(refusal_text wave)"* && "$out" == *"$PLANS_REL/wave/"* ]]'
out="$("$AT/orchestration-start.sh" --self wave --coordinator --session "$K" 2>&1)"; rc=$?
check "C1 coordinator start refuses (1) with the same text (got $rc)" '[[ $rc -eq 1 && "$out" == *"$(refusal_text wave)"* ]]'
check "C1 the refusals wrote nothing: no record folder in either root, no ledger line" '[[ "$(snap)" == "$before" && ! -e "$AT/$SELF_REL/wave" && ! -e "$CONSUMER/$PLANS_REL/wave" ]]'

echo "== C2 every other writer refuses on a shipped record =="
mkdir -p "$AT/$SELF_REL/$SHIPPED"
printf '# s\n\n```json\n{"slug": "%s", "session": "%s", "session_window": {"from": "2026-07-02T09:00:00Z", "to": null}, "features": [{"repo": "agentTooling", "slug": "feat-s", "session": null, "branch": null, "pr": null, "report": null}]}\n```\n' \
  "$SHIPPED" "$L" > "$AT/$SELF_REL/$SHIPPED/README.md"
before="$(snap)"
TEXT="$(refusal_text "$SHIPPED")"
out="$(python3 -B "$AT/analysis/manifest.py" --self --orchestration "$SHIPPED" add-feature repo=agentTooling slug=feat-t 2>&1)"; rc=$?
check "C2 manifest.py add-feature refuses (1) (got $rc)" '[[ $rc -eq 1 && "$out" == *"$TEXT"* ]]'
out="$(python3 -B "$AT/analysis/manifest.py" --self --orchestration "$SHIPPED" set-feature repo=agentTooling slug=feat-s pr=x 2>&1)"; rc=$?
check "C2 manifest.py set-feature refuses (1) (got $rc)" '[[ $rc -eq 1 && "$out" == *"$TEXT"* ]]'
out="$(python3 -B "$AT/analysis/manifest.py" --self --orchestration "$SHIPPED" set-window-to now 2>&1)"; rc=$?
check "C2 manifest.py set-window-to refuses (1) (got $rc)" '[[ $rc -eq 1 && "$out" == *"$TEXT"* ]]'
out="$("$AT/orchestration-capture.sh" --self "$SHIPPED" 2>&1)"; rc=$?
check "C2 orchestration-capture.sh --self refuses (1) (got $rc)" '[[ $rc -eq 1 && "$out" == *"$TEXT"* ]]'
out="$(python3 -B "$AT/analysis/orchestration_capture.py" --self "$SHIPPED" 2>&1)"; rc=$?
check "C2 orchestration_capture.py --self refuses (1) (got $rc)" '[[ $rc -eq 1 && "$out" == *"$TEXT"* ]]'
out="$(python3 -B "$AT/analysis/report.py" --self --orchestration "$SHIPPED" 2>&1)"; rc=$?
check "C2 report.py --self --orchestration refuses (1) (got $rc)" '[[ $rc -eq 1 && "$out" == *"$TEXT"* ]]'
check "C2 the refusals wrote nothing: the record byte for byte, no planning.json, no report" '[[ "$(snap)" == "$before" && ! -e "$AT/$SELF_REL/$SHIPPED/planning.json" && ! -e "$AT/$SELF_REL/$SHIPPED/report.json" ]]'

echo "== C3 reading a shipped record is unaffected =="
out="$(python3 -B "$AT/analysis/manifest.py" --self --orchestration "$SHIPPED" get session 2>&1)"; rc=$?
check "C3 manifest.py --self get reads the shipped record (got $rc)" '[[ $rc -eq 0 && "$out" == "$L" ]]'
check "C3 the role hook still reads the shipped record" '[[ "$(python3 -B "$AT/hooks/orchestrator_role.py" "$AT" "$L")" == "$AT/$SELF_REL/$SHIPPED/README.md" ]]'
# The advisory would warn for L (its transcript's cwd, /w, is outside the consumer's checkout)
# but for a record naming it: the shipped one. A session no record names is the control.
check "C3 the coordinator advisory still counts the shipped record as naming its session" '[[ -z "$(python3 -B "$AT/analysis/coordinator_check.py" "$L" "$AT")" ]]'
check "C3 ... and warns for a session no record names (the control)" '[[ -n "$(python3 -B "$AT/analysis/coordinator_check.py" "$O" "$AT")" ]]'

echo "== C4 the consumer's own start is unchanged =="
"$AT/orchestration-start.sh" wave --coordinator --session "$K" >/dev/null 2>&1; rc=$?
check "C4 a start without --self writes plans/orchestrations/wave (got $rc)" '[[ $rc -eq 0 && -f "$CONSUMER/$PLANS_REL/wave/README.md" && ! -e "$AT/$SELF_REL/wave" ]]'

echo "== C5 a standalone checkout's --self writers work as before =="
S="$SA/$SELF_REL"
"$SA/orchestration-start.sh" --self orch --session "$O" >/dev/null 2>&1; rc=$?
check "C5 the orchestrator start writes self/orchestrations/orch (got $rc)" '[[ $rc -eq 0 && -f "$S/orch/README.md" ]]'
"$SA/orchestration-start.sh" --self coord --coordinator --session "$K" >/dev/null 2>&1; rc=$?
check "C5 the coordinator start writes self/orchestrations/coord (got $rc)" '[[ $rc -eq 0 && -f "$S/coord/README.md" ]]'
SA_MANIFEST=(python3 -B "$SA/analysis/manifest.py" --self --orchestration orch)
"${SA_MANIFEST[@]}" add-feature repo=agentTooling slug=feat-s >/dev/null 2>&1; rc=$?
check "C5 add-feature writes (got $rc)" '[[ $rc -eq 0 && "$("${SA_MANIFEST[@]}" get features)" == *"feat-s"* ]]'
"${SA_MANIFEST[@]}" set-feature repo=agentTooling slug=feat-s pr=https://example.com/1 >/dev/null 2>&1; rc=$?
check "C5 set-feature writes (got $rc)" '[[ $rc -eq 0 && "$("${SA_MANIFEST[@]}" get features)" == *"https://example.com/1"* ]]'
sed -i.bak 's/"from": "[^"]*"/"from": "2026-07-02T09:00:00Z"/' "$S/orch/README.md" && rm -f "$S/orch/README.md.bak"
"${SA_MANIFEST[@]}" set-window-to 2026-07-02T12:00:00Z >/dev/null 2>&1; rc=$?
check "C5 set-window-to writes (got $rc)" '[[ $rc -eq 0 && "$("${SA_MANIFEST[@]}" get session_window.to)" == "2026-07-02T12:00:00Z" ]]'
"$SA/orchestration-capture.sh" --self orch >/dev/null 2>&1; rc=$?
check "C5 the capture writes planning.json (got $rc)" '[[ $rc -eq 0 && -f "$S/orch/planning.json" ]]'
python3 -B "$SA/analysis/report.py" --self --orchestration orch >/dev/null 2>&1; rc=$?
check "C5 the report writes report.json and report.md (got $rc)" '[[ $rc -eq 0 && -f "$S/orch/report.json" && -f "$S/orch/report.md" ]]'

echo "== C6 the decision is roots.py's =="
out="$(python3 -B "$AT/analysis/roots.py" self-write x)"; v1=$?
python3 -B "$SA/analysis/roots.py" self-write x >/dev/null; v2=$?
check "C6 roots.py self-write: refuses (1) with the text in the vendored copy, allows (0) in the standalone checkout (got $v1, $v2)" '[[ $v1 -eq 1 && "$out" == "$(refusal_text x)" && $v2 -eq 0 ]]'
# With roots.py unaskable the --self start fails closed, even where it would be allowed
SA_LEDGER="$SA/$LEDGER_REL"
sa_before="$(find "$SA/self" "$SA_LEDGER" -type f -exec cksum {} + 2>/dev/null | sort)"
mv "$SA/analysis/roots.py" "$SA/analysis/roots.py.off"
out="$("$SA/orchestration-start.sh" --self closed --session "$L" 2>&1)"; rc=$?
mv "$SA/analysis/roots.py.off" "$SA/analysis/roots.py"
sa_after="$(find "$SA/self" "$SA_LEDGER" -type f -exec cksum {} + 2>/dev/null | sort)"
check "C6 with roots.py missing a --self start refuses (1), saying it cannot ask, and writes nothing (got $rc)" '[[ $rc -eq 1 && "$out" == *"cannot ask"* && ! -e "$S/closed" && "$sa_after" == "$sa_before" ]]'
# C7 (self/features/orchestrator-move-length-cap/): the go-ahead is exit 0 WITH roots.py's fixed
# token, so an emptied roots.py, or a stub that exits 0 printing nothing or anything else,
# refuses the standalone --self start the real classifier allows
out="$(python3 -B "$SA/analysis/roots.py" self-write x)"; rc=$?
check "C7 roots.py self-write (standalone): exit 0 printing exactly the go-ahead '$GO_AHEAD' (got $rc, '$out')" '[[ $rc -eq 0 && "$out" == "$GO_AHEAD" ]]'
mv "$SA/analysis/roots.py" "$SA/analysis/roots.py.off"
for stub in empty exit0 other; do
  case "$stub" in
    empty) : > "$SA/analysis/roots.py" ;;
    exit0) printf 'import sys\nsys.exit(0)\n' > "$SA/analysis/roots.py" ;;
    other) printf 'print("go")\n' > "$SA/analysis/roots.py" ;;
  esac
  out="$("$SA/orchestration-start.sh" --self closed --session "$L" 2>&1)"; rc=$?
  sa_after="$(find "$SA/self" "$SA_LEDGER" -type f -exec cksum {} + 2>/dev/null | sort)"
  check "C7 with a $stub stub roots.py (exit 0, no go-ahead), a --self start refuses (1) and writes nothing (got $rc)" '[[ $rc -eq 1 && "$out" == *"without its go-ahead"* && ! -e "$S/closed" && "$sa_after" == "$sa_before" ]]'
done
mv "$SA/analysis/roots.py.off" "$SA/analysis/roots.py"

echo ""
if (( fails )); then
  echo "consumer-record-guard: $fails check(s) FAILED"
  exit 1
fi
echo "consumer-record-guard: all checks passed"
