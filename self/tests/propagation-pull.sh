#!/usr/bin/env bash
set -uo pipefail

# Self-test for a propagation pull as a feature (self/features/propagation-as-feature/,
# LIFECYCLE.md -> "Propagate"). Run by self/gate.sh, or by hand:
# bash self/tests/propagation-pull.sh
#
# A pull of agentTooling into a consuming repo is its own `--method hand` feature there,
# `pull-agenttooling-pr<N>`, so the session that performs it is routed and its cost lands
# in that feature's record. What that asks of update.sh, and what this asserts:
#
#   P1. on the consumer's `main` it refuses — a pull onto main is exactly the unrouted
#       spend the design removes — naming feature-start.sh, --method hand and the slug
#       convention, pulling nothing and moving no ref;
#   P2. on a detached HEAD it refuses the same way;
#   P3. on a branch with no feature manifest (plans/features/<branch>/README.md) it
#       refuses naming that path — a branch nobody started is not a feature;
#   P4. inside a linked worktree R/.worktrees/<slug>, on branch <slug> whose manifest is
#       committed, it pulls: the new upstream file lands in the worktree's prefix, the
#       squash commit's git-subtree-split is the upstream head and is printed on a
#       `split` line, the freshly pulled sync-plans.sh runs, the worktree stays on its
#       branch, main is untouched, the primary gains nothing, and no branch is created;
#   P5. the permission hook denies neither the pull nor update.sh run from the worktree
#       (a prompt is the ordinary outcome for a write; a deny would block the recipe);
#   P6. no `permissions.deny` prefix rule hooks/policy.py renders matches either command,
#       so a consumer's generated settings leave the pull alone.
#
# Builds a bare upstream holding the real update.sh and a stub sync-plans.sh, a consumer
# that `git subtree add`s it, and a linked worktree made by the fixture itself (the
# lifecycle scripts are feature-lifecycle.sh's to test). No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/propagation-pull.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

# The slug convention the recipe names, and the layout feature-start.sh writes
SLUG="pull-agenttooling-pr7"
PREFIX="agentTooling"
WORKTREES_DIR=".worktrees"
FEATURES_REL="plans/features"
MANIFEST_NAME="README.md"
UPSTREAM_BRANCH="main"
# What the stub sync-plans.sh prints, so P4 can see the pulled copy ran
SYNC_STUB_LINE="sync-plans stub ran"
# The command a propagation recipe would type, spelled the way README.md -> "Updating" does
SUBTREE_PULL_CMD="git subtree pull --prefix=$PREFIX https://github.com/ssdesai/agentTooling.git main --squash"
REFUSED_RC=1

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

gitq() { git -c user.email=test@example.invalid -c user.name="propagation test" "$@"; }

echo "propagation-pull"

# ── Fixture: an upstream agentTooling and a consumer that vendors it ─────────────
UPSTREAM="$TMP/upstream.git"
WORK="$TMP/work"
CONSUMER="$TMP/consumer"
WT="$CONSUMER/$WORKTREES_DIR/$SLUG"

git init -q --bare "$UPSTREAM"
git -C "$UPSTREAM" symbolic-ref HEAD "refs/heads/$UPSTREAM_BRANCH"
git clone -q "$UPSTREAM" "$WORK" 2>/dev/null
git -C "$WORK" symbolic-ref HEAD "refs/heads/$UPSTREAM_BRANCH"
cp "$AT/update.sh" "$WORK/update.sh" 2>/dev/null || true
printf '#!/usr/bin/env bash\necho "%s"\nexit 0\n' "$SYNC_STUB_LINE" > "$WORK/sync-plans.sh"
chmod +x "$WORK/update.sh" "$WORK/sync-plans.sh" 2>/dev/null || true
gitq -C "$WORK" add -A && gitq -C "$WORK" commit -q -m "upstream: update.sh and a stub sync"
git -C "$WORK" push -q origin "$UPSTREAM_BRANCH" 2>/dev/null

mkdir -p "$CONSUMER"
git -C "$CONSUMER" init -q
git -C "$CONSUMER" symbolic-ref HEAD refs/heads/main
echo "consumer root" > "$CONSUMER/README.md"
gitq -C "$CONSUMER" add -A && gitq -C "$CONSUMER" commit -q -m "init"
gitq -C "$CONSUMER" subtree add --prefix="$PREFIX" "$UPSTREAM" "$UPSTREAM_BRANCH" --squash >/dev/null 2>&1
# feature-start.sh keeps .worktrees/ out of git the same way
mkdir -p "$CONSUMER/.git/info"
echo "/$WORKTREES_DIR/" >> "$CONSUMER/.git/info/exclude"

# The feature's branch and worktree, with its manifest committed, as a start leaves them
gitq -C "$CONSUMER" worktree add -q -b "$SLUG" "$WT" main 2>/dev/null
mkdir -p "$WT/$FEATURES_REL/$SLUG"
printf '# Pull agentTooling PR 7\n\n```json\n{"slug": "%s", "method": "hand", "plans": ["01-review-opus"], "branches": ["%s"]}\n```\n' \
  "$SLUG" "$SLUG" > "$WT/$FEATURES_REL/$SLUG/$MANIFEST_NAME"
gitq -C "$WT" add -A && gitq -C "$WT" commit -q -m "$SLUG: start"

# The upstream moves on: this is what a pull must bring across
echo "marker" > "$WORK/MARKER.txt"
gitq -C "$WORK" add -A && gitq -C "$WORK" commit -q -m "add MARKER.txt"
git -C "$WORK" push -q origin "$UPSTREAM_BRANCH" 2>/dev/null
UPSTREAM_HEAD="$(git -C "$WORK" rev-parse HEAD)"

MAIN_BEFORE="$(git -C "$CONSUMER" rev-parse main)"
BRANCHES_BEFORE="$(git -C "$CONSUMER" for-each-ref --format='%(refname)' refs/heads | sort)"

# ── P1. on main: refused ─────────────────────────────────────────────────────────
out="$(cd "$TMP" && "$CONSUMER/$PREFIX/update.sh" --remote "$UPSTREAM" 2>&1)"; rc=$?
check "P1a. update.sh on main exits $REFUSED_RC (got $rc)" '[[ $rc -eq $REFUSED_RC ]]'
check "P1b. the refusal names feature-start.sh, --method hand and the slug convention" \
  'grep -qF "feature-start.sh" <<<"$out" && grep -qF -- "--method hand" <<<"$out" && grep -qF "pull-agenttooling-pr" <<<"$out"'
check "P1c. nothing pulled into the primary" '[[ ! -e "$CONSUMER/$PREFIX/MARKER.txt" ]]'
check "P1d. main has not moved" '[[ "$(git -C "$CONSUMER" rev-parse main)" == "$MAIN_BEFORE" ]]'

# ── P2. a detached HEAD: refused ─────────────────────────────────────────────────
git -C "$CONSUMER" checkout -q --detach main 2>/dev/null
out="$(cd "$TMP" && "$CONSUMER/$PREFIX/update.sh" --remote "$UPSTREAM" 2>&1)"; rc=$?
check "P2a. update.sh on a detached HEAD exits $REFUSED_RC (got $rc)" '[[ $rc -eq $REFUSED_RC ]]'
check "P2b. the refusal says detached and names feature-start.sh" \
  'grep -qF "detached" <<<"$out" && grep -qF "feature-start.sh" <<<"$out"'
check "P2c. nothing pulled" '[[ ! -e "$CONSUMER/$PREFIX/MARKER.txt" ]]'
git -C "$CONSUMER" checkout -q main 2>/dev/null

# ── P3. a branch nobody started: refused ─────────────────────────────────────────
UNSTARTED="scratch-branch"
git -C "$CONSUMER" checkout -q -b "$UNSTARTED" 2>/dev/null
out="$(cd "$TMP" && "$CONSUMER/$PREFIX/update.sh" --remote "$UPSTREAM" 2>&1)"; rc=$?
check "P3a. update.sh on a branch with no feature manifest exits $REFUSED_RC (got $rc)" '[[ $rc -eq $REFUSED_RC ]]'
check "P3b. the refusal names the manifest path it looked for" \
  'grep -qF "$FEATURES_REL/$UNSTARTED/$MANIFEST_NAME" <<<"$out"'
check "P3c. nothing pulled" '[[ ! -e "$CONSUMER/$PREFIX/MARKER.txt" ]]'
git -C "$CONSUMER" checkout -q main 2>/dev/null
git -C "$CONSUMER" branch -q -D "$UNSTARTED" 2>/dev/null

# ── P4. inside the feature's worktree, on its branch: pulled ─────────────────────
WT_BEFORE="$(git -C "$WT" rev-parse HEAD)"
out="$(cd "$TMP" && "$WT/$PREFIX/update.sh" --remote "$UPSTREAM" 2>&1)"; rc=$?
check "P4a. update.sh in the feature worktree exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "P4b. MARKER.txt pulled into the worktree's prefix" '[[ -e "$WT/$PREFIX/MARKER.txt" ]]'
check "P4c. the worktree is still on $SLUG, and its branch moved" \
  '[[ "$(git -C "$WT" branch --show-current)" == "$SLUG" && "$(git -C "$WT" rev-parse HEAD)" != "$WT_BEFORE" ]]'
check "P4d. main has not moved, and the primary gained nothing" \
  '[[ "$(git -C "$CONSUMER" rev-parse main)" == "$MAIN_BEFORE" && ! -e "$CONSUMER/$PREFIX/MARKER.txt" ]]'
check "P4e. no branch was created" \
  '[[ "$(git -C "$CONSUMER" for-each-ref --format="%(refname)" refs/heads | sort)" == "$BRANCHES_BEFORE" ]]'
split="$(git -C "$WT" log -n 1 --format=%B --grep="^git-subtree-dir: $PREFIX\$" HEAD | sed -n 's/^git-subtree-split: *//p' | head -n 1)"
check "P4f. the squash commit on the branch records the upstream head as its split" \
  '[[ "$split" == "$UPSTREAM_HEAD" ]]'
check "P4g. the output prints that sha on a split line" \
  'grep -qE "^  split +$UPSTREAM_HEAD\$" <<<"$out"'
check "P4h. the freshly pulled sync-plans.sh ran" 'grep -qF "$SYNC_STUB_LINE" <<<"$out"'

# ── P5. the hook: neither command is denied ──────────────────────────────────────
# decision <cwd> <command> — the hook's permissionDecision, or "prompt" when it prints
# nothing, or "ERR".
decision() {
  python3 - "$AT/hooks/allow-repo-commands.sh" "$CONSUMER" "$1" "$2" <<'PY'
import json, os, subprocess, sys
hook, root, cwd, cmd = sys.argv[1:5]
env = dict(os.environ, CLAUDE_PROJECT_DIR=root)
payload = {"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": cmd}}
p = subprocess.run([hook], input=json.dumps(payload), capture_output=True, text=True, env=env)
if p.returncode != 0:
    print("ERR")
elif not p.stdout.strip():
    print("prompt")
else:
    try:
        print(json.loads(p.stdout)["hookSpecificOutput"]["permissionDecision"])
    except (ValueError, KeyError, TypeError):
        print("ERR")
PY
}
d="$(decision "$WT" "$SUBTREE_PULL_CMD")"
check "P5a. the hook does not deny a git subtree pull in the worktree (got $d)" '[[ "$d" != "deny" && "$d" != "ERR" ]]'
d="$(decision "$CONSUMER" "$WT/$PREFIX/update.sh")"
check "P5b. the hook does not deny the worktree's update.sh by absolute path (got $d)" '[[ "$d" != "deny" && "$d" != "ERR" ]]'
d="$(decision "$WT" "./$PREFIX/update.sh")"
check "P5c. the hook does not deny ./agentTooling/update.sh from the worktree (got $d)" '[[ "$d" != "deny" && "$d" != "ERR" ]]'

# ── P6. the generated deny rules: none matches ───────────────────────────────────
matched="$(python3 - "$AT/hooks" "$SUBTREE_PULL_CMD" "./$PREFIX/update.sh" "git merge --squash x" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import policy
prefix_open, prefix_close = policy.BASH_RULE_TEMPLATE.split("%s")
for rule in policy.bash_deny_rules():
    prefix = rule[len(prefix_open):-len(prefix_close)]
    for cmd in sys.argv[2:]:
        if cmd == prefix or cmd.startswith(prefix + " "):
            print(rule, "matches", cmd)
PY
)"
check "P6a. no rendered deny rule matches the subtree pull, update.sh or a git merge (got '$matched')" '[[ -z "$matched" ]]'

echo
if (( fails > 0 )); then
  echo "propagation-pull: $fails failed"
  exit 1
fi
echo "propagation-pull: all passed"
