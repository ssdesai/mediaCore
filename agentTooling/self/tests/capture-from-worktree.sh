#!/usr/bin/env bash
set -uo pipefail

# Self-test: a capture run from a feature WORKTREE's copy of the analysis scripts selects
# what a capture from the primary would (self/DESIGN-2026-09-16-lifecycle-restructure.md
# §3.2, §4). Run by self/gate.sh, or by hand: bash self/tests/capture-from-worktree.sh
#
# Why this exists. feature-capture.sh runs in the worktree, on the branch, before the
# merge — so the copy of capture_planning.py it runs is the WORKTREE's. That copy used to
# be the wrong one: `roots.session_root` is the nearest ancestor holding `.git`, and a
# worktree's `.git` is a file of its own, so the session root landed on the worktree, the
# claim roots and the transcript-directory scan were derived from it, and the primary's
# project directory was outside both. The rule now is that a worktree's `.git` file is
# followed to its common git dir, whose parent is the primary checkout — the same session
# root the primary's own copy resolves.
#
# A real git repo R with a real `git worktree add R/.worktrees/S`, the analysis scripts
# committed in R so the worktree carries its own copy, a manifest committed on S, and
# under a redirected $HOME the transcripts:
#   W  launched in R/.worktrees/S on branch S, with a delegate under it;
#   M  launched in R on main, not pinned — never this feature's;
#   P  launched in R on main, pinned in the manifest's `sessions`;
#   O  launched in R/.worktrees/other on branch S — another feature's worktree, fenced off.
#
# Asserts, in order:
#   F1. `roots.session_root(True)` from the worktree's copy is R, not the worktree;
#   F2. `capture_planning.py --self S` run from the worktree's copy exits 0 and writes
#       planning.json into the WORKTREE's corpus, and none into R's;
#   F3. it claims W by branch with its cwd, and W's delegate with it;
#   F4. it does not claim M (main, unpinned) nor O (another feature's worktree);
#   F5. it does claim P, as pinned — the one way a primary session on main is in;
#   F6. `--last-branch-instant S` from the worktree's copy is W's delegate's last instant
#       plus one second;
#   F7. `--list-sessions` from the worktree's copy lists sessions filed under R's own
#       project directory as well as the worktree's.
#
# RED until roots.session_root follows a worktree's .git file. No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/capture-wt.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

# The repo under test, and the worktree layout feature-start.sh makes (LIFECYCLE.md).
R="$TMP/agentTooling"
SLUG="wt-capture"
WORKTREES_DIR=".worktrees"
WT="$R/$WORKTREES_DIR/$SLUG"
OTHER_WT="$R/$WORKTREES_DIR/other"
MODEL="claude-sonnet-5"

# Session and agent ids, and their instants. The window opens at FROM; W's delegate runs
# past W's own last line, so F6's bound is the delegate's.
FROM="2026-06-01T00:00:00Z"
S_W="wwwwwwww-1111-0000-0000-000000000001"
S_M="mmmmmmmm-1111-0000-0000-000000000002"
S_P="pppppppp-1111-0000-0000-000000000003"
S_O="oooooooo-1111-0000-0000-000000000004"
A_W="a2222222222222221"
T_W="2026-06-01T10:00:00.000Z"
T_A="2026-06-01T11:00:00.000Z"
T_M="2026-06-01T10:30:00.000Z"
T_P="2026-06-01T09:00:00.000Z"
T_O="2026-06-01T10:15:00.000Z"
EXPECTED_BOUND="2026-06-01T11:00:01Z"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
pj() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }

mkdir -p "$R/analysis" "$R/self/features"
for f in pricing.py roots.py transcript.py capture_planning.py routing.py; do
  cp "$HERE/analysis/$f" "$R/analysis/$f" 2>/dev/null || true
done
printf '__pycache__/\n' > "$R/.gitignore"
git -C "$R" init -q
git -C "$R" symbolic-ref HEAD refs/heads/main
git -C "$R" config user.email test@example.invalid
git -C "$R" config user.name "capture-from-worktree test"
git -C "$R" add -A
git -C "$R" commit -q -m "init"
git -C "$R" worktree add -q "$WT" -b "$SLUG"
git -C "$R" worktree add -q "$OTHER_WT" -b other

FD="$WT/self/features/$SLUG"
mkdir -p "$FD"
printf '# %s\n\nTest fixture only.\n\n```json\n{"slug": "%s", "method": "direct", "plans": [], "branches": ["%s"], "base": "main", "session_window": {"from": "%s", "to": null}, "exclude_sessions": [], "exclude_subagents": [], "sessions": ["%s"], "subagents": []}\n```\n' \
  "$SLUG" "$SLUG" "$SLUG" "$FROM" "$S_P" > "$FD/README.md"
git -C "$WT" add -A
git -C "$WT" commit -q -m "$SLUG: start"

FAKE_HOME="$TMP/home"
project_dir() { echo "$FAKE_HOME/.claude/projects/$(echo "$1" | tr '/.' '--')"; }
WP="$(project_dir "$WT")"; RP="$(project_dir "$R")"; OP="$(project_dir "$OTHER_WT")"
mkdir -p "$WP/$S_W/subagents" "$RP" "$OP"
session_line "$S_W" "$WT" "$SLUG" "m-w" "$MODEL" "$T_W" 100 5000 0 0 0 > "$WP/$S_W.jsonl"
subagent_line "$S_W" "$A_W" "$WT" "$SLUG" "m-a" "$MODEL" "$T_A" 100 2000 0 0 0 \
  > "$WP/$S_W/subagents/agent-$A_W.jsonl"
session_line "$S_M" "$R" "main" "m-m" "$MODEL" "$T_M" 100 3000 0 0 0 > "$RP/$S_M.jsonl"
session_line "$S_P" "$R" "main" "m-p" "$MODEL" "$T_P" 100 4000 0 0 0 > "$RP/$S_P.jsonl"
session_line "$S_O" "$OTHER_WT" "$SLUG" "m-o" "$MODEL" "$T_O" 100 1000 0 0 0 > "$OP/$S_O.jsonl"

wt_py() { HOME="$FAKE_HOME" python3 -B "$@" 2>&1; }

echo "capture from worktree"

root="$(wt_py -c "import sys; sys.path.insert(0, sys.argv[1]); import roots; print(roots.session_root(True))" "$WT/analysis")"
check "F1. session_root from the worktree's copy is the primary checkout (got $root)" '[[ "$root" == "$R" ]]'

out="$(wt_py "$WT/analysis/capture_planning.py" --self "$SLUG")"; rc=$?
PJ="$FD/planning.json"
check "F2. a capture from the worktree's copy exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "F2b. ... writing planning.json into the worktree's corpus and none into the primary's" \
  '[[ -f "$PJ" && ! -e "$R/self/features/$SLUG/planning.json" ]]'
check "F3. the session launched in the worktree is claimed by branch, cwd recorded" \
  '[[ "$(pj "$PJ" "[(s[\"selected_by\"], s[\"cwd\"]) for s in d[\"sessions\"] if s[\"session_id\"] == \"$S_W\"]")" == "[('"'"'branch'"'"', '"'"'$WT'"'"')]" ]]'
check "F3b. ... and its delegate with it" \
  '[[ "$(pj "$PJ" "[a[\"agent_id\"] for a in d[\"subagents\"]]")" == "['"'"'$A_W'"'"']" ]]'
check "F4. a session in the primary on main, unpinned, is not claimed" \
  '[[ "$(pj "$PJ" "\"$S_M\" in [s[\"session_id\"] for s in d[\"sessions\"]]")" == "False" ]]'
check "F4b. ... nor one launched in another feature's worktree" \
  '[[ "$(pj "$PJ" "\"$S_O\" in [s[\"session_id\"] for s in d[\"sessions\"]]")" == "False" ]]'
check "F5. a primary session pinned in sessions is claimed, as pinned" \
  '[[ "$(pj "$PJ" "[s[\"selected_by\"] for s in d[\"sessions\"] if s[\"session_id\"] == \"$S_P\"]")" == "['"'"'pinned'"'"']" ]]'

bound="$(wt_py "$WT/analysis/capture_planning.py" --self --last-branch-instant "$SLUG")"
check "F6. --last-branch-instant from the worktree's copy is the delegate's last instant + 1s (got $bound)" \
  '[[ "$bound" == "$EXPECTED_BOUND" ]]'

listed="$(wt_py "$WT/analysis/capture_planning.py" --self --list-sessions)"
check "F7. --list-sessions from the worktree's copy lists the primary's sessions and the worktree's" \
  'grep -q "$S_M" <<<"$listed" && grep -q "$S_W" <<<"$listed"'

echo
if (( fails > 0 )); then echo "capture-from-worktree: $fails assertion(s) FAILED"; exit 1; fi
echo "capture-from-worktree: all assertions passed"
