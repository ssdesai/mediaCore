#!/usr/bin/env bash
set -uo pipefail

# Self-test for the claim root the experiment harness's own tree needs. The harness runs
# every `claude` session of a feature (implementer, review, rework) with cwd
# `<primary>-<Branch>` (camelCase, `harness_worktree_path` in harness/lib.sh), a directory
# that is neither the primary, `<primary>/.worktrees/<slug>` nor the legacy `<primary>-<slug>`
# (kebab-case): before `claim_roots` took the manifest's `branches`, such a session landed
# in `launched_elsewhere` and the feature priced $0. Run by self/gate.sh, or by hand:
# bash self/tests/harness-claim-root.sh
#
# Same scaffolding as worktree-claims.sh: copies of `analysis/*.py` in a throwaway
# checkout under mktemp -d, transcripts under a redirected $HOME. No model, no network.
#
# Asserts, in order:
#   H1. a manifest whose `branches` holds `exportStoreDirectAfter2` claims a session whose
#       cwd is `<primary>-exportStoreDirectAfter2` and prices it (non-zero cost, cwd recorded);
#   H2. the same transcript shape launched in `<primary>-otherBranch` is not claimed, and
#       the warning names that directory;
#   H3. `claim_roots` with `branches` empty adds no sibling root, and with a branch adds
#       exactly `<primary>-<branch>`, the three roots it already had staying;
#   H4. a directory that merely starts with the harness tree's path
#       (`<primary>-exportStoreDirectAfter2Extra`) is not claimed — whole-component matching;
#   H5. `--last-branch-instant`, the second `claim_roots` call site, admits the harness tree
#       too: its bound is that session's last instant + 1s, not the unclaimable later ones'.
#   (H2c: the warning names the harness tree among the roots it lists.)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness.claim.root.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Physical path: roots.py resolves AGENT_TOOLING_DIR with Path.resolve() (capture-guard.sh).
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
for f in pricing.py litellm_prices.py rates_history.json roots.py transcript.py capture_planning.py routing.py; do
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

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"
project_dir() { echo "$FAKE_HOME/.claude/projects/$(printf '%s' "$1" | tr '/.' '--')"; }
capture() { HOME="$FAKE_HOME" python3 -B "$AT/analysis/capture_planning.py" --self "$@" 2>&1; }

SLUG="export-store-direct-after-2"
BRANCH="exportStoreDirectAfter2"
OTHER_BRANCH="otherBranch"
MODEL="claude-sonnet-5"
HARNESS_TREE="$AT-$BRANCH"
OTHER_TREE="$AT-$OTHER_BRANCH"
PREFIX_TREE="$AT-${BRANCH}Extra"

mkdir -p "$AT/self/features/$SLUG"
cat > "$AT/self/features/$SLUG/README.md" <<EOF
# $SLUG

\`\`\`json
{"slug": "$SLUG", "plans": [], "branches": ["$BRANCH"],
 "session_window": {"from": "2026-06-01T00:00:00Z", "to": "2026-06-02T00:00:00Z"}}
\`\`\`
EOF

S_HARNESS="hhhhhhhh-0000-0000-0000-000000000001"
S_OTHER="oooooooo-0000-0000-0000-000000000002"
S_PREFIX="pppppppp-0000-0000-0000-000000000003"
mkdir -p "$(project_dir "$HARNESS_TREE")" "$(project_dir "$OTHER_TREE")" "$(project_dir "$PREFIX_TREE")"
session_line "$S_HARNESS" "$HARNESS_TREE" "$BRANCH" "msg-h" "$MODEL" "2026-06-01T10:00:00.000Z" 100 1000 0 0 0 \
  > "$(project_dir "$HARNESS_TREE")/$S_HARNESS.jsonl"
session_line "$S_OTHER" "$OTHER_TREE" "$BRANCH" "msg-o" "$MODEL" "2026-06-01T11:00:00.000Z" 100 2000 0 0 0 \
  > "$(project_dir "$OTHER_TREE")/$S_OTHER.jsonl"
session_line "$S_PREFIX" "$PREFIX_TREE" "$BRANCH" "msg-p" "$MODEL" "2026-06-01T12:00:00.000Z" 100 3000 0 0 0 \
  > "$(project_dir "$PREFIX_TREE")/$S_PREFIX.jsonl"

echo "harness claim root"

out="$(capture "$SLUG")"; rc=$?
PJ="$AT/self/features/$SLUG/planning.json"
check "H1a. capture exits 0 (got $rc)" '[[ $rc -eq 0 && -f "$PJ" ]]'
check "H1b. the session launched in <primary>-<Branch> is selected by branch, cwd recorded" \
  '[[ "$(pj "$PJ" "[(s[\"session_id\"], s[\"selected_by\"], s[\"cwd\"]) for s in d[\"sessions\"]]")" == "[('"'"'$S_HARNESS'"'"', '"'"'branch'"'"', '"'"'$HARNESS_TREE'"'"')]" ]]'
check "H1c. ... and it is priced" \
  '[[ "$(pj "$PJ" "d[\"cost_usd\"][\"total\"] > 0")" == "True" ]]'
check "H2a. the session launched in <primary>-otherBranch is not claimed" \
  '[[ "$(pj "$PJ" "\"$S_OTHER\" in [s[\"session_id\"] for s in d[\"sessions\"]]")" == "False" ]]'
check "H2b. ... and the warning names that directory" 'grep -qF "$OTHER_TREE" <<<"$out"'
check "H2c. ... and names the harness tree among the claimable roots" "grep -qF \"['$HARNESS_TREE']\" <<<\"\$out\""
check "H4. a directory merely starting with the harness tree's path is not claimed" \
  '[[ "$(pj "$PJ" "\"$S_PREFIX\" in [s[\"session_id\"] for s in d[\"sessions\"]]")" == "False" ]]'
# The other call site: the evidence bound is the harness-tree session's last instant + 1s,
# not the later, unclaimable otherBranch / Extra sessions'.
bound="$(capture --last-branch-instant "$SLUG")"
check "H5. --last-branch-instant is bounded by the harness-tree session (got $bound)" \
  '[[ "$bound" == "2026-06-01T10:00:01Z" ]]'

roots_probe() {  # $1 python list literal of branches
  (cd "$AT/analysis" && python3 -B -c "
import sys
sys.path.insert(0, '.')
from capture_planning import claim_roots
roots, _ = claim_roots('$AT', '$SLUG', $1)
print('\n'.join(roots))")
}
base_roots="$(roots_probe '[]')"
with_roots="$(roots_probe "['$BRANCH']")"
check "H3a. empty branches adds no sibling root (three roots: primary, worktree, legacy)" \
  '[[ "$(wc -l <<<"$base_roots" | tr -d " ")" == "3" ]] && ! grep -qF "$HARNESS_TREE" <<<"$base_roots"'
check "H3b. one branch adds exactly <primary>-<branch>, the existing roots staying" \
  '[[ "$(wc -l <<<"$with_roots" | tr -d " ")" == "4" ]] && grep -qxF "$HARNESS_TREE" <<<"$with_roots" && grep -qxF "$AT" <<<"$with_roots" && grep -qxF "$AT-$SLUG" <<<"$with_roots"'

echo
if (( fails > 0 )); then echo "harness-claim-root: $fails assertion(s) FAILED"; exit 1; fi
echo "harness-claim-root: all assertions passed"
