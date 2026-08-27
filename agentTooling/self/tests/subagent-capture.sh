#!/usr/bin/env bash
set -uo pipefail

# Self-test for capture_planning.py's subagent attribution. Run by self/gate.sh, or by
# hand: bash self/tests/subagent-capture.sh
#
# Same scaffolding as capture-guard.sh: a throwaway agentTooling checkout under
# mktemp -d, one synthesized feature manifest, and under a redirected $HOME the
# `~/.claude/projects/*/<session_id>.jsonl` transcripts capture selects on — plus, new
# here, the `<session_id>/subagents/agent-<id>.jsonl` files beside them. No model, no
# network; a few seconds.
#
# What it guards. A subagent transcript inherits its parent's `gitBranch` and `cwd` at
# spawn and never records a branch of its own, so an architect spawned from a
# coordinator sitting on `main` says `main` for its whole life — and a branch-matched
# scan never sees it. Measured on one real corpus before this landed: $184 of opus
# plan-authoring across four repos, and the $206 coordinator that spawned it, all
# invisible to `report.py`. Two routes in: a subagent whose parent is selected is priced
# when its own start is in the window; and a manifest `subagents` pin claims one on its
# id alone, bypassing branch and window, because the pin is the human's word.
#
# Asserts, in order:
#   1. a selected parent's in-window subagent is priced: the total rises by exactly
#      `cost_usd.subagents`, and `subagents[]` names it as selected by "parent";
#   2. a subagent of that same parent starting after the window's `to` is not;
#   3. a subagent under a parent on `main` (a branch the manifest does not list) is not
#      priced until the manifest pins its id — then it is, as "pinned", while the
#      parent itself stays unpriced and out of `sessions[]`;
#   4. a pinned id no transcript carries is warned about by id;
#   5. the frozen-cost guard covers subagents: with the subagents directory gone, a
#      re-capture refuses, names `agent-<id>`, and leaves planning.json byte-identical;
#      --force still overrides;
#   6. --list-subagents prints each reachable subagent with its opening prompt, and
#      --since drops the ones that started earlier;
#   7. a subagent of a runner session (its parent claimed by a usage.json) is not
#      priced even when pinned — its cost is already in that sidecar — and the pin is
#      reported unmatched rather than silently dropped;
#   8. two manifests pinning the same id are warned about, naming the other feature.
#
# All RED until the subagent walk landed in analysis/capture_planning.py.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Physical path — roots.py resolves through Path.resolve(); see capture-guard.sh.
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

for f in pricing.py roots.py transcript.py capture_planning.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done
mkdir -p "$AT/.git"

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

SLUG="subagent-capture"
FEATURE_DIR="$AT/self/features/$SLUG"
PLANNING="$FEATURE_DIR/planning.json"
BRANCH="someFeatureBranch"
MODEL="claude-sonnet-5"
SESSION_P="pppppppp-0000-0000-0000-000000000001"   # parent on the feature branch
SESSION_M="mmmmmmmm-0000-0000-0000-000000000002"   # parent on main (a coordinator)
SESSION_R="rrrrrrrr-0000-0000-0000-000000000003"   # runner session, claimed by a usage.json
AGENT_1="a1111111111111111"
AGENT_2="a2222222222222222"
AGENT_3="a3333333333333333"
AGENT_4="a4444444444444444"
WINDOW_FROM="2026-07-01T00:00:00Z"
WINDOW_TO="2026-07-05T00:00:00Z"

FAKE_HOME="$TMP/home"
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/' '-')"
mkdir -p "$PROJECTS" "$FEATURE_DIR"

# write_manifest [PINS_JSON] — PINS_JSON is the `subagents` array, default empty.
write_manifest() {
  local pins="${1:-[]}"
  cat > "$FEATURE_DIR/README.md" <<MANIFEST
# $SLUG

Fixture feature for self/tests/subagent-capture.sh.

\`\`\`json
{
  "slug": "$SLUG",
  "branches": ["$BRANCH"],
  "session_window": {"from": "$WINDOW_FROM", "to": "$WINDOW_TO"},
  "exclude_sessions": [],
  "subagents": $pins
}
\`\`\`
MANIFEST
}

# write_parent SESSION_ID BRANCH TIMESTAMP OUTPUT_TOKENS
write_parent() {
  session_line "$1" "$AT" "$2" "msg-$1" "$MODEL" "$3" 100 "$4" 0 0 0 > "$PROJECTS/$1.jsonl"
}
# write_subagent SESSION_ID AGENT_ID BRANCH TIMESTAMP OUTPUT_TOKENS PROMPT
write_subagent() {
  mkdir -p "$PROJECTS/$1/subagents"
  {
    subagent_prompt_line "$1" "$2" "$AT" "$3" "$4" "$6"
    subagent_line "$1" "$2" "$AT" "$3" "msg-$2" "$MODEL" "$4" 100 "$5" 0 0 0
  } > "$PROJECTS/$1/subagents/agent-$2.jsonl"
}

capture()   { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self "$SLUG" --recapture "$@" 2>&1; }
list_subs() { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self --list-subagents "$@" 2>&1; }

field() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$PLANNING" "$1"; }
total_of() { field "d['cost_usd']['total']"; }
near()  { python3 -c "import sys; sys.exit(0 if abs(float(sys.argv[1]) - float(sys.argv[2])) < 1e-9 else 1)" "$1" "$2"; }
gt()    { python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) else 1)" "$1" "$2"; }

echo "capture_planning subagent attribution"

# ── 1. a selected parent's in-window subagent is priced ───────────────────────
write_manifest
write_parent "$SESSION_P" "$BRANCH" "2026-07-01T10:00:00.000Z" 5000
capture > /dev/null
parent_only="$(total_of)"
write_subagent "$SESSION_P" "$AGENT_1" "$BRANCH" "2026-07-02T10:00:00.000Z" 8000 "Plan author brief for the feature"
capture > "$TMP/out1.txt"
with_agent="$(total_of)"
sub_cost="$(field "d['cost_usd']['subagents']")"
check "1. the total rises once the subagent transcript exists" "gt '$with_agent' '$parent_only'"
check "1b. by exactly cost_usd.subagents" "near \"\$(python3 -c 'print($with_agent - $parent_only)')\" '$sub_cost'"
check "1c. subagents[] names the agent, selected by its parent" \
  "[ \"\$(field \"[(s['agent_id'], s['selected_by'], s['parent_session_id']) for s in d['subagents']]\")\" = \"[('$AGENT_1', 'parent', '$SESSION_P')]\" ]"
check "1d. the priced entry carries agent_id and is sidechain" \
  "[ \"\$(field \"[(p['agent_id'], p['is_sidechain']) for p in d['priced'] if p['agent_id']]\")\" = \"[('$AGENT_1', True)]\" ]"
check "1e. the result line counts it" "grep -q '1 subagents' '$TMP/out1.txt'"

# ── 2. outside the window, not selected ───────────────────────────────────────
write_subagent "$SESSION_P" "$AGENT_2" "$BRANCH" "2026-07-09T10:00:00.000Z" 8000 "Late follow-up"
capture > /dev/null
check "2. a subagent starting after the window's to is not priced" "near '$(total_of)' '$with_agent'"
check "2b. and is absent from subagents[]" \
  "[ \"\$(field \"[s['agent_id'] for s in d['subagents']]\")\" = \"['$AGENT_1']\" ]"

# ── 3. a coordinator on main: invisible until pinned ──────────────────────────
write_parent "$SESSION_M" "main" "2026-07-03T09:00:00.000Z" 5000
write_subagent "$SESSION_M" "$AGENT_3" "main" "2026-07-03T09:30:00.000Z" 8000 "Architect brief spawned from main"
capture > /dev/null
check "3. an unpinned subagent of a main-branch parent is not priced" "near '$(total_of)' '$with_agent'"
write_manifest "[\"$AGENT_3\"]"
capture > "$TMP/out3.txt"
pinned_total="$(total_of)"
check "3b. pinning its id prices it" "gt '$pinned_total' '$with_agent'"
check "3c. as selected_by pinned, under its real parent" \
  "[ \"\$(field \"[(s['agent_id'], s['selected_by']) for s in d['subagents'] if s['agent_id']=='$AGENT_3']\")\" = \"[('$AGENT_3', 'pinned')]\" ]"
check "3d. the main-branch parent itself stays out of sessions[]" \
  "[ \"\$(field \"[s['session_id'] for s in d['sessions']]\")\" = \"['$SESSION_P']\" ]"
check "3e. manifest_subagents records the pin" \
  "[ \"\$(field \"d['manifest_subagents']\")\" = \"['$AGENT_3']\" ]"

# ── 4. a pin that matches nothing ─────────────────────────────────────────────
write_manifest "[\"$AGENT_3\", \"deadbeefdeadbeef0\"]"
capture > "$TMP/out4.txt"
check "4. a pinned id no transcript carries is warned about by id" \
  "grep -q \"WARN: pinned subagent 'deadbeefdeadbeef0'\" '$TMP/out4.txt'"
check "4b. the pin that did match is not" \
  "! grep -q \"pinned subagent '$AGENT_3'\" '$TMP/out4.txt'"
write_manifest "[\"$AGENT_3\"]"
capture > /dev/null

# ── 5. the frozen-cost guard covers subagents ─────────────────────────────────
cp "$PLANNING" "$TMP/planning.before.json"
mv "$PROJECTS/$SESSION_P/subagents" "$TMP/stash-subagents"
capture > "$TMP/out5.txt"
rc5=$?
check "5. re-capture with the subagents directory gone is refused" "[ $rc5 -ne 0 ]"
check "5b. planning.json is left byte-identical" "cmp -s '$TMP/planning.before.json' '$PLANNING'"
check "5c. the refusal names the lost subagent as agent-<id>" "grep -q 'agent-$AGENT_1' '$TMP/out5.txt'"
capture --force > /dev/null
rc5f=$?
check "5d. --force overrides it" "[ $rc5f -eq 0 ] && ! near '$(total_of)' '$pinned_total'"
mv "$TMP/stash-subagents" "$PROJECTS/$SESSION_P/subagents"
capture > /dev/null
check "5e. restored, the figure comes back" "near '$(total_of)' '$pinned_total'"

# ── 6. --list-subagents is the discovery step ─────────────────────────────────
list_subs > "$TMP/out6.txt"
check "6. every reachable subagent is listed" \
  "grep -q '$AGENT_1' '$TMP/out6.txt' && grep -q '$AGENT_2' '$TMP/out6.txt' && grep -q '$AGENT_3' '$TMP/out6.txt'"
check "6b. with its opening prompt and parent" \
  "grep '$AGENT_3' '$TMP/out6.txt' | grep -q 'Architect brief spawned from main' && grep '$AGENT_3' '$TMP/out6.txt' | grep -q '${SESSION_M:0:8}'"
check "6c. with a non-zero cost" \
  "grep '$AGENT_1' '$TMP/out6.txt' | grep -Eq '\\\$ *[0-9]+\\.[0-9]*[1-9]'"
list_subs --since 2026-07-03 > "$TMP/out6b.txt"
check "6d. --since drops earlier ones and keeps later" \
  "! grep -q '$AGENT_1' '$TMP/out6b.txt' && grep -q '$AGENT_3' '$TMP/out6b.txt'"

# ── 7. a runner session's subagent is already in its usage.json ───────────────
write_parent "$SESSION_R" "$BRANCH" "2026-07-01T12:00:00.000Z" 5000
write_subagent "$SESSION_R" "$AGENT_4" "$BRANCH" "2026-07-01T12:30:00.000Z" 8000 "Executor-spawned helper"
mkdir -p "$AT/self/features/other-feature/auto/complete"
printf '{"plan":"01-x","session_id":"%s","total_cost_usd":1.0,"attempts":[]}\n' "$SESSION_R" \
  > "$AT/self/features/other-feature/auto/complete/01-x.usage.json"
write_manifest "[\"$AGENT_3\", \"$AGENT_4\"]"
capture > "$TMP/out7.txt"
check "7. a subagent of an excluded runner session is not priced even when pinned" \
  "near '$(total_of)' '$pinned_total'"
check "7b. and the pin is reported unmatched, not silently dropped" \
  "grep -q \"pinned subagent '$AGENT_4'\" '$TMP/out7.txt'"
check "7c. the runner session itself is excluded as before" \
  "[ \"\$(field \"d['excluded_session_ids']\")\" = \"['$SESSION_R']\" ]"
write_manifest "[\"$AGENT_3\"]"

# ── 8. two manifests pinning one id ───────────────────────────────────────────
mkdir -p "$AT/self/features/twin"
sed "s/\"slug\": \"$SLUG\"/\"slug\": \"twin\"/" "$FEATURE_DIR/README.md" > "$AT/self/features/twin/README.md"
capture > "$TMP/out8.txt"
check "8. a subagent pinned by two features is warned about, naming the other" \
  "grep -q \"subagent '$AGENT_3' is also pinned by feature 'twin'\" '$TMP/out8.txt'"
rm -r "$AT/self/features/twin"
capture > "$TMP/out8b.txt"
check "8b. and not once the twin is gone" "! grep -q 'also pinned' '$TMP/out8b.txt'"

echo
if [ "$fails" -eq 0 ]; then echo "subagent-capture: all ok"; else echo "subagent-capture: $fails FAIL"; exit 1; fi
