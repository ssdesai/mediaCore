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
#      this repo's directories, --unclaimed keeping only those no planning.json lists;
#  19. a pin is a claim whether or not it cost anything: a pinned transcript with no
#      `assistant` line in it is captured into `subagents[]` all the same, earns no
#      priced row, and is written to the ledger under this feature with `cost_usd` 0, so
#      --list-subagents --unclaimed stops listing it — with the listing BEFORE the pin as
#      the guard, since a delegate the list never held would satisfy the last check on
#      its own.
#   Y. a parent-selected delegate another feature PINS yields (self/features/unpin-and-yield):
#      Y1 pinned by a sibling manifest under `.worktrees/<other>/` — recorded in
#      `yielded_agent_ids` as `{agent_id, to}`, out of `subagents[]` and the total, one
#      output line naming the pinner, and the recapture that newly yields it is not refused
#      as "lost"; Y2 the same with the pin only in the ledger (another repo, `pinned`);
#      Y3 a ledger claim by another feature with `selected_by: "parent"` does not yield;
#      Y4 this feature's own pin still wins; Y5 `exclude_subagents` still excludes and
#      lands in `excluded_agent_ids`; Y6 the pinning feature's capture then succeeds;
#      Y7 the pin-over-parent refusal names the other feature and its recapture, and that
#      recapture yields.
#   C. a runner child that collided with its parent's session id (self/features/
#      cost-capture-collisions, design §4): the coordinator a usage.json names is still
#      captured at its interactive lines alone, warned about with the sidecar named, its
#      pinned implementer captured; the runner tree's own delegate is not priced, one whose
#      spawning tree cannot be told is priced as the coordinator's with a warning; a runner
#      session with a file of its own is excluded as before and its pinned delegate never
#      priced; and a pinned delegate whose parent the main walk never reached is found in
#      this repo's own directories. RED on main, which excluded the whole session.
#      C12-C14 (round 2): a pinned collided coordinator filed under a second project
#      directory — reached only by the pinned-session fallback — has its pinned
#      implementer priced under it, while a pinned delegate its runner tree spawned is not
#      priced and its pin is warned ignored. RED on round 1's code.
#
# All RED until the subagent walk landed in analysis/capture_planning.py; 19c-19e were RED
# until the ledger was written from `subagents[]` rather than from the priced rows.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Physical path — roots.py resolves through Path.resolve(); see capture-guard.sh.
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
for f in pricing.py litellm_prices.py rates_history.json roots.py transcript.py capture_planning.py routing.py; do
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
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/.' '--')"
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
# The self corpus's identity is declared (roots.SELF_CORPUS_IDENTITY) and its
# repo_display_name is `agentTooling`, which is what this fixture's copy is called.
REPO_NAME="$(basename "$AT")"
# The ledger has two sections — `subagents` (one claimant per id) and `sessions` (a list,
# since a coordinator spans features); this reads the first by name rather than tolerating
# the legacy flat shape, so a regression to it fails here. claims-ledger.sh owns the
# assertion that such a file still LOADS.
claim() { python3 -c "import json,sys; d=json.load(open(sys.argv[1]))['subagents']; c=d.get(sys.argv[2]); print(c and (c['repo_name'], c['slug'], c['selected_by']))" "$LEDGER" "$1"; }
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
d["subagents"][sys.argv[2]] = {"repo": "git@elsewhere:other.git", "repo_name": "otherRepo", "slug": "other-feature",
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
d = json.load(open(sys.argv[1])); del d["subagents"][sys.argv[2]]; json.dump(d, open(sys.argv[1], "w"))
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
# $PROJECTS. This list is what feature-capture.sh's unclaimed-delegate warning reads, and a
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

# ── 19. a pin is a claim whether or not it cost anything ──────────────────────
# Design §3. The ledger used to be written from the priced rows, so a pinned delegate
# whose transcript holds no `assistant` line — a brief, and then a kill, or a run that
# billed nothing — reached no `priced[]` row, entered the ledger under no feature, and
# `--list-subagents --unclaimed` went on listing it forever, telling the human to write a
# pin that was already written. The ledger records claims: every entry of the capture's
# own `subagents[]`, with `cost_usd` 0 when nothing was billable.
#
# The transcript is the prompt line alone — no `assistant` line at all, which is the
# first half of the rule and is asserted rather than assumed (19a): the capture must still
# list it in `subagents[]`, since `agent_start_of` reads timestamps and not usage.
AGENT_ZERO="a0000000000000000"
rm -rf "$PROJECTS"/* "$PLANNING"
write_parent "$SESSION_P" "$BRANCH" "2026-07-01T10:00:00.000Z" 5000
mkdir -p "$PROJECTS/$SESSION_M/subagents"
subagent_prompt_line "$SESSION_M" "$AGENT_ZERO" "$AT" "main" "2026-07-03T09:00:00.000Z" \
  "feature: $REPO_NAME/$SLUG\\nDelegate that billed nothing" \
  > "$PROJECTS/$SESSION_M/subagents/agent-$AGENT_ZERO.jsonl"
write_parent "$SESSION_M" "main" "2026-07-03T09:00:00.000Z" 5000

# The guard, and it has to come first: before the pin, this delegate IS unclaimed and is
# listed. Without it the assertion below could pass because the listing never had a row
# for an unbilled transcript in the first place.
list_subs --unclaimed > "$TMP/out19-before.txt"
check "19. an unpinned, unbilled delegate is listed as unclaimed (the guard)" \
  "grep -q '$AGENT_ZERO' '$TMP/out19-before.txt'"

write_manifest "[\"$AGENT_ZERO\"]"
capture > "$TMP/out19.txt"
check "19a. a pinned transcript with no assistant line is still captured into subagents[]" \
  "[ \"\$(field \"[(s['agent_id'], s['selected_by']) for s in d['subagents']]\")\" = \"[('$AGENT_ZERO', 'pinned')]\" ]"
check "19b. it earns no priced row, having nothing billable in it" \
  "[ \"\$(field \"[p['agent_id'] for p in d['priced'] if p['agent_id']]\")\" = '[]' ]"
check "19c. the ledger names this feature for it all the same" \
  "[ \"$(claim $AGENT_ZERO)\" = \"('$REPO_NAME', '$SLUG', 'pinned')\" ]"
zero_cost="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['subagents'][sys.argv[2]]['cost_usd'])" "$LEDGER" "$AGENT_ZERO")"
check "19d. with cost_usd 0 — a claim, not a price (got ${zero_cost:-<absent>})" "[ \"$zero_cost\" = 0.0 ]"
list_subs --unclaimed > "$TMP/out19-after.txt"
check "19e. and --unclaimed no longer lists it, by the same ledger lookup as any other" \
  "! grep -q '$AGENT_ZERO' '$TMP/out19-after.txt'"
check "19f. and the capture's own result line counts it among the subagents" \
  "grep -q '1 subagents' '$TMP/out19.txt'"

# ── Y. a parent-selected delegate another feature PINS yields ─────────────────
# self/features/unpin-and-yield, spec §2. A session a feature selects used to claim every
# delegate it spawned in the window, even one another feature pins, and the ledger then
# refused the pinning feature's capture as a double claim; `exclude_subagents`, written by
# hand in the selecting feature, was the only way out. Now the parent arm checks first:
# pinned by another feature's manifest (this corpus, in the primary or any
# `.worktrees/*/` checkout) or by a `"pinned"` ledger claim of another (repo, slug), the
# delegate is skipped and recorded in `yielded_agent_ids`. This feature's own pin and
# `exclude_subagents` come first and are unchanged. RED until the yield arm landed.
AGENT_Y1="b1111111111111111"   # pinned by a sibling manifest in .worktrees/sib
AGENT_Y2="b2222222222222222"   # pinned only in the ledger, by a feature of another repo
AGENT_YP="b3333333333333333"   # claimed in the ledger by another feature as "parent"
AGENT_Y4="b4444444444444444"   # pinned by this feature AND by the sibling
AGENT_Y5="b5555555555555555"   # excluded by this feature, pinned by the sibling
AGENT_Y7="b7777777777777777"   # parent-claimed here first, pinned by `pinner` after
SIB_README="$AT/.worktrees/sib/self/features/sib/README.md"
PINNER_DIR="$AT/self/features/pinner"
FAR_REPO="git@elsewhere:far.git"
rm -rf "$PROJECTS"/* "$PLANNING" "$LEDGER"
write_parent "$SESSION_P" "$BRANCH" "2026-07-01T10:00:00.000Z" 5000
for a in "$AGENT_Y1" "$AGENT_Y2" "$AGENT_Y4" "$AGENT_Y5"; do
  write_subagent "$SESSION_P" "$a" "$BRANCH" "2026-07-02T10:00:00.000Z" 8000 "Delegate $a"
done
write_manifest "[\"$AGENT_Y4\"]" "[]" "[\"$AGENT_Y5\"]"

# other_manifest PATH SLUG BRANCH PINS_JSON — another feature's fence.
other_manifest() {
  mkdir -p "$(dirname "$1")"
  printf '# %s\n\n```json\n{"slug": "%s", "branches": ["%s"], "session_window": {"from": "%s", "to": "%s"}, "exclude_sessions": [], "exclude_subagents": [], "sessions": [], "subagents": %s}\n```\n' \
    "$2" "$2" "$3" "$WINDOW_FROM" "$WINDOW_TO" "$4" > "$1"
}
# ledger_set AGENT REPO REPO_NAME SLUG SELECTED_BY — one subagents-section claim, written
# the way another capture would have (`record_claims`); `-` deletes the entry.
ledger_set() {
  python3 - "$LEDGER" "$@" <<'PY'
import json, os, sys
path, agent, repo, repo_name, slug, selected_by = sys.argv[1:7]
d = json.load(open(path)) if os.path.exists(path) else {"subagents": {}, "sessions": {}}
if repo == "-":
    d["subagents"].pop(agent, None)
else:
    d["subagents"][agent] = {"repo": repo, "repo_name": repo_name, "slug": slug,
                             "selected_by": selected_by, "cost_usd": 1.0,
                             "claimed_at": "2026-07-01T00:00:00+00:00"}
json.dump(d, open(path, "w"))
PY
}
capture_pinner() { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self pinner --recapture 2>&1; }
pinner_field() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$PINNER_DIR/planning.json" "$1"; }

# Y0 — the baseline, before anyone else pins anything: the parent route claims Y1 and Y2.
capture > "$TMP/outY0.txt"
base_total="$(total_of)"
y12_cost="$(field "sum(p['cost_usd'] for p in d['priced'] if p['agent_id'] in ('$AGENT_Y1', '$AGENT_Y2'))")"
check "Y0. baseline: the parent route claims Y1 and Y2, the own pin Y4, and Y5 stays excluded" \
  "[ \"\$(field \"[(s['agent_id'], s['selected_by']) for s in d['subagents']]\")\" = \"[('$AGENT_Y1', 'parent'), ('$AGENT_Y2', 'parent'), ('$AGENT_Y4', 'pinned')]\" ]"
check "Y0b. yielded_agent_ids is present, and empty, when nothing yields" \
  "[ \"\$(field \"d['yielded_agent_ids']\")\" = '[]' ]"

# Y1/Y2 — a sibling worktree's manifest pins Y1 (and Y4, Y5); another repo's ledger pin
# holds Y2. The recapture yields both, and the frozen guard does not call them lost.
other_manifest "$SIB_README" sib sib-branch "[\"$AGENT_Y1\", \"$AGENT_Y4\", \"$AGENT_Y5\"]"
ledger_set "$AGENT_Y2" "$FAR_REPO" farRepo far-feature pinned
capture > "$TMP/outY1.txt"; rcY1=$?
check "Y1. the recapture that newly yields two priced delegates is not refused as losing them (rc $rcY1)" \
  "[ $rcY1 -eq 0 ] && ! grep -q 'REFUSING' '$TMP/outY1.txt'"
check "Y1b. yielded_agent_ids names each, sorted, with the feature that pins it (manifest, then ledger)" \
  "[ \"\$(field \"[(y['agent_id'], y['to']) for y in d['yielded_agent_ids']]\")\" = \"[('$AGENT_Y1', '$REPO_NAME/sib'), ('$AGENT_Y2', 'farRepo/far-feature')]\" ]"
check "Y1c. neither is in subagents[] any more" \
  "[ \"\$(field \"[s['agent_id'] for s in d['subagents']]\")\" = \"['$AGENT_Y4']\" ]"
check "Y1d. the feature's cost drops by exactly what the two cost" \
  "near \"\$(python3 -c 'print($base_total - $y12_cost)')\" '$(total_of)'"
check "Y1e. one output line per yielded id names the pinning feature" \
  "grep '$AGENT_Y1' '$TMP/outY1.txt' | grep -q 'yield.*$REPO_NAME/sib' && grep '$AGENT_Y2' '$TMP/outY1.txt' | grep -q 'yield.*farRepo/far-feature'"
check "Y1f. and the ledger no longer holds Y1 for this feature — it is free for the pinner" \
  "[ \"$(claim "$AGENT_Y1")\" = None ]"
check "Y2. the other repo's ledger pin is left exactly as it was" \
  "[ \"$(claim "$AGENT_Y2")\" = \"('farRepo', 'far-feature', 'pinned')\" ]"
check "Y4. this feature's own pin still wins: Y4 is 'pinned', not yielded, though the sibling pins it too" \
  "[ \"\$(field \"[(s['agent_id'], s['selected_by']) for s in d['subagents'] if s['agent_id']=='$AGENT_Y4'] + [y for y in d['yielded_agent_ids'] if y['agent_id']=='$AGENT_Y4']\")\" = \"[('$AGENT_Y4', 'pinned')]\" ]"
check "Y5. exclude_subagents still excludes, recorded in excluded_agent_ids and not yielded" \
  "[ \"\$(field \"d['excluded_agent_ids']\")\" = \"['$AGENT_Y5']\" ] && [ \"\$(field \"'$AGENT_Y5' in [y['agent_id'] for y in d['yielded_agent_ids']]\")\" = False ]"

# Y3 — only a pin outranks: another feature's PARENT claim in the ledger does not yield,
# and the ordinary double-claim refusal stands.
write_subagent "$SESSION_P" "$AGENT_YP" "$BRANCH" "2026-07-02T11:00:00.000Z" 8000 "Delegate claimed elsewhere"
ledger_set "$AGENT_YP" "$FAR_REPO" farRepo par-feature parent
cp "$PLANNING" "$TMP/planningY3.before"
capture > "$TMP/outY3.txt"; rcY3=$?
check "Y3. a ledger claim with selected_by parent does not yield — the double claim is refused (rc $rcY3)" \
  "[ $rcY3 -ne 0 ] && grep -q '$AGENT_YP  claimed by farRepo/par-feature' '$TMP/outY3.txt' && cmp -s '$TMP/planningY3.before' '$PLANNING'"
check "Y3b. and nothing says it yielded" "! grep '$AGENT_YP' '$TMP/outY3.txt' | grep -q 'yield'"
ledger_set "$AGENT_YP" - - - -
rm -f "$PROJECTS/$SESSION_P/subagents/agent-$AGENT_YP.jsonl"

# Y6 — the pinning feature's own capture now succeeds: `pinner`, in this corpus, pins Y1.
other_manifest "$SIB_README" sib sib-branch "[\"$AGENT_Y4\", \"$AGENT_Y5\"]"
other_manifest "$PINNER_DIR/README.md" pinner pinner-branch "[\"$AGENT_Y1\"]"
capture > "$TMP/outY6a.txt"
check "Y6. a pin in this corpus's own primary checkout yields too" \
  "[ \"\$(field \"[(y['agent_id'], y['to']) for y in d['yielded_agent_ids']]\")\" = \"[('$AGENT_Y1', '$REPO_NAME/pinner'), ('$AGENT_Y2', 'farRepo/far-feature')]\" ]"
capture_pinner > "$TMP/outY6.txt"; rcY6=$?
check "Y6b. the pinning feature's capture then succeeds, with no double-claim refusal (rc $rcY6)" \
  "[ $rcY6 -eq 0 ] && ! grep -q 'already claimed' '$TMP/outY6.txt'"
check "Y6c. claiming the delegate as pinned, in its record and in the ledger" \
  "[ \"\$(pinner_field \"[(s['agent_id'], s['selected_by']) for s in d['subagents']]\")\" = \"[('$AGENT_Y1', 'pinned')]\" ] && [ \"$(claim "$AGENT_Y1")\" = \"('$REPO_NAME', 'pinner', 'pinned')\" ]"

# Y7 — the ordering hole: this feature claims Y7 by parent FIRST, and only then does
# `pinner` pin it. Its capture is refused (no record rewritten behind its owner's back),
# but the refusal names the feature holding the parent claim and the recapture that will
# now yield it — and that recapture does.
write_subagent "$SESSION_P" "$AGENT_Y7" "$BRANCH" "2026-07-02T12:00:00.000Z" 8000 "Delegate pinned late"
capture > /dev/null
check "Y7 (setup). this feature claims Y7 by parent while nobody pins it" \
  "[ \"$(claim "$AGENT_Y7")\" = \"('$REPO_NAME', '$SLUG', 'parent')\" ]"
other_manifest "$PINNER_DIR/README.md" pinner pinner-branch "[\"$AGENT_Y1\", \"$AGENT_Y7\"]"
capture_pinner > "$TMP/outY7.txt"; rcY7=$?
check "Y7. the pin over a parent claim is still refused (rc $rcY7)" \
  "[ $rcY7 -ne 0 ] && grep -q '$AGENT_Y7  claimed by $REPO_NAME/$SLUG' '$TMP/outY7.txt'"
check "Y7b. the refusal names the other feature's recapture, which will now yield the delegate" \
  "grep -q 'feature-capture.sh --self $SLUG --recapture' '$TMP/outY7.txt' && grep -q 'feature-capture.sh --self $SLUG' '$TMP/outY7.txt' && grep -qi 'yield' '$TMP/outY7.txt'"
capture > "$TMP/outY7c.txt"
check "Y7c. and it does: the parent feature's recapture yields Y7 to pinner" \
  "[ \"\$(field \"[y['to'] for y in d['yielded_agent_ids'] if y['agent_id']=='$AGENT_Y7']\")\" = \"['$REPO_NAME/pinner']\" ]"
capture_pinner > "$TMP/outY7d.txt"; rcY7d=$?
check "Y7d. after which the pinning feature's capture goes through (rc $rcY7d)" \
  "[ $rcY7d -eq 0 ] && [ \"$(claim "$AGENT_Y7")\" = \"('$REPO_NAME', 'pinner', 'pinned')\" ]"

# ── C. a runner child that collided with its parent's session id (design §4) ──────────
# self/features/cost-capture-collisions. Reproduced in a cloud container: a `claude -p`
# launched with the parent's environment reports the parent's CLAUDE_CODE_SESSION_ID and
# APPENDS its lines to the parent's own transcript as a second conversation tree — rooted
# at a `user` line with `parentUuid: null` whose prompt is the runner's — so the parent's
# id lands in the plan's usage.json. The capture then excluded the coordinator outright as
# a runner session, and its pinned implementer with it: cloud-close recorded $1.92 of
# roughly $9.30. The rule now: an id a usage.json names is runner-only when nothing in its
# transcript lies outside a headless tree; one that also holds interactive lines is a
# COLLISION — warned about, its interactive lines priced as any session's, its headless
# tree (whose cost the sidecar holds) dropped, and a delegate spawned FROM that tree left
# to the sidecar too. RED on main: the whole session is excluded, nothing here is priced.
#
# The coordinator's file below, in order: its own root and a response that spawns the
# implementer (5000 output tokens); the runner's root — the review runner's real opening,
# marker sentence and all — and a response that spawns a delegate of its own (7000); a
# compaction boundary that continues the COORDINATOR's tree through `logicalParentUuid`
# though its own `parentUuid` is null; and one more coordinator response (3000). So the
# coordinator's own cost is 8000 output tokens and the runner's 7000.
SESSION_C="cccccccc-0000-0000-0000-00000000000c"   # coordinator, collided with a runner child
SESSION_R2="dddddddd-0000-0000-0000-00000000000d"  # a runner session with a file of its own
SESSION_W="eeeeeeee-0000-0000-0000-00000000000e"   # parent in another feature's worktree
AGENT_CI="c1c1c1c1c1c1c1c1c"   # the coordinator's implementer, pinned
AGENT_CR="c2c2c2c2c2c2c2c2c"   # spawned by the runner's tree — runner cost
AGENT_CU="c3c3c3c3c3c3c3c3c"   # no meta.json: which tree spawned it cannot be told
AGENT_CW="c4c4c4c4c4c4c4c4c"   # pinned, under a parent the main walk never reaches
AGENT_R2="c5c5c5c5c5c5c5c5c"   # pinned, under a genuine runner session
RUNNER_OPENING="You are running a REVIEW plan: a post-verify pass that reads the DIFF a batch produced and judges the code itself. A progress log is maintained automatically by the harness so this work can be resumed if interrupted."
# tree_user SESSION UUID TIMESTAMP PROMPT_SOURCE TEXT — a conversation's root `user` line.
tree_user() {
  printf '{"type":"user","sessionId":"%s","cwd":"%s","gitBranch":"%s","uuid":"%s","parentUuid":null,"timestamp":"%s","promptSource":"%s","message":{"role":"user","content":"%s"}}\n' \
    "$1" "$AT" "$BRANCH" "$2" "$3" "$4" "$5"
}
# tree_assistant SESSION UUID PARENT TIMESTAMP MESSAGE_ID OUTPUT TOOL_USE_ID — one billed
# response, carrying an Agent tool_use block with TOOL_USE_ID (the id a delegate's
# meta.json names as the call that spawned it).
tree_assistant() {
  printf '{"type":"assistant","sessionId":"%s","cwd":"%s","gitBranch":"%s","uuid":"%s","parentUuid":"%s","timestamp":"%s","isSidechain":false,"message":{"id":"%s","model":"%s","content":[{"type":"tool_use","id":"%s","name":"Agent","input":{}}],"usage":{"input_tokens":0,"output_tokens":%s,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0}}}}\n' \
    "$1" "$AT" "$BRANCH" "$2" "$3" "$4" "$5" "$MODEL" "$7" "$6"
}
# tree_compact SESSION UUID LOGICAL_PARENT TIMESTAMP — a compaction boundary: parentUuid
# null, the tree continued through logicalParentUuid.
tree_compact() {
  printf '{"type":"system","subtype":"compact_boundary","sessionId":"%s","cwd":"%s","gitBranch":"%s","uuid":"%s","parentUuid":null,"logicalParentUuid":"%s","timestamp":"%s","content":"Conversation compacted"}\n' \
    "$1" "$AT" "$BRANCH" "$2" "$3" "$4"
}
# delegate SESSION AGENT TIMESTAMP OUTPUT [TOOL_USE_ID] — a delegate transcript, with the
# meta.json Claude Code writes beside it naming the tool call that spawned it.
delegate() {
  write_subagent "$1" "$2" "$BRANCH" "$3" "$4" "Delegate $2"
  if [ -n "${5:-}" ]; then
    printf '{"agentType":"general-purpose","toolUseId":"%s"}\n' "$5" > "$PROJECTS/$1/subagents/agent-$2.meta.json"
  fi
}
# Output tokens priced the way the capture prices them, for the exact expected figures.
price_output() {
  python3 -c "import sys; sys.path.insert(0, sys.argv[1]); from pricing import compute_cost; print(compute_cost(sys.argv[2], {'input': 0, 'output': int(sys.argv[3]), 'cache_read': 0, 'cache_creation_5m': 0, 'cache_creation_1h': 0}, as_of=sys.argv[4])[0])" \
    "$AT/analysis" "$MODEL" "$1" "$2"
}

rm -rf "$PROJECTS"/* "$PLANNING" "$LEDGER" "$AT/self/features/other-feature"
{
  tree_user      "$SESSION_C" "i-root" "2026-07-02T09:00:00.000Z" system "Coordinate the feature"
  tree_assistant "$SESSION_C" "i-1" "i-root" "2026-07-02T09:01:00.000Z" "msg-c-i1" 5000 "toolu_coord"
  tree_user      "$SESSION_C" "h-root" "2026-07-02T10:00:00.000Z" sdk "$RUNNER_OPENING"
  tree_assistant "$SESSION_C" "h-1" "h-root" "2026-07-02T10:01:00.000Z" "msg-c-h1" 7000 "toolu_runner"
  tree_compact   "$SESSION_C" "i-compact" "i-1" "2026-07-02T11:00:00.000Z"
  tree_assistant "$SESSION_C" "i-2" "i-compact" "2026-07-02T11:05:00.000Z" "msg-c-i2" 3000 "toolu_coord2"
} > "$PROJECTS/$SESSION_C.jsonl"
delegate "$SESSION_C" "$AGENT_CI" "2026-07-02T09:30:00.000Z" 8000 "toolu_coord"
delegate "$SESSION_C" "$AGENT_CR" "2026-07-02T10:30:00.000Z" 6000 "toolu_runner"
delegate "$SESSION_C" "$AGENT_CU" "2026-07-02T11:30:00.000Z" 4000
{
  tree_user      "$SESSION_R2" "r-root" "2026-07-02T12:00:00.000Z" sdk "$RUNNER_OPENING"
  tree_assistant "$SESSION_R2" "r-1" "r-root" "2026-07-02T12:01:00.000Z" "msg-r2-1" 9000 "toolu_r2"
} > "$PROJECTS/$SESSION_R2.jsonl"
delegate "$SESSION_R2" "$AGENT_R2" "2026-07-02T12:30:00.000Z" 5000 "toolu_r2"
WT_PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT/.worktrees/other" | tr '/.' '--')"
mkdir -p "$WT_PROJECTS/$SESSION_W/subagents"
session_line "$SESSION_W" "$AT/.worktrees/other" "other" "msg-$SESSION_W" "$MODEL" "2026-07-02T13:00:00.000Z" 0 2000 0 0 0 \
  > "$WT_PROJECTS/$SESSION_W.jsonl"
{
  subagent_prompt_line "$SESSION_W" "$AGENT_CW" "$AT/.worktrees/other" "other" "2026-07-02T13:30:00.000Z" "Implementer spawned from another worktree"
  subagent_line "$SESSION_W" "$AGENT_CW" "$AT/.worktrees/other" "other" "msg-$AGENT_CW" "$MODEL" "2026-07-02T13:30:00.000Z" 0 2500 0 0 0
} > "$WT_PROJECTS/$SESSION_W/subagents/agent-$AGENT_CW.jsonl"
SIDECAR_DIR="$AT/self/features/other-feature/review/complete"
mkdir -p "$SIDECAR_DIR"
printf '{"plan":"01-review-opus","session_id":"%s","total_cost_usd":2.0,"attempts":[{"session_id":"%s","total_cost_usd":2.0}]}\n' \
  "$SESSION_C" "$SESSION_C" > "$SIDECAR_DIR/01-review-opus.usage.json"
printf '{"plan":"02-review-opus","session_id":"%s","total_cost_usd":3.0,"attempts":[{"session_id":"%s","total_cost_usd":3.0}]}\n' \
  "$SESSION_R2" "$SESSION_R2" > "$SIDECAR_DIR/02-review-opus.usage.json"
write_manifest "[\"$AGENT_CI\", \"$AGENT_CW\", \"$AGENT_R2\"]"
capture > "$TMP/outC.txt"; rcC=$?

coord_cost="$(price_output 8000 2026-07-02)"
check "C1. the capture succeeds (rc $rcC)" "[ $rcC -eq 0 ]"
check "C2. the collided coordinator is captured, selected by branch, not excluded" \
  "[ \"\$(field \"[(s['session_id'], s['selected_by']) for s in d['sessions']]\")\" = \"[('$SESSION_C', 'branch')]\" ] && [ \"\$(field \"'$SESSION_C' in d['excluded_session_ids']\")\" = False ]"
check "C3. priced at its interactive lines alone — 8000 output tokens, not the runner's 7000 beside them" \
  "near \"\$(field \"sum(p['cost_usd'] for p in d['priced'] if p['session_id']=='$SESSION_C' and not p['agent_id'])\")\" '$coord_cost'"
check "C3b. its span is the coordinator's own, the runner tree's lines dropped from it (09:00 to 11:05)" \
  "[ \"\$(field \"[s['duration_s'] for s in d['sessions'] if s['session_id']=='$SESSION_C']\")\" = '[7500]' ]"
check "C4. the warning names the collision, the session and the sidecar that names it" \
  "grep 'WARN:' '$TMP/outC.txt' | grep '$SESSION_C' | grep -q 'other-feature/review/complete/01-review-opus.usage.json'"
check "C5. the coordinator's pinned implementer is captured, as pinned, under its parent" \
  "[ \"\$(field \"[(s['selected_by'], s['parent_session_id']) for s in d['subagents'] if s['agent_id']=='$AGENT_CI']\")\" = \"[('pinned', '$SESSION_C')]\" ]"
check "C6. a delegate the runner's tree spawned is the sidecar's, never priced here" \
  "[ \"\$(field \"'$AGENT_CR' in [s['agent_id'] for s in d['subagents']] or '$AGENT_CR' in [p['agent_id'] for p in d['priced']]\")\" = False ]"
check "C7. a delegate whose spawning tree cannot be told is the coordinator's, priced by its parent, and warned about by id" \
  "[ \"\$(field \"[s['selected_by'] for s in d['subagents'] if s['agent_id']=='$AGENT_CU']\")\" = \"['parent']\" ] && grep 'WARN:' '$TMP/outC.txt' | grep -q '$AGENT_CU'"
check "C8. a runner session with a file of its own is still excluded exactly as before" \
  "[ \"\$(field \"'$SESSION_R2' in d['excluded_session_ids'] and '$SESSION_R2' not in [s['session_id'] for s in d['sessions']]\")\" = True ]"
check "C8b. ... and no collision is claimed for it" "! grep 'WARN:' '$TMP/outC.txt' | grep -q '$SESSION_R2.*interactive'"
check "C9. a pinned delegate of that runner session is still never priced — its sidecar holds it" \
  "[ \"\$(field \"'$AGENT_R2' in [s['agent_id'] for s in d['subagents']]\")\" = False ]"
check "C10. a pinned delegate whose parent the main walk never reached is found in this repo's own directories" \
  "[ \"\$(field \"[(s['selected_by'], s['parent_session_id']) for s in d['subagents'] if s['agent_id']=='$AGENT_CW']\")\" = \"[('pinned', '$SESSION_W')]\" ]"
check "C11. the priced delegates are exactly the implementer, the untold one and the found one" \
  "[ \"\$(field \"sorted(set(p['agent_id'] for p in d['priced'] if p['agent_id']))\")\" = \"['$AGENT_CI', '$AGENT_CU', '$AGENT_CW']\" ]"
check "C11b. and the total is the coordinator's own 8000 tokens plus those three — nothing of the runner's" \
  "near '$(total_of)' \"\$(field \"$coord_cost + sum(p['cost_usd'] for p in d['priced'] if p['agent_id'])\")\""

# ── C, round 2: a collided coordinator found only through the pinned-session fallback ──
# Round 1's review (escalations/01-review-opus.md): a pinned coordinator whose collided
# transcript is filed under ANOTHER project directory is reached only by the pinned-
# session fallback, which ran after the pinned-delegate fallback — so its delegates were
# skipped as a runner-only session's, and a delegate the fallback did reach was never
# asked which tree spawned it. The same fixture, plus a second project directory holding
# coordinator E: its interactive tree spawns the implementer EI (4000 output tokens of its
# own), the runner's tree spawns ER; both delegates and E itself are pinned, and a
# usage.json names E. RED on round 1's code: EI is unmatched, ER's pin is not called
# ignored.
SESSION_E="ffffffff-0000-0000-0000-00000000000f"   # pinned coordinator, collided, filed elsewhere
AGENT_EI="e1e1e1e1e1e1e1e1e"   # E's implementer, spawned by its interactive tree — pinned
AGENT_ER="e2e2e2e2e2e2e2e2e"   # spawned by E's runner tree — pinned, still runner cost
COLL_PROJECTS="$FAKE_HOME/.claude/projects/-elsewhere-coordinator"
mkdir -p "$COLL_PROJECTS/$SESSION_E/subagents"
{
  tree_user      "$SESSION_E" "e-root" "2026-07-03T09:00:00.000Z" system "Coordinate from another checkout"
  tree_assistant "$SESSION_E" "e-1" "e-root" "2026-07-03T09:01:00.000Z" "msg-e-i1" 4000 "toolu_e_coord"
  tree_user      "$SESSION_E" "eh-root" "2026-07-03T10:00:00.000Z" sdk "$RUNNER_OPENING"
  tree_assistant "$SESSION_E" "eh-1" "eh-root" "2026-07-03T10:01:00.000Z" "msg-e-h1" 6000 "toolu_e_runner"
} > "$COLL_PROJECTS/$SESSION_E.jsonl"
for pair in "$AGENT_EI:toolu_e_coord:2026-07-03T09:30:00.000Z" "$AGENT_ER:toolu_e_runner:2026-07-03T10:30:00.000Z"; do
  e_agent="${pair%%:*}"; e_rest="${pair#*:}"; e_tool="${e_rest%%:*}"; e_ts="${e_rest#*:}"
  {
    subagent_prompt_line "$SESSION_E" "$e_agent" "$AT" "$BRANCH" "$e_ts" "Delegate $e_agent"
    subagent_line "$SESSION_E" "$e_agent" "$AT" "$BRANCH" "msg-$e_agent" "$MODEL" "$e_ts" 100 3000 0 0 0
  } > "$COLL_PROJECTS/$SESSION_E/subagents/agent-$e_agent.jsonl"
  printf '{"agentType":"general-purpose","toolUseId":"%s"}\n' "$e_tool" > "$COLL_PROJECTS/$SESSION_E/subagents/agent-$e_agent.meta.json"
done
printf '{"plan":"03-review-opus","session_id":"%s","total_cost_usd":1.5,"attempts":[{"session_id":"%s","total_cost_usd":1.5}]}\n' \
  "$SESSION_E" "$SESSION_E" > "$SIDECAR_DIR/03-review-opus.usage.json"
cat > "$FEATURE_DIR/README.md" <<MANIFEST
# $SLUG

\`\`\`json
{
  "slug": "$SLUG",
  "branches": ["$BRANCH"],
  "session_window": {"from": "$WINDOW_FROM", "to": "$WINDOW_TO"},
  "exclude_sessions": [],
  "sessions": ["$SESSION_E"],
  "subagents": ["$AGENT_CI", "$AGENT_CW", "$AGENT_R2", "$AGENT_EI", "$AGENT_ER"]
}
\`\`\`
MANIFEST
capture > "$TMP/outC12.txt"; rcC12=$?

check "C12. the capture succeeds (rc $rcC12)" "[ $rcC12 -eq 0 ]"
check "C12b. the coordinator filed under a second project directory is captured as pinned, and its collision warned about" \
  "[ \"\$(field \"[s['selected_by'] for s in d['sessions'] if s['session_id']=='$SESSION_E']\")\" = \"['pinned']\" ] && grep 'WARN:' '$TMP/outC12.txt' | grep '$SESSION_E' | grep -q '03-review-opus.usage.json'"
check "C13. its pinned implementer is priced, as pinned, under it" \
  "[ \"\$(field \"[(s['selected_by'], s['parent_session_id']) for s in d['subagents'] if s['agent_id']=='$AGENT_EI']\")\" = \"[('pinned', '$SESSION_E')]\" ] && [ \"\$(field \"'$AGENT_EI' in [p['agent_id'] for p in d['priced']]\")\" = True ]"
check "C13b. and is not reported as an unmatched pin" "! grep 'WARN:' '$TMP/outC12.txt' | grep '$AGENT_EI' | grep -q 'matches no transcript'"
check "C14. a pinned delegate whose meta.json toolUseId points into the runner tree is not priced" \
  "[ \"\$(field \"'$AGENT_ER' in [s['agent_id'] for s in d['subagents']] or '$AGENT_ER' in [p['agent_id'] for p in d['priced']]\")\" = False ]"
check "C14b. and the capture warns that its pin is ignored" \
  "grep 'WARN:' '$TMP/outC12.txt' | grep '$AGENT_ER' | grep -q 'the pin is ignored'"

echo
if [ "$fails" -eq 0 ]; then echo "subagent-capture: all ok"; else echo "subagent-capture: $fails FAIL"; exit 1; fi
