#!/usr/bin/env bash
set -uo pipefail

# Self-test for coordinator records (self/features/coordinator-cost-records): the record of a
# session that coordinates several features through Agent delegates, priced on a line of its
# own beside them, and the start's advisory that names one no record claims. Run by
# self/gate.sh, or by hand: bash self/tests/coordinator-records.sh
#
# Asserts:
#   K1. `orchestration-start.sh <slug> --coordinator --session K` writes a fence with
#       `"kind": "coordinator"` (after `slug`), `from` = K's first transcript instant, and
#       the coordinator prose; it is NOT refused by the reverse guard in a checkout whose
#       tracked manifest names the current branch (a plain start there is); `--from` sets
#       `from` in either kind, and a malformed `--from` is refused writing nothing; a
#       session id outside ^[A-Za-z0-9_][A-Za-z0-9_-]*$ (at most 128 characters) (a quote, `*`, a space, a newline, …), from
#       `--session` or $CLAUDE_CODE_SESSION_ID, is refused writing nothing, and a
#       `session_…` id is accepted (self/features/hook-role-hardening/, F2); run through a
#       symlink beside a planted plan-runner-roots.sh, the start sources its own library and
#       writes under the real tooling directory (that feature's audit round 4);
#   K2. the record is no role: hooks/orchestrator_role.py prints nothing for K, and
#       plan-runner-roots.sh's refuse_orchestrator_session returns 0 for K (a plain record's
#       session is still refused);
#   K3. `orchestration-capture.sh` on a coordinator record prices K's own transcript plus
#       the one delegate that is its own (brief `feature: none — …`, claimed by nobody), and
#       lists in `subagents_not_priced` the delegate briefed for a feature, the `none`
#       delegate the claims ledger holds and the one a manifest pins; `kind` is
#       `coordinator`; a manifest pinning K in `sessions` is named in `warnings`; an
#       orchestrator's record still prices every delegate and has no `subagents_not_priced`;
#   K4. `report.py --orchestration` on it: `kind` in report.json, the coordination wording
#       in report.md, a feature in another repository priced through `--checkout
#       REPO=PATH`, unpriced with the `--checkout` reason without it, and `--checkout`
#       malformed, naming no directory, or without `--orchestration` is a usage error;
#   K5. `analysis/coordinator_check.py`: a session whose first `cwd` is outside the checkout
#       and in no git checkout gets both lines (naming `--coordinator --session <id>` and the
#       missing hooks); outside the checkout but in another checkout, only the first; inside
#       the checkout, recorded by any record, or with no transcript, nothing; exit 0 always;
#   K6. a coordinator record keeps its shape (self/features/hook-role-hardening/, F1(b)):
#       `manifest.py --orchestration` refuses `session=`/`branch=` on its features (null is
#       allowed, and an orchestrator record still takes both), and a record saying
#       `coordinator` whose features carry a branch is read as a role.
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/coordinator-records.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
FAKE_HOME="$TMP/home"
export HOME="$FAKE_HOME"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
unset CLAUDE_CODE_SESSION_ID

mkdir -p "$AT/analysis" "$AT/hooks" "$AT/templates/plans/features" "$AT/self/features" "$FAKE_HOME/.claude/projects"
mkdir -p "$AT/hooks" && cp "$HERE/hooks/shared_rules.py" "$AT/hooks/"  # roots.py imports it
for f in pricing.py litellm_prices.py rates_history.json roots.py transcript.py routing.py manifest.py capture_planning.py report.py orchestration_capture.py coordinator_check.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done
cp "$HERE/hooks/brief_header.py" "$HERE/hooks/orchestrator_role.py" "$AT/hooks/"
cp "$HERE/templates/plans/features/TEMPLATE.md" "$AT/templates/plans/features/TEMPLATE.md"
cp "$HERE/orchestration-start.sh" "$HERE/orchestration-capture.sh" "$HERE/plan-runner-roots.sh" "$AT/"
git -C "$AT" init -q -b claude/held
git -C "$AT" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# The fixture is agentTooling's own checkout, so every record call is `--self`; the
# consuming-repo mode is self/tests/orchestration-records-in-repo.sh
MANIFEST=(python3 -B "$AT/analysis/manifest.py" --self)
REPORT=(python3 -B "$AT/analysis/report.py" --self)
CHECK=(python3 -B "$AT/analysis/coordinator_check.py")
MODEL="claude-sonnet-5"
K="cccccccc-0000-0000-0000-000000000001"
O="dddddddd-0000-0000-0000-000000000002"
U_ROLE="abababab-0000-0000-0000-000000000008"   # K6's hand-edited record
SLUG="wave"
FOLDER="$AT/self/orchestrations/$SLUG"
RECORD="$FOLDER/README.md"
PROJ="$FAKE_HOME/.claude/projects/-home-user"
fence_get() {
  python3 -c '
import json, re, sys
text = open(sys.argv[1]).read()
d = json.loads(re.findall(r"```json\n(.*?)\n```", text, re.S)[-1])
print(eval(sys.argv[2]))' "$1" "$2"
}
json_get() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }

# K's transcript: launched outside every checkout (cwd $TMP/outside), two own responses, and
# four delegates — one briefed for a feature, one `none` it owns, one `none` the ledger
# claims, one `none` a manifest pins.
mkdir -p "$PROJ/$K/subagents" "$TMP/outside"
{
  session_line "$K" "$TMP/outside" HEAD m1 "$MODEL" 2026-07-02T10:00:00.000Z 1000 500 0 0 0
  session_line "$K" "$TMP/outside" HEAD m2 "$MODEL" 2026-07-02T11:00:00.000Z 2000 700 0 0 0
} > "$PROJ/$K.jsonl"
delegate() {  # delegate AGENT_ID PROMPT INPUT
  {
    subagent_prompt_line "$K" "$1" "$TMP/outside" HEAD 2026-07-02T10:10:00.000Z "$2"
    subagent_line "$K" "$1" "$TMP/outside" HEAD "s-$1" "$MODEL" 2026-07-02T10:20:00.000Z "$3" 100 0 0 0
  } > "$PROJ/$K/subagents/agent-$1.jsonl"
}
A_FEATURE="a1111111111111111"; A_OWN="a2222222222222222"; A_LEDGER="a3333333333333333"; A_PINNED="a4444444444444444"
delegate "$A_FEATURE" "feature: agentTooling/feat-a build it" 5000
delegate "$A_OWN" "feature: none — analysis for the coordinator" 300
delegate "$A_LEDGER" "feature: none — bookkeeping someone claimed" 7000
delegate "$A_PINNED" "feature: none — pinned by hand" 9000
printf '{"subagents": {"%s": {"repo_name": "other", "slug": "x"}}, "sessions": {}, "seen": {}}\n' "$A_LEDGER" > "$FAKE_HOME/.claude/subagent-claims.json"

echo "== K1 start --coordinator =="
# A tracked manifest naming the current branch: the plain start's reverse guard refuses here.
"${MANIFEST[@]}" --self held init --method direct --branch claude/held --base main --from 2026-07-01T00:00:00Z >/dev/null
"${MANIFEST[@]}" --self held pin-subagent "$A_PINNED" >/dev/null
"${MANIFEST[@]}" --self held pin-session "$K" >/dev/null
git -C "$AT" add self/features/held >/dev/null
git -C "$AT" -c user.name=t -c user.email=t@example.com commit -q -m held
"$AT/orchestration-start.sh" --self plain-here --session "$O" >/dev/null 2>&1; rc=$?
check "K1 a plain start is refused by the reverse guard here (1)" '[[ $rc -eq 1 && ! -e "$AT/self/orchestrations/plain-here" ]]'
out="$("$AT/orchestration-start.sh" --self "$SLUG" --coordinator --session "$K" 2>&1)"; rc=$?
check "K1 a coordinator start is not refused and writes the record" '[[ $rc -eq 0 && -f "$RECORD" ]]'
check "K1 a coordinator start writes nothing to the orchestrator ledger" '! grep -qs "$K" "$AT/.git/agenttooling-orchestrators"'
check "K1 the fence carries kind coordinator" '[[ "$(fence_get "$RECORD" "d[\"kind\"]")" == "coordinator" ]]'
check "K1 kind is written after slug" '[[ "$(fence_get "$RECORD" "list(d)[:3]")" == "['"'"'slug'"'"', '"'"'kind'"'"', '"'"'session'"'"']" ]]'
check "K1 from is the session's first transcript instant" '[[ "$(fence_get "$RECORD" "d[\"session_window\"][\"from\"]")" == "2026-07-02T10:00:00.000Z" ]]'
check "K1 the prose says it is a coordinator record and no role" 'grep -q "coordinator record" "$RECORD" && grep -q "The record is no" "$RECORD"'
"$AT/orchestration-start.sh" --self with-from --coordinator --session "$O" --from 2026-07-03T00:00:00Z >/dev/null 2>&1
check "K1 --from sets from" '[[ "$(fence_get "$AT/self/orchestrations/with-from/README.md" "d[\"session_window\"][\"from\"]")" == "2026-07-03T00:00:00Z" ]]'
"$AT/orchestration-start.sh" --self bad-from --coordinator --session "$O" --from yesterday >/dev/null 2>&1; rc=$?
check "K1 a malformed --from is refused writing nothing (1)" '[[ $rc -eq 1 && ! -e "$AT/self/orchestrations/bad-from" ]]'
rm -rf "$AT/self/orchestrations/with-from"
# F2 (self/features/hook-role-hardening/): the session id is written into the fence
# unescaped, so one outside ^[A-Za-z0-9_][A-Za-z0-9_-]*$ (at most 128 characters) is refused, writing nothing, in either kind
# and through either source; the ids Claude Code issues are accepted.
n=0
for bad in 'a", "kind": "coordinator' '*' 'a b' $'a\nb' 'a\b' 'café' ''"'"'x'; do
  n=$((n + 1))
  "$AT/orchestration-start.sh" --self "bad-session-$n" --coordinator --session "$bad" >/dev/null 2>&1; rc=$?
  check "K1 a session id $(printf '%q' "$bad") is refused writing nothing (1)" '[[ $rc -eq 1 && ! -e "$AT/self/orchestrations/bad-session-$n" ]]'
done
CLAUDE_CODE_SESSION_ID='zz" , "x' "$AT/orchestration-start.sh" --self bad-env --coordinator >/dev/null 2>&1; rc=$?
check "K1 ... and so is one from \$CLAUDE_CODE_SESSION_ID (1)" '[[ $rc -eq 1 && ! -e "$AT/self/orchestrations/bad-env" ]]'
"$AT/orchestration-start.sh" --self good-session --coordinator --session "session_0175k4pFaCJm1-Z9" --from 2026-07-03T00:00:00Z >/dev/null 2>&1; rc=$?
check "K1 a session_… id with '_' and '-' is accepted (0)" '[[ $rc -eq 0 && "$(fence_get "$AT/self/orchestrations/good-session/README.md" "d[\"session\"]")" == "session_0175k4pFaCJm1-Z9" ]]'
rm -rf "$AT/self/orchestrations/good-session"

# Round 4: run through a symlink placed beside a planted library, the start sources its
# own library — SCRIPT_DIR is resolved before anything is sourced — and writes its record
# under the real tooling directory, never beside the link.
LINKDIR="$TMP/linked"
mkdir -p "$LINKDIR"
ln -s "$AT/orchestration-start.sh" "$LINKDIR/orchestration-start.sh"
printf 'touch "%s/planted-ran"\n' "$TMP" > "$LINKDIR/plan-runner-roots.sh"
( cd "$LINKDIR" && ./orchestration-start.sh --self via-link --coordinator --session "$O" --from 2026-07-03T00:00:00Z >/dev/null 2>&1 ); rc=$?
check "K1 a symlinked orchestration-start.sh sources its own library, not one planted beside the link (0)" \
  '[[ $rc -eq 0 && ! -e "$TMP/planted-ran" && -f "$AT/self/orchestrations/via-link/README.md" && ! -e "$LINKDIR/self" ]]'
rm -rf "$AT/self/orchestrations/via-link"

echo "== K2 no role =="
check "K2 orchestrator_role.py prints nothing for the coordinator" '[[ -z "$(python3 -B "$AT/hooks/orchestrator_role.py" "$AT" "$K")" ]]'
git -C "$AT" add "self/orchestrations/$SLUG" >/dev/null
git -C "$AT" -c user.name=t -c user.email=t@example.com commit -q -m "coordinator record"
check "K2 committed as a coordinator, the record is still no role (the history reads it as first committed)" '[[ -z "$(python3 -B "$AT/hooks/orchestrator_role.py" -- "$AT" "$K")" ]]'
check "K2 refuse_orchestrator_session returns 0 for the coordinator" 'bash -c "source \"$AT/plan-runner-roots.sh\"; refuse_orchestrator_session \"$K\"" 2>/dev/null'
mkdir -p "$AT/self/orchestrations/orch"
printf '# x\n\n```json\n{"slug": "orch", "session": "%s", "features": []}\n```\n' "$O" > "$AT/self/orchestrations/orch/README.md"
check "K2 a plain record's session is still refused" '! bash -c "source \"$AT/plan-runner-roots.sh\"; refuse_orchestrator_session \"$O\"" 2>/dev/null'

echo "== K3 capture =="
"${MANIFEST[@]}" --orchestration "$SLUG" set-window-to 2026-07-02T12:00:00Z >/dev/null
"$AT/orchestration-capture.sh" --self "$SLUG" >"$TMP/capture.out" 2>&1; rc=$?
P="$FOLDER/planning.json"
check "K3 capture exits 0 and writes planning.json" '[[ $rc -eq 0 && -f "$P" ]]'
EXPECT="$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from pricing import compute_cost
def tok(i, o): return {"input": i, "output": o, "cache_read": 0, "cache_creation_5m": 0, "cache_creation_1h": 0}
main, _ = compute_cost(sys.argv[2], tok(3000, 1200), as_of="2026-07-02")
own, _ = compute_cost(sys.argv[2], tok(300, 100), as_of="2026-07-02")
print(round(main + own, 9))' "$AT/analysis" "$MODEL")"
check "K3 total is the own transcript plus its own none-briefed delegate" '[[ "$(json_get "$P" "round(d[\"cost_usd\"][\"total\"], 9)")" == "$EXPECT" ]]'
check "K3 the one priced delegate is its own" '[[ "$(json_get "$P" "[a[\"agent_id\"] for a in d[\"subagents\"]]")" == "['"'"'$A_OWN'"'"']" ]]'
check "K3 the feature-briefed, ledger-claimed and pinned delegates are listed, not priced" '[[ "$(json_get "$P" "d[\"subagents_not_priced\"]")" == "['"'"'$A_FEATURE'"'"', '"'"'$A_LEDGER'"'"', '"'"'$A_PINNED'"'"']" ]]'
check "K3 kind is coordinator" '[[ "$(json_get "$P" "d[\"kind\"]")" == "coordinator" ]]'
check "K3 a manifest pinning the coordinator session is warned about" '[[ "$(json_get "$P" "any(\"self/features/held\" in w and \"$K\" in w for w in d[\"warnings\"])")" == "True" ]]'
# An orchestrator record on the same session prices every delegate, as before.
mkdir -p "$AT/self/orchestrations/as-orch"
printf '# x\n\n```json\n{"slug": "as-orch", "session": "%s", "session_window": {"from": "2026-07-02T09:00:00Z", "to": "2026-07-02T12:00:00Z"}, "features": []}\n```\n' "$K" > "$AT/self/orchestrations/as-orch/README.md"
"$AT/orchestration-capture.sh" --self as-orch >/dev/null 2>&1
check "K3 an orchestrator record prices all four delegates and lists none" '[[ "$(json_get "$AT/self/orchestrations/as-orch/planning.json" "(len(d[\"subagents\"]), \"subagents_not_priced\" in d, d[\"kind\"])")" == "(4, False, '"'"'orchestrator'"'"')" ]]'
rm -rf "$AT/self/orchestrations/as-orch"

echo "== K4 report =="
OTHER="$TMP/otherRepo"
mkdir -p "$OTHER/plans/features/feat-b" "$AT/self/features/feat-a"
printf '{"cost":{"total":2.0}}\n' > "$AT/self/features/feat-a/report.json"
printf '{"cost":{"total":3.0}}\n' > "$OTHER/plans/features/feat-b/report.json"
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=agentTooling slug=feat-a report=self/features/feat-a/report.json >/dev/null
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=otherRepo slug=feat-b report=plans/features/feat-b/report.json >/dev/null
"${REPORT[@]}" --orchestration "$SLUG" >/dev/null; rc=$?
R="$FOLDER/report.json"
check "K4 the report exits 0" '[[ $rc -eq 0 && -f "$R" ]]'
check "K4 report.json carries kind coordinator" '[[ "$(json_get "$R" "d[\"kind\"]")" == "coordinator" ]]'
check "K4 another repo with no --checkout is unpriced, naming --checkout" '[[ "$(json_get "$R" "d[\"features\"][1][\"unpriced_reason\"]")" == "in otherRepo: pass --checkout otherRepo=<its checkout>" ]]'
"${REPORT[@]}" --orchestration "$SLUG" --checkout "otherRepo=$OTHER" >/dev/null
check "K4 --checkout prices the other repo's feature" '[[ "$(json_get "$R" "(d[\"features\"][0][\"total_usd\"], d[\"features\"][1][\"total_usd\"], d[\"unpriced_count\"])")" == "(2.0, 3.0, 0)" ]]'
check "K4 the group total is both features plus the coordinator line" '[[ "$(json_get "$R" "abs(d[\"group_total_usd\"] - 5.0 - d[\"overhead\"][\"usd\"]) < 1e-9")" == "True" ]]'
check "K4 report.md uses the coordination wording" 'grep -q "^# Coordination report: $SLUG" "$FOLDER/report.md" && grep -q "^Coordinator session: \`$K\`" "$FOLDER/report.md" && grep -q "^Coordination overhead (the coordinator" "$FOLDER/report.md"'
"${REPORT[@]}" --orchestration "$SLUG" --checkout "otherRepo" >/dev/null 2>&1; rc=$?
check "K4 a --checkout with no = is a usage error (2)" '[[ $rc -eq 2 ]]'
"${REPORT[@]}" --orchestration "$SLUG" --checkout "otherRepo=$TMP/nope" >/dev/null 2>&1; rc=$?
check "K4 a --checkout naming no directory is a usage error (2)" '[[ $rc -eq 2 ]]'
"${REPORT[@]}" --self feat-a --checkout "otherRepo=$OTHER" >/dev/null 2>&1; rc=$?
check "K4 --checkout without --orchestration is a usage error (2)" '[[ $rc -eq 2 ]]'
"${REPORT[@]}" --orchestration orch >/dev/null 2>&1
check "K4 a plain record keeps the orchestration wording" 'grep -q "^# Orchestration report: orch" "$AT/self/orchestrations/orch/report.md" && [[ "$(json_get "$AT/self/orchestrations/orch/report.json" "d[\"kind\"]")" == "orchestrator" ]]'

echo "== K6 a coordinator record keeps its shape =="
# self/features/hook-role-hardening/, F1(b): a coordinator record whose features carry a
# session or branch has the orchestrator's shape and is a role, so manifest.py refuses to
# write either into one; clearing one (null) is allowed.
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=agentTooling slug=feat-c session=s1 >/dev/null 2>&1; rc=$?
check "K6 add-feature session= on a coordinator record is refused (1)" '[[ $rc -eq 1 && "$(fence_get "$RECORD" "[f[\"slug\"] for f in d[\"features\"]]")" != *feat-c* ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" set-feature repo=agentTooling slug=feat-a branch=claude/x >/dev/null 2>&1; rc=$?
check "K6 set-feature branch= on a coordinator record is refused (1)" '[[ $rc -eq 1 && "$(fence_get "$RECORD" "d[\"features\"][0][\"branch\"]")" == "None" ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" set-feature repo=agentTooling slug=feat-a session=null >/dev/null 2>&1; rc=$?
check "K6 set-feature session=null on a coordinator record is allowed (0)" '[[ $rc -eq 0 ]]'
check "K6 the record is still no role" '[[ -z "$(python3 -B "$AT/hooks/orchestrator_role.py" "$AT" "$K")" ]]'
"${MANIFEST[@]}" --orchestration orch add-feature repo=agentTooling slug=feat-c session=s1 branch=claude/c >/dev/null 2>&1; rc=$?
check "K6 an orchestrator record still takes session= and branch= (0)" '[[ $rc -eq 0 ]]'
# A coordinator kind on an orchestrator's shape is a role (the hand-edit F1 describes)
mkdir -p "$AT/self/orchestrations/edited"
printf '# x\n\n```json\n{"slug": "edited", "kind": "coordinator", "session": "%s", "features": [{"repo": "r", "slug": "s", "session": null, "branch": "claude/s", "pr": null, "report": null}]}\n```\n' "$U_ROLE" > "$AT/self/orchestrations/edited/README.md"
check "K6 a coordinator kind on an orchestrator-shaped record is still a role" '[[ "$(python3 -B "$AT/hooks/orchestrator_role.py" "$AT" "$U_ROLE")" == "$AT/self/orchestrations/edited/README.md" ]]'
rm -rf "$AT/self/orchestrations/edited"

echo "== K5 coordinator_check =="
U="eeeeeeee-0000-0000-0000-000000000005"   # outside every checkout, no record
V="ffffffff-0000-0000-0000-000000000006"   # in another checkout, no record
W="99999999-0000-0000-0000-000000000007"   # inside this checkout
mkdir -p "$TMP/elsewhere"
git -C "$TMP/elsewhere" init -q
session_line "$U" "$TMP/outside" HEAD u1 "$MODEL" 2026-07-02T10:00:00.000Z 1 1 0 0 0 > "$PROJ/$U.jsonl"
session_line "$V" "$TMP/elsewhere" main v1 "$MODEL" 2026-07-02T10:00:00.000Z 1 1 0 0 0 > "$PROJ/$V.jsonl"
session_line "$W" "$AT/analysis" claude/held w1 "$MODEL" 2026-07-02T10:00:00.000Z 1 1 0 0 0 > "$PROJ/$W.jsonl"
out="$("${CHECK[@]}" "$U" "$AT")"; rc=$?
check "K5 outside every checkout: two lines, naming --coordinator and the hooks" '[[ $rc -eq 0 && "$(printf "%s\n" "$out" | wc -l)" -eq 2 && "$out" == *"--coordinator --session $U"* && "$out" == *"no git checkout"* ]]'
out="$("${CHECK[@]}" "$V" "$AT")"
check "K5 in another checkout: the first line only" '[[ "$(printf "%s\n" "$out" | wc -l)" -eq 1 && "$out" == *"--coordinator --session $V"* ]]'
check "K5 inside this checkout: nothing" '[[ -z "$("${CHECK[@]}" "$W" "$AT")" ]]'
check "K5 a session a coordinator record names: nothing" '[[ -z "$("${CHECK[@]}" "$K" "$AT")" ]]'
session_line "$O" "$TMP/outside" HEAD o1 "$MODEL" 2026-07-02T10:00:00.000Z 1 1 0 0 0 > "$PROJ/$O.jsonl"
check "K5 a session an orchestrator record names: nothing" '[[ -z "$("${CHECK[@]}" "$O" "$AT")" ]]'
check "K5 no transcript, or no arguments: nothing, exit 0" '[[ -z "$("${CHECK[@]}" "12121212-0000-0000-0000-000000000000" "$AT")" && -z "$("${CHECK[@]}")" ]]'

echo ""
if (( fails )); then
  echo "coordinator-records: $fails check(s) FAILED"
  exit 1
fi
echo "coordinator-records: all checks passed"
