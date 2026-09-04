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
#   8. two manifests pinning the same id are warned about, naming the other feature;
#  18. --list-subagents --unclaimed --for <repo>/<slug> keeps exactly the delegates whose
#      brief names that feature — a `<slug>-two` one is not among them, one whose
#      `<repo>/<slug>` is longer than the pin column is, the agent id prints untruncated,
#      and --for without --unclaimed, or not shaped `<repo>/<slug>`, is a usage error;
#  17. session pins — the top-level twin of a subagent pin: a `sessions` id is claimed
#      outright from any project directory regardless of branch, window or cwd, with
#      `selected_by: "pinned"` (branch-selected entries say "branch"); a pin that is also
#      excluded warns and wins; and --list-sessions prints the top-level sessions under
#      this repo's directories, --unclaimed keeping only those no planning.json lists.
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
  local excludes="${2:-[]}"
  local agent_excludes="${3:-[]}"
  cat > "$FEATURE_DIR/README.md" <<MANIFEST
# $SLUG

Fixture feature for self/tests/subagent-capture.sh.

\`\`\`json
{
  "slug": "$SLUG",
  "branches": ["$BRANCH"],
  "session_window": {"from": "$WINDOW_FROM", "to": "$WINDOW_TO"},
  "exclude_sessions": $excludes,
  "exclude_subagents": $agent_excludes,
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

# ── 9. a pin survives a manual exclusion of its parent ────────────────────────
# Exclude the on-branch parent P and pin one of its two subagents (plus the main-branch
# architect). P's own context cost must go; the pinned children must stay.
write_manifest "[\"$AGENT_3\", \"$AGENT_1\"]" "[\"$SESSION_P\"]"
capture > "$TMP/out9.txt"
check "9. a manually excluded parent contributes no main-context cost" \
  "near '$(field "d['cost_usd']['main']")' 0"
check "9b. but its pinned subagent is still priced, as pinned" \
  "[ \"\$(field \"sorted((s['agent_id'], s['selected_by']) for s in d['subagents'])\")\" = \"[('$AGENT_1', 'pinned'), ('$AGENT_3', 'pinned')]\" ]"
check "9c. its unpinned sibling is not (exclusion closes the parent route)" \
  "! grep -q \"$AGENT_2\" '$PLANNING'"
check "9d. and no unmatched-pin warning is raised" "! grep -q 'pinned subagent' '$TMP/out9.txt'"
check "9e. the excluded parent is recorded as excluded, not as a session" \
  "[ \"\$(field \"'$SESSION_P' in d['excluded_session_ids'] and '$SESSION_P' not in [s['session_id'] for s in d['sessions']]\")\" = True ]"
write_manifest "[\"$AGENT_3\"]"

# ── 10. a pin whose parent lives under another repo's project directory ───────
# A coordinator in otherRepo spawned an architect to work on this repo; the transcript
# is filed under otherRepo's directory. This repo's manifest pins it by id.
OTHER_PROJECTS="$FAKE_HOME/.claude/projects/-Users-someone-dev-otherRepo"
OTHER_CWD="/Users/someone/dev/otherRepo"
SESSION_F="ffffffff-0000-0000-0000-000000000004"
AGENT_5="a5555555555555555"
mkdir -p "$OTHER_PROJECTS/$SESSION_F/subagents"
session_line "$SESSION_F" "$OTHER_CWD" "main" "msg-$SESSION_F" "$MODEL" "2026-07-04T09:00:00.000Z" 100 5000 0 0 0 \
  > "$OTHER_PROJECTS/$SESSION_F.jsonl"
{
  subagent_prompt_line "$SESSION_F" "$AGENT_5" "$OTHER_CWD" "main" "2026-07-04T09:30:00.000Z" "Architect for this repo, spawned from otherRepo"
  subagent_line "$SESSION_F" "$AGENT_5" "$OTHER_CWD" "main" "msg-$AGENT_5" "$MODEL" "2026-07-04T09:30:00.000Z" 100 8000 0 0 0
} > "$OTHER_PROJECTS/$SESSION_F/subagents/agent-$AGENT_5.jsonl"
capture > /dev/null
check "10. unpinned, a subagent filed under another repo is not priced" "! grep -q '$AGENT_5' '$PLANNING'"
write_manifest "[\"$AGENT_3\", \"$AGENT_5\"]"
capture > "$TMP/out10.txt"
check "10b. pinned, it is priced from wherever its transcript is filed" "gt '$(total_of)' '$pinned_total'"
check "10c. as pinned, cross_repo, under its own parent" \
  "[ \"\$(field \"[(s['selected_by'], s['cross_repo'], s['parent_session_id']) for s in d['subagents'] if s['agent_id']=='$AGENT_5']\")\" = \"[('pinned', True, '$SESSION_F')]\" ]"
check "10d. and no unmatched-pin warning is raised" "! grep -q 'pinned subagent' '$TMP/out10.txt'"
check "10e. a same-repo subagent is not cross_repo" \
  "[ \"\$(field \"[s['cross_repo'] for s in d['subagents'] if s['agent_id']=='$AGENT_3']\")\" = '[False]' ]"
list_subs > "$TMP/out10l.txt"
list_subs --everywhere > "$TMP/out10e.txt"
check "10f. --list-subagents omits it; --everywhere shows it with the parent's cwd" \
  "! grep -q '$AGENT_5' '$TMP/out10l.txt' && grep '$AGENT_5' '$TMP/out10e.txt' | grep -q 'otherRepo'"
write_manifest "[\"$AGENT_3\"]"

# ── 11. the claims ledger records every priced subagent ───────────────────────
LEDGER="$FAKE_HOME/.claude/subagent-claims.json"
REPO_NAME="$(basename "$AT")"   # the fixture copy has no .git, so identity falls back to the directory name
claim() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); c=d.get(sys.argv[2]); print(c and (c['repo_name'], c['slug'], c['selected_by']))" "$LEDGER" "$1"; }
capture > /dev/null   # manifest pins AGENT_3 only; AGENT_5 was pinned in phase 10
check "11. the ledger names the feature for a parent-selected subagent" \
  "[ \"$(claim $AGENT_1)\" = \"('$REPO_NAME', '$SLUG', 'parent')\" ]"
check "11b. and for a pinned one" "[ \"$(claim $AGENT_3)\" = \"('$REPO_NAME', '$SLUG', 'pinned')\" ]"
check "11c. an id no longer pinned drops out of the ledger" "[ \"$(claim $AGENT_5)\" = None ]"
check "11d. a never-priced subagent is not in it" "[ \"$(claim $AGENT_2)\" = None ]"

# ── 12. a subagent already claimed by another feature refuses the capture ─────
python3 - "$LEDGER" "$AGENT_3" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d[sys.argv[2]] = {"repo": "git@elsewhere:other.git", "repo_name": "otherRepo", "slug": "other-feature",
                  "selected_by": "pinned", "cost_usd": 1.0, "claimed_at": "2026-07-01T00:00:00+00:00"}
json.dump(d, open(sys.argv[1], "w"))
PY
rm -f "$PLANNING"
capture > "$TMP/out12.txt"; rc=$?
check "12. a cross-feature claim refuses the capture, naming the claimant" \
  "grep -q \"$AGENT_3  claimed by otherRepo/other-feature\" '$TMP/out12.txt'"
check "12b. nothing is written and the exit code says so" "[ ! -e '$PLANNING' ] && [ $rc -ne 0 ]"
python3 - "$LEDGER" "$AGENT_3" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); del d[sys.argv[2]]; json.dump(d, open(sys.argv[1], "w"))
PY
capture > /dev/null
check "12c. once the other claim is gone the capture goes through and re-claims" \
  "[ -e '$PLANNING' ] && [ \"$(claim $AGENT_3)\" = \"('$REPO_NAME', '$SLUG', 'pinned')\" ]"

# ── 13. --unclaimed and the brief header ──────────────────────────────────────
AGENT_6="a6666666666666666"
AGENT_7="a7777777777777777"
write_subagent "$SESSION_M" "$AGENT_6" "main" "2026-07-03T10:00:00.000Z" 8000 "feature: $REPO_NAME/$SLUG\\nArchitect brief with the header"
write_subagent "$SESSION_M" "$AGENT_7" "main" "2026-07-03T10:30:00.000Z" 8000 "feature: otherRepo/other-slug\\nArchitect brief for somewhere else"
list_subs --unclaimed > "$TMP/out13.txt"
check "13. --unclaimed lists the never-claimed and omits the claimed" \
  "grep -q '$AGENT_2' '$TMP/out13.txt' && grep -q '$AGENT_6' '$TMP/out13.txt' && ! grep -q '$AGENT_1' '$TMP/out13.txt' && ! grep -q '$AGENT_3' '$TMP/out13.txt'"
check "13b. with the feature each brief names as the proposed pin" \
  "grep '$AGENT_6' '$TMP/out13.txt' | grep -q '$REPO_NAME/$SLUG' && grep '$AGENT_7' '$TMP/out13.txt' | grep -q 'otherRepo/other-slug'"
check "13c. and a dash for a brief without the header" "grep '$AGENT_2' '$TMP/out13.txt' | grep -q ' -  '"
write_manifest "[\"$AGENT_3\", \"$AGENT_6\", \"$AGENT_7\"]"
capture > "$TMP/out13b.txt"
check "13d. a pin whose brief names another feature is warned about" \
  "grep -q \"pinned subagent '$AGENT_7' was briefed for feature 'otherRepo/other-slug'\" '$TMP/out13b.txt'"
check "13e. a pin whose brief names this feature is not" "! grep -q \"'$AGENT_6' was briefed\" '$TMP/out13b.txt'"
list_subs --unclaimed > "$TMP/out13c.txt"
check "13f. once pinned they leave --unclaimed" "! grep -q '$AGENT_6' '$TMP/out13c.txt' && ! grep -q '$AGENT_7' '$TMP/out13c.txt'"
write_manifest "[\"$AGENT_3\"]"

# ── 18. --for narrows --unclaimed to exactly one feature ──────────────────────
# Numbered last, placed here because it reuses phase 13's fixtures — phase 17 clears
# $PROJECTS. This list is what feature-close.sh's stray-delegate guard reads, and a
# substring test over the printed table got it wrong both ways: a delegate briefed for
# `<slug>-two` matched (and the human was sent to pin it into the wrong manifest), while a
# `<repo>/<slug>` longer than the 26-character pin column matched nothing — a silent miss,
# and an unpinned delegate is never priced. --for compares the (repo, slug) pair the brief
# carries.
AGENT_A="aaaaaaaaaaaaaaaa1"
AGENT_B="aaaaaaaaaaaaaaaa2"
AGENT_L="aaaaaaaaaaaaaaaa3"
LONG_SLUG="alpha-longer-than-the-pin-column-by-a-wide-margin"
write_subagent "$SESSION_M" "$AGENT_A" "main" "2026-07-03T12:00:00.000Z" 8000 "feature: $REPO_NAME/alpha\\nBuild alpha"
write_subagent "$SESSION_M" "$AGENT_B" "main" "2026-07-03T12:30:00.000Z" 8000 "feature: $REPO_NAME/alpha-two\\nBuild alpha-two"
write_subagent "$SESSION_M" "$AGENT_L" "main" "2026-07-03T13:00:00.000Z" 8000 "feature: $REPO_NAME/$LONG_SLUG\\nBuild the long-named one"
list_subs --unclaimed --for "$REPO_NAME/alpha" > "$TMP/out18.txt"
check "18. --for <repo>/alpha lists exactly that delegate, not the alpha-two one" \
  "grep -q '$AGENT_A' '$TMP/out18.txt' && ! grep -q '$AGENT_B' '$TMP/out18.txt' && ! grep -q '$AGENT_6' '$TMP/out18.txt'"
list_subs --unclaimed --for "$REPO_NAME/alpha-two" > "$TMP/out18b.txt"
check "18b. --for <repo>/alpha-two lists exactly that one, not alpha" \
  "grep -q '$AGENT_B' '$TMP/out18b.txt' && ! grep -q '$AGENT_A' '$TMP/out18b.txt'"
list_subs --unclaimed --for "$REPO_NAME/$LONG_SLUG" > "$TMP/out18c.txt"
check "18c. a <repo>/<slug> past the 26-character pin column is still matched" \
  "[ ${#REPO_NAME} -gt 0 ] && [ $(( ${#REPO_NAME} + 1 + ${#LONG_SLUG} )) -gt 26 ] && grep -q '$AGENT_L' '$TMP/out18c.txt' && ! grep -q '$AGENT_A' '$TMP/out18c.txt'"
check "18d. its agent id is printed untruncated — the close reads that column" \
  "[ \"\$(awk '/^2026-/ {print \$2}' '$TMP/out18c.txt')\" = '$AGENT_L' ]"
list_subs --unclaimed --for "$REPO_NAME/no-such-feature" > "$TMP/out18e.txt"
check "18e. a feature no brief names lists no row at all" \
  "! grep -q '^2026-' '$TMP/out18e.txt' && grep -q 'no unclaimed subagent transcripts briefed for $REPO_NAME/no-such-feature' '$TMP/out18e.txt'"
list_subs --for "$REPO_NAME/alpha" > "$TMP/out18f.txt"; rc18=$?
check "18f. --for without --unclaimed is a usage error naming what it needs" \
  "[ $rc18 -ne 0 ] && grep -q 'takes --list-subagents --unclaimed' '$TMP/out18f.txt'"
list_subs --unclaimed --for "not-a-feature-ref" > "$TMP/out18g.txt"; rc18g=$?
check "18g. --for that is not <repo>/<slug> is a usage error naming the shape" \
  "[ $rc18g -ne 0 ] && grep -q 'takes <repo>/<slug>' '$TMP/out18g.txt'"

# ── 14. one transcript filed under two parents is priced once ─────────────────
# A resumed session re-files its subagents under the new session id.
capture > /dev/null
before="$(total_of)"
mkdir -p "$PROJECTS/$SESSION_P/subagents"
cp "$PROJECTS/$SESSION_M/subagents/agent-$AGENT_3.jsonl" "$PROJECTS/$SESSION_P/subagents/agent-$AGENT_3.jsonl"
capture > /dev/null
check "14. a pinned id filed under two parents is priced once" "near '$(total_of)' '$before'"
check "14b. and listed once in subagents[]" \
  "[ \"\$(field \"[s['agent_id'] for s in d['subagents']].count('$AGENT_3')\")\" = 1 ]"
list_subs > "$TMP/out14.txt"
check "14c. --list-subagents shows it once" "[ \"$(grep -c "$AGENT_3" "$TMP/out14.txt")\" = 1 ]"
rm "$PROJECTS/$SESSION_P/subagents/agent-$AGENT_3.jsonl"

# ── 15. --carry-lost adds a pin to a feature whose sessions have expired ──────
SESSION_X="xxxxxxxx-0000-0000-0000-000000000005"
AGENT_8="a8888888888888888"
write_parent "$SESSION_X" "$BRANCH" "2026-07-02T12:00:00.000Z" 5000
capture > /dev/null
frozen="$(total_of)"
# Make the prior file look like one written before subagent capture existed: no
# agent_id on priced rows, no subagents[] at all — the shape of every real frozen file.
python3 - "$PLANNING" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["priced"] = [{k: v for k, v in p.items() if k != "agent_id"} for p in d["priced"] if not p.get("agent_id")]
d.pop("subagents", None)
json.dump(d, open(sys.argv[1], "w"))
PY
rm "$PROJECTS/$SESSION_X.jsonl"
capture > "$TMP/out15.txt"; rc15=$?
check "15. a priced session whose transcript is gone still refuses a plain recapture" \
  "[ $rc15 -ne 0 ] && grep -q 'REFUSING' '$TMP/out15.txt' && grep -q 'carry-lost' '$TMP/out15.txt'"
write_subagent "$SESSION_M" "$AGENT_8" "main" "2026-07-03T11:00:00.000Z" 8000 "Late pin on a frozen feature"
write_manifest "[\"$AGENT_3\", \"$AGENT_8\"]"
capture --carry-lost > "$TMP/out15b.txt"; rc15b=$?
a8="$(field "sum(p['cost_usd'] for p in d['priced'] if p['agent_id']=='$AGENT_8')")"
check "15b. --carry-lost writes: frozen figure plus the new pin, exactly" \
  "[ $rc15b -eq 0 ] && near '$(total_of)' \"\$(python3 -c 'print($frozen + $a8)')\""
check "15c. the lost session is carried, marked with the capture it came from" \
  "[ \"\$(field \"[s['session_id'] for s in d['sessions'] if s.get('carried_from')]\")\" = \"['$SESSION_X']\" ] && [ \"\$(field \"d['carried_from'] is not None\")\" = True ]"
check "15d. the new pin is priced and claimed beside it" \
  "[ \"$(claim $AGENT_8)\" = \"('$REPO_NAME', '$SLUG', 'pinned')\" ]"
check "15e. and the run says what it carried" "grep -q 'carried forward' '$TMP/out15b.txt'"
write_manifest "[\"$AGENT_3\"]"

# ── 16. exclude_subagents: a selected parent disowns a child another feature pins ─
# AGENT_1 is parent-selected under SESSION_P (phase 1). The coordinator case: the
# coordinator's manifest owns the session, the arm's manifest pins the architect.
write_manifest "[\"$AGENT_3\"]" "[]" "[\"$AGENT_1\"]"
capture --carry-lost > "$TMP/out16.txt"
check "16. an excluded subagent is not claimed by the parent route" \
  "[ \"\$(field \"'$AGENT_1' in [s['agent_id'] for s in d['subagents']]\")\" = False ]"
check "16b. and is recorded as excluded" \
  "[ \"\$(field \"d['excluded_agent_ids']\")\" = \"['$AGENT_1']\" ]"
check "16c. the parent's own cost is still counted" "gt '$(field "d['cost_usd']['main']")' 0"
check "16d. and the id leaves the ledger, free for the other feature to pin" "[ \"$(claim $AGENT_1)\" = None ]"
write_manifest "[\"$AGENT_3\", \"$AGENT_1\"]" "[]" "[\"$AGENT_1\"]"
capture --carry-lost > "$TMP/out16b.txt"
check "16e. pinned and excluded at once warns, and the pin wins" \
  "grep -q \"both pinned and in exclude_subagents\" '$TMP/out16b.txt' && [ \"\$(field \"'$AGENT_1' in [s['agent_id'] for s in d['subagents']]\")\" = True ]"
write_manifest "[\"$AGENT_3\"]"

# ── 17. session pins ──────────────────────────────────────────────────────────
# A session that began on main before the feature existed — the planning session that
# then ran feature-start.sh — is claimed by id, never by putting main in `branches`.
SESSION_X="xxxxxxxx-0000-0000-0000-000000000009"   # launched elsewhere, on main, out of window
SESSION_Q="qqqqqqqq-0000-0000-0000-000000000010"   # in this repo, on main, claimed by nobody
ELSEWHERE_PROJECTS="$FAKE_HOME/.claude/projects/-elsewhere-repo"
mkdir -p "$ELSEWHERE_PROJECTS"
write_manifest_sessions() {           # write_manifest_sessions <sessions json> [<excludes json>]
  cat > "$FEATURE_DIR/README.md" <<MANIFEST
# $SLUG

\`\`\`json
{
  "slug": "$SLUG",
  "branches": ["$BRANCH"],
  "session_window": {"from": "$WINDOW_FROM", "to": "$WINDOW_TO"},
  "exclude_sessions": ${2:-[]},
  "sessions": $1,
  "subagents": []
}
\`\`\`
MANIFEST
}
rm -rf "$PROJECTS"/* "$PLANNING"
write_parent "$SESSION_P" "$BRANCH" "2026-07-01T10:00:00.000Z" 5000
session_line "$SESSION_X" "/elsewhere/repo" "main" "msg-$SESSION_X" "$MODEL" \
  "2026-01-01T00:00:00.000Z" 100 4000 0 0 0 > "$ELSEWHERE_PROJECTS/$SESSION_X.jsonl"
write_manifest_sessions "[]"
capture > /dev/null
check "17a. without a pin the elsewhere session is invisible" \
  "[ \"\$(field \"[s['session_id'] for s in d['sessions']]\")\" = \"['$SESSION_P']\" ]"
check "17b. a branch-selected entry says selected_by branch" \
  "[ \"\$(field \"[s['selected_by'] for s in d['sessions']]\")\" = \"['branch']\" ]"
write_manifest_sessions "[\"$SESSION_X\"]"
capture > "$TMP/out17.txt"
check "17c. a pinned session is claimed from another project directory, out of window, on main" \
  "[ \"\$(field \"sorted((s['session_id'], s['selected_by']) for s in d['sessions'])\")\" = \"[('$SESSION_P', 'branch'), ('$SESSION_X', 'pinned')]\" ]"
check "17d. its entry records the cwd it was launched in" \
  "[ \"\$(field \"[s['cwd'] for s in d['sessions'] if s['session_id']=='$SESSION_X']\")\" = \"['/elsewhere/repo']\" ]"
check "17e. and its cost is in the total" "gt '$(total_of)' 0"
write_manifest_sessions "[\"$SESSION_P\"]"
capture > /dev/null
check "17f. a pin that branch and window also select is priced once" \
  "[ \"\$(field \"[s['session_id'] for s in d['sessions']].count('$SESSION_P')\")\" = 1 ] && [ \"\$(field \"len([p for p in d['priced'] if p['session_id']=='$SESSION_P'])\")\" = 1 ]"
write_manifest_sessions "[\"$SESSION_X\"]" "[\"$SESSION_X\"]"
capture > "$TMP/out17g.txt"
check "17g. pinned and excluded at once warns, and the pin wins" \
  "grep -q 'both pinned and in exclude_sessions' '$TMP/out17g.txt' && [ \"\$(field \"'$SESSION_X' in [s['session_id'] for s in d['sessions']]\")\" = True ]"
# --list-sessions: the discovery step for a pin, and the close step's "who is unclaimed".
write_parent "$SESSION_Q" "main" "2026-07-02T10:00:00.000Z" 1500
printf '{"type":"user","sessionId":"%s","cwd":"%s","gitBranch":"main","timestamp":"2026-07-02T10:00:00.000Z","message":{"role":"user","content":"triage the flaky tests"}}\n' \
  "$SESSION_Q" "$AT" >> "$PROJECTS/$SESSION_Q.jsonl"
list_sess() { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self --list-sessions "$@" 2>&1; }
list_sess > "$TMP/out17h.txt"
check "17h. --list-sessions prints the top-level sessions under this repo, with branch, cwd and prompt" \
  "grep -q '$SESSION_P' '$TMP/out17h.txt' && grep -q '$SESSION_Q' '$TMP/out17h.txt' && grep -q 'triage the flaky tests' '$TMP/out17h.txt' && ! grep -q '$SESSION_X' '$TMP/out17h.txt'"
list_sess --unclaimed > "$TMP/out17i.txt"
check "17i. --unclaimed keeps the one no planning.json lists" \
  "grep -q '$SESSION_Q' '$TMP/out17i.txt' && ! grep -q '$SESSION_P' '$TMP/out17i.txt'"
list_sess --since 2026-07-02 > "$TMP/out17j.txt"
check "17j. --since drops the earlier one" \
  "grep -q '$SESSION_Q' '$TMP/out17j.txt' && ! grep -q '$SESSION_P' '$TMP/out17j.txt'"
write_manifest "[\"$AGENT_3\"]"

echo
if [ "$fails" -eq 0 ]; then echo "subagent-capture: all ok"; else echo "subagent-capture: $fails FAIL"; exit 1; fi
