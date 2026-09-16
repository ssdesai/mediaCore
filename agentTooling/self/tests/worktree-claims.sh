#!/usr/bin/env bash
set -uo pipefail

# Self-test for which launch directories a feature can claim a session from, now that
# feature worktrees live INSIDE the primary checkout (self/features/in-repo-worktrees/).
# Run by self/gate.sh, or by hand: bash self/tests/worktree-claims.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d — copies of
# `analysis/{pricing,roots,transcript,capture_planning}.py` — one feature manifest, and,
# under a redirected $HOME, the `~/.claude/projects/*/<session_id>.jsonl` transcripts
# capture reads, each filed under the project directory Claude Code would give its launch
# cwd: the path with every `/` and `.` turned into `-`. No model, no network.
#
# For slug S and primary checkout R, the claimable launch directories are R itself, the
# feature's worktree R/.worktrees/S, and the legacy sibling R-S a feature started before
# this layout still has. R/.worktrees/<other> is under R, and must NOT be claimable: it is
# another feature's worktree, and a plain prefix test on R would hand every feature's
# sessions to every other feature.
#
# Asserts, in order:
#   W0. the fixture's premise: R's own path carries a `.`, so its project directory name
#       is mangled differently from the path, and every nested project dir is named
#       `…-R--worktrees-<slug>`;
#   W1. capture selects by branch the sessions launched in R, in R/.worktrees/S and in
#       the legacy R-S, recording each one's cwd;
#   W2. and does not select the one launched in R/.worktrees/<other>, though it carries
#       S's branch and sits under R — the warning names where it was seen; nor the ones
#       launched in R/.worktrees/S-two and R-S-two, whose paths merely START with S's
#       worktree paths (a bare startswith(root) would claim both);
#   W3. the delegate of the session launched in R/.worktrees/S, filed under that
#       session's mangled nested project directory, is priced with its parent;
#   W4. --last-branch-instant is bounded by the claimable sessions and that delegate,
#       not by the later session in R/.worktrees/<other>;
#   W5. --list-sessions finds the sessions filed under the nested and legacy project
#       directories, and --list-subagents the delegate under the nested one.
#
# W1's nested and legacy halves, W2 and W4 were RED until capture_planning.py fenced
# R/.worktrees; everything was RED until transcript_dir_name mangled `.` as Claude Code
# does, because R's path carries one (W0).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The template's dots are deliberate: they put a `.` in R's own path (W0).
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wt.claims.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Physical path: roots.py resolves AGENT_TOOLING_DIR with Path.resolve(), and a cwd is
# compared against that resolved root (capture-guard.sh explains the macOS /var case).
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"
for f in pricing.py roots.py transcript.py capture_planning.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done
# session_root() walks up to the nearest ancestor holding .git; this one makes it $AT.
mkdir -p "$AT/.git"
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
pj() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }

# The layout under test (LIFECYCLE.md): R/.worktrees/<slug>, and the legacy R-<slug>.
WORKTREES_DIR=".worktrees"
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"
# Claude Code's project directory name for a launch cwd: every `/` and `.` becomes `-`.
project_dir() { echo "$FAKE_HOME/.claude/projects/$(printf '%s' "$1" | tr '/.' '--')"; }
capture() { HOME="$FAKE_HOME" python3 -B "$AT/analysis/capture_planning.py" --self "$@" 2>&1; }

SLUG="nest-me"
OTHER="other-one"
MODEL="claude-sonnet-5"
NESTED="$AT/$WORKTREES_DIR/$SLUG"
LEGACY="$AT-$SLUG"
OTHER_WT="$AT/$WORKTREES_DIR/$OTHER"
# Another feature whose slug has S as a prefix, in both layouts.
PREFIX_NESTED="$AT/$WORKTREES_DIR/$SLUG-two"
PREFIX_LEGACY="$AT-$SLUG-two"

mkdir -p "$AT/self/features/$SLUG"
cat > "$AT/self/features/$SLUG/README.md" <<EOF
# $SLUG

\`\`\`json
{"slug": "$SLUG", "plans": [], "branches": ["$SLUG"],
 "session_window": {"from": "2026-06-01T00:00:00Z", "to": "2026-06-02T00:00:00Z"}}
\`\`\`
EOF

S_PRIMARY="pppppppp-0000-0000-0000-000000000001"
S_NESTED="nnnnnnnn-0000-0000-0000-000000000002"
S_LEGACY="llllllll-0000-0000-0000-000000000003"
S_OTHER="oooooooo-0000-0000-0000-000000000004"
AGENT_N="a2222222222222222"

mkdir -p "$(project_dir "$AT")" "$(project_dir "$NESTED")/$S_NESTED/subagents" \
  "$(project_dir "$LEGACY")" "$(project_dir "$OTHER_WT")"
session_line "$S_PRIMARY" "$AT" "$SLUG" "msg-p" "$MODEL" "2026-06-01T10:00:00.000Z" 100 1000 0 0 0 \
  > "$(project_dir "$AT")/$S_PRIMARY.jsonl"
session_line "$S_NESTED" "$NESTED" "$SLUG" "msg-n" "$MODEL" "2026-06-01T11:00:00.000Z" 100 2000 0 0 0 \
  > "$(project_dir "$NESTED")/$S_NESTED.jsonl"
{
  subagent_prompt_line "$S_NESTED" "$AGENT_N" "$NESTED" "$SLUG" "2026-06-01T12:00:00.000Z" "feature: agentTooling/$SLUG\\nbuild it"
  subagent_line "$S_NESTED" "$AGENT_N" "$NESTED" "$SLUG" "msg-na" "$MODEL" "2026-06-01T15:00:00.000Z" 100 3000 0 0 0
} > "$(project_dir "$NESTED")/$S_NESTED/subagents/agent-$AGENT_N.jsonl"
session_line "$S_LEGACY" "$LEGACY" "$SLUG" "msg-l" "$MODEL" "2026-06-01T13:00:00.000Z" 100 4000 0 0 0 \
  > "$(project_dir "$LEGACY")/$S_LEGACY.jsonl"
# Latest of all, and on S's branch: were it claimable it would both be priced and set
# the bound W4 reads.
session_line "$S_OTHER" "$OTHER_WT" "$SLUG" "msg-o" "$MODEL" "2026-06-01T20:00:00.000Z" 100 5000 0 0 0 \
  > "$(project_dir "$OTHER_WT")/$S_OTHER.jsonl"
# Later still, for the same reason: a leak would be priced and would move W4's bound.
S_PREFIX_NESTED="qqqqqqqq-0000-0000-0000-000000000005"
S_PREFIX_LEGACY="rrrrrrrr-0000-0000-0000-000000000006"
mkdir -p "$(project_dir "$PREFIX_NESTED")" "$(project_dir "$PREFIX_LEGACY")"
session_line "$S_PREFIX_NESTED" "$PREFIX_NESTED" "$SLUG" "msg-qn" "$MODEL" "2026-06-01T21:00:00.000Z" 100 6000 0 0 0 \
  > "$(project_dir "$PREFIX_NESTED")/$S_PREFIX_NESTED.jsonl"
session_line "$S_PREFIX_LEGACY" "$PREFIX_LEGACY" "$SLUG" "msg-ql" "$MODEL" "2026-06-01T22:00:00.000Z" 100 7000 0 0 0 \
  > "$(project_dir "$PREFIX_LEGACY")/$S_PREFIX_LEGACY.jsonl"

echo "worktree claims"

# ── W0. the fixture's premise ─────────────────────────────────────────────────
check "W0a. R's own path carries a '.', so its project dir name differs from the path" '[[ "$AT" == *.* ]]'
check "W0b. the nested worktree's project dir is named …-R--worktrees-S" \
  '[[ -d "$FAKE_HOME/.claude/projects/$(printf "%s" "$AT" | tr "/." "--")--worktrees-$SLUG" ]]'

# ── W1–W3. capture ────────────────────────────────────────────────────────────
out="$(capture "$SLUG")"; rc=$?
PJ="$AT/self/features/$SLUG/planning.json"
selected() { pj "$PJ" "sorted((s['session_id'], s['selected_by'], s['cwd']) for s in d['sessions'])"; }
check "W1a. capture exits 0 (got $rc)" '[[ $rc -eq 0 && -f "$PJ" ]]'
check "W1b. the session launched in R is selected by branch" \
  'grep -qF "('"'"'$S_PRIMARY'"'"', '"'"'branch'"'"', '"'"'$AT'"'"')" <<<"$(selected)"'
check "W1c. the session launched in R/$WORKTREES_DIR/S is selected by branch, cwd recorded" \
  'grep -qF "('"'"'$S_NESTED'"'"', '"'"'branch'"'"', '"'"'$NESTED'"'"')" <<<"$(selected)"'
check "W1d. the session launched in the legacy sibling R-S is still selected" \
  'grep -qF "('"'"'$S_LEGACY'"'"', '"'"'branch'"'"', '"'"'$LEGACY'"'"')" <<<"$(selected)"'
check "W2a. the session launched in R/$WORKTREES_DIR/<other> is NOT selected, though it is under R" \
  '[[ "$(pj "$PJ" "\"$S_OTHER\" in [s[\"session_id\"] for s in d[\"sessions\"]]")" == "False" ]]'
check "W2b. ... exactly three sessions are selected" '[[ "$(pj "$PJ" "len(d[\"sessions\"])")" == "3" ]]'
check "W2c. ... and the warning names the directory it was launched from" 'grep -qF "$OTHER_WT" <<<"$out"'
check "W2d. the session launched in R/$WORKTREES_DIR/S-two (a prefix-sharing slug) is NOT selected" \
  '[[ "$(pj "$PJ" "\"$S_PREFIX_NESTED\" in [s[\"session_id\"] for s in d[\"sessions\"]]")" == "False" ]]'
check "W2e. nor the one launched in the legacy sibling R-S-two" \
  '[[ "$(pj "$PJ" "\"$S_PREFIX_LEGACY\" in [s[\"session_id\"] for s in d[\"sessions\"]]")" == "False" ]]'
check "W3. the delegate filed under the nested project dir is priced with its parent" \
  '[[ "$(pj "$PJ" "[(a[\"agent_id\"], a[\"selected_by\"]) for a in d[\"subagents\"]]")" == "[('"'"'$AGENT_N'"'"', '"'"'parent'"'"')]" ]]'

# ── W4. the evidence bound ────────────────────────────────────────────────────
bound="$(capture --last-branch-instant "$SLUG")"
check "W4. --last-branch-instant is the nested delegate's last instant + 1s, not the other worktree's (got $bound)" \
  '[[ "$bound" == "2026-06-01T15:00:01Z" ]]'

# ── W5. discovery ─────────────────────────────────────────────────────────────
sessions_out="$(capture --list-sessions)"
check "W5a. --list-sessions finds the session filed under the nested project dir" 'grep -q "$S_NESTED" <<<"$sessions_out"'
check "W5b. ... and the one under the legacy project dir, and the primary's" \
  'grep -q "$S_LEGACY" <<<"$sessions_out" && grep -q "$S_PRIMARY" <<<"$sessions_out"'
agents_out="$(capture --list-subagents)"
check "W5c. --list-subagents finds the delegate under the nested project dir" 'grep -q "$AGENT_N" <<<"$agents_out"'

echo
if (( fails > 0 )); then echo "worktree-claims: $fails assertion(s) FAILED"; exit 1; fi
echo "worktree-claims: all assertions passed"
