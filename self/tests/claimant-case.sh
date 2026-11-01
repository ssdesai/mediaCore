#!/usr/bin/env bash
set -uo pipefail

# Self-test: a feature named in two repo-name spellings is ONE claimant
# (self/features/cloud-pull-fixes/, defect C). Run by self/gate.sh, or by hand:
# bash self/tests/claimant-case.sh
#
# In one cloud container the consuming repos were cloned to lowercase directories from
# lowercase origin URLs (https://github.com/ssdesai/musicmap), so captures there wrote
# claims as `musicmap/<slug>` while every record frozen on a laptop says `musicMap/<slug>`.
# Every close's frozen-record refresh then wrote both into dozens of other features'
# `also_claimed_by`. What this asserts:
#
#   C1. `--annotate-frozen` over a record already holding BOTH spellings of one mention
#       leaves one, the mixed-case spelling, and names the record on stdout;
#   C2. a record holding `musicMap/<slug>` whose claimant the ledger has NOT seen, while
#       the ledger's own claim for that session spells it `musicmap/<slug>`, ends with one
#       mention, `musicMap/<slug>` — the kept mention and the ledger's are the same feature;
#   C3. a second `--annotate-frozen` over the unchanged corpus prints nothing and leaves
#       every record and the ledger byte-identical;
#   C4. report.py's shared-session list (`compute_shared_sessions`) unions
#       `also_claimed_by` and `share_basis` without a case-only duplicate;
#   C5. check_brief_headers does not warn on a brief whose repo half differs only in case
#       (`agenttooling/<slug>` for `agentTooling`), and still warns on another repo;
#   C6. `--list-subagents --unclaimed --for agenttooling/<slug>` lists a delegate whose
#       brief names `agentTooling/<slug>` — the `--for` feature-capture.sh asks with;
#   C7. plan-runner-roots.sh's feature_repo_name names a checkout by its origin's
#       repository name (`musicMap` for a `musicmap/` directory cloned from
#       `git@github.com:o/musicMap.git`), by its directory without an origin, and as
#       `agentTooling` under --self — the same string analysis's
#       repo_display_name(roots.SELF_CORPUS_IDENTITY) gives;
#   C8. feature-start.sh's brief-header line and feature-capture.sh's `--for` both use it.
#
# A throwaway agentTooling checkout with analysis/*.py, hand-written manifests and frozen
# records, and a hand-written claims ledger under a redirected $HOME. No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/claimant-case.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features" "$AT/.git"
export RATES_LIVE_LOOKUP=off
for f in pricing.py litellm_prices.py rates_history.json roots.py transcript.py capture_planning.py report.py routing.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

FAKE_HOME="$TMP/home"
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/.' '--')"
mkdir -p "$PROJECTS"
export HOME="$FAKE_HOME"
LEDGER="$FAKE_HOME/.claude/subagent-claims.json"

# The two spellings of one repo, and the identity its cloud clone carries
CLOUD_IDENTITY="https://github.com/ssdesai/musicmap"
CLOUD_NAME="musicmap"
LAPTOP_NAME="musicMap"
SEEN_KEY="github.com/ssdesai/musicmap"
SEEN_SLUG="feat-x"
UNSEEN_SLUG="feat-y"
SESSION_ONE="11111111-0000-0000-0000-000000000001"
SESSION_TWO="11111111-0000-0000-0000-000000000002"
SESSION_COORD="11111111-0000-0000-0000-000000000003"
AGENT_ID="a3333333333333333"
SELF_NAME="agentTooling"
BRANCH="claimant-case-branch"
WINDOW_FROM="2026-07-01T00:00:00Z"
WINDOW_TO="2026-07-05T00:00:00Z"
CAPTURED_AT="2026-07-06T00:00:00Z"
TS="2026-07-02T10:00:00.000Z"
MODEL="claude-sonnet-5"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
mentions() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d["sessions"][0].get("also_claimed_by")))' "$1" 2>/dev/null; }

# frozen <slug> <session> <also_claimed_by JSON> — a closed manifest and its frozen record
frozen() {
  local dir="$AT/self/features/$1"
  mkdir -p "$dir"
  printf '# %s\n\n```json\n{"slug": "%s", "plans": [], "branches": ["%s"], "session_window": {"from": "%s", "to": "%s"}, "sessions": [], "subagents": []}\n```\n' \
    "$1" "$1" "$BRANCH" "$WINDOW_FROM" "$WINDOW_TO" > "$dir/README.md"
  printf '{\n  "captured_at": "%s",\n  "sessions": [\n    {\n      "session_id": "%s",\n      "selected_by": "branch",\n      "also_claimed_by": %s\n    }\n  ],\n  "priced": []\n}' \
    "$CAPTURED_AT" "$2" "$3" > "$dir/planning.json"
}

echo "claimant-case"

frozen one "$SESSION_ONE" "[\"$LAPTOP_NAME/$SEEN_SLUG\", \"$CLOUD_NAME/$SEEN_SLUG\"]"
frozen two "$SESSION_TWO" "[\"$LAPTOP_NAME/$UNSEEN_SLUG\"]"

# The ledger a cloud capture leaves: claims spelled from the lowercase origin, and only
# SEEN_SLUG registered as seen.
mkdir -p "$FAKE_HOME/.claude"
cat > "$LEDGER" <<LEDGER_JSON
{
  "subagents": {},
  "sessions": {
    "$SESSION_ONE": [{"repo": "$CLOUD_IDENTITY", "repo_name": "$CLOUD_NAME", "slug": "$SEEN_SLUG", "selected_by": "branch", "cost_usd": 0.0, "claimed_at": "$CAPTURED_AT", "window": {"from": "$WINDOW_FROM", "to": "$WINDOW_TO"}}],
    "$SESSION_TWO": [{"repo": "$CLOUD_IDENTITY", "repo_name": "$CLOUD_NAME", "slug": "$UNSEEN_SLUG", "selected_by": "branch", "cost_usd": 0.0, "claimed_at": "$CAPTURED_AT", "window": {"from": "$WINDOW_FROM", "to": "$WINDOW_TO"}}]
  },
  "seen": {
    "$SEEN_KEY": {"repo": "$CLOUD_IDENTITY", "repo_name": "$CLOUD_NAME", "registered_at": null, "features": {"$SEEN_SLUG": "$CAPTURED_AT"}}
  }
}
LEDGER_JSON

annotate() { python3 "$AT/analysis/capture_planning.py" --self --annotate-frozen 2>"$TMP/annotate-err.txt"; }

# ── C1/C2. one mention per feature, the mixed-case spelling ──────────────────
out="$(annotate)"; rc=$?
check "C1a. --annotate-frozen exits 0 (got $rc: $(cat "$TMP/annotate-err.txt"))" '[[ $rc -eq 0 ]]'
check "C1b. a record holding both spellings keeps one, $LAPTOP_NAME/$SEEN_SLUG (got $(mentions "$AT/self/features/one/planning.json"))" \
  '[[ "$(mentions "$AT/self/features/one/planning.json")" == "[\"$LAPTOP_NAME/$SEEN_SLUG\"]" ]]'
check "C1c. ... and stdout names it" 'grep -qx "one" <<<"$out"'
check "C2. an unseen claimant kept as $LAPTOP_NAME/$UNSEEN_SLUG is not doubled by the ledger's $CLOUD_NAME/$UNSEEN_SLUG (got $(mentions "$AT/self/features/two/planning.json"))" \
  '[[ "$(mentions "$AT/self/features/two/planning.json")" == "[\"$LAPTOP_NAME/$UNSEEN_SLUG\"]" ]]'

# ── C3. a refresh over an unchanged corpus writes nothing ────────────────────
cp "$AT/self/features/one/planning.json" "$TMP/one.json"
cp "$AT/self/features/two/planning.json" "$TMP/two.json"
cp "$LEDGER" "$TMP/ledger.json"
out="$(annotate)"; rc=$?
check "C3a. the second run exits 0 and names no record (got '$out')" '[[ $rc -eq 0 && -z "$out" ]]'
check "C3b. both records byte-identical" \
  'cmp -s "$TMP/one.json" "$AT/self/features/one/planning.json" && cmp -s "$TMP/two.json" "$AT/self/features/two/planning.json"'
check "C3c. the ledger byte-identical" 'cmp -s "$TMP/ledger.json" "$LEDGER"'

# ── C4/C5. report's union and the brief-header check ─────────────────────────
py_out="$(python3 - "$AT/analysis" "$LAPTOP_NAME" "$CLOUD_NAME" "$SELF_NAME" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
laptop, cloud, self_name = sys.argv[2:5]
import report, capture_planning
shared = report.compute_shared_sessions({
    "sessions": [{
        "session_id": "s",
        "also_claimed_by": [f"{laptop}/feat-x"],
        "share_basis": [
            {"feature": f"{self_name}/one", "source": "self"},
            {"feature": f"{cloud}/feat-x", "source": "ledger"},
        ],
    }],
    "priced": [],
})
print("C4", shared[0]["also_claimed_by"] if shared else None)
quiet = capture_planning.check_brief_headers({"a1": (self_name.lower(), "one")}, self_name, "one")
loud = capture_planning.check_brief_headers({"a1": ("otherRepo", "one")}, self_name, "one")
print("C5", len(quiet), len(loud))
PY
)"
WANT_C4="C4 ['$LAPTOP_NAME/feat-x']"
check "C4. the shared-session union names $LAPTOP_NAME/feat-x once (got: $(grep '^C4' <<<"$py_out"))" \
  '[[ "$(grep "^C4" <<<"$py_out")" == "$WANT_C4" ]]'
check "C5. no warning for a case-only difference, one for another repo (got: $(grep '^C5' <<<"$py_out"))" \
  '[[ "$(grep "^C5" <<<"$py_out")" == "C5 0 1" ]]'

# ── C6. --for is case-insensitive in the repo half ───────────────────────────
mkdir -p "$PROJECTS/$SESSION_COORD/subagents"
{
  subagent_prompt_line "$SESSION_COORD" "$AGENT_ID" "$AT" "main" "$TS" "feature: $SELF_NAME/one\\nbuild it"
  subagent_line "$SESSION_COORD" "$AGENT_ID" "$AT" "main" "msg-$AGENT_ID" "$MODEL" "$TS" 100 2000 0 0 0
} > "$PROJECTS/$SESSION_COORD/subagents/agent-$AGENT_ID.jsonl"
SELF_NAME_LOWER="$(tr '[:upper:]' '[:lower:]' <<<"$SELF_NAME")"
out="$(python3 "$AT/analysis/capture_planning.py" --self --list-subagents --unclaimed --for "$SELF_NAME_LOWER/one" 2>&1)"
check "C6. --for $SELF_NAME_LOWER/one lists the delegate briefed for $SELF_NAME/one" 'grep -qF "$AGENT_ID" <<<"$out"'

# ── C7. the shell's repo name ────────────────────────────────────────────────
mkdir -p "$TMP/clones/musicmap" "$TMP/clones/plainrepo"
git -C "$TMP/clones/musicmap" init -q
git -C "$TMP/clones/musicmap" remote add origin "git@github.com:ssdesai/$LAPTOP_NAME.git"
git -C "$TMP/clones/plainrepo" init -q
name_of() { ( SELF_MODE="$2"; source "$HERE/plan-runner-roots.sh"; feature_repo_name "$1" ) 2>/dev/null; }
check "C7a. a musicmap/ checkout cloned from .../$LAPTOP_NAME.git is $LAPTOP_NAME (got $(name_of "$TMP/clones/musicmap" 0))" \
  '[[ "$(name_of "$TMP/clones/musicmap" 0)" == "$LAPTOP_NAME" ]]'
check "C7b. a checkout with no origin is its directory (got $(name_of "$TMP/clones/plainrepo" 0))" \
  '[[ "$(name_of "$TMP/clones/plainrepo" 0)" == "plainrepo" ]]'
py_self="$(python3 -c 'import sys; sys.dont_write_bytecode=True; sys.path.insert(0, sys.argv[1]); import roots, capture_planning; print(capture_planning.repo_display_name(roots.SELF_CORPUS_IDENTITY))' "$AT/analysis" 2>/dev/null)"
check "C7c. under --self it is $SELF_NAME, analysis's own name for the self corpus (got $(name_of "$TMP/clones/musicmap" 1), analysis $py_self)" \
  '[[ "$(name_of "$TMP/clones/musicmap" 1)" == "$SELF_NAME" && "$py_self" == "$SELF_NAME" ]]'

# ── C8. both lifecycle scripts name the repo through it ──────────────────────
check "C8a. feature-start.sh derives its brief-header repo name with feature_repo_name" \
  'grep -qE "^REPO_NAME=\"\\\$\(feature_repo_name " "$HERE/feature-start.sh"'
check "C8b. feature-capture.sh derives its --for repo name with feature_repo_name" \
  'grep -qE "^REPO_NAME=\"\\\$\(feature_repo_name " "$HERE/feature-capture.sh"'

echo
if (( fails > 0 )); then
  echo "claimant-case: $fails failed"
  exit 1
fi
echo "claimant-case: all passed"
