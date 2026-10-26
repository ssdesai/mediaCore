#!/usr/bin/env bash
set -uo pipefail

# Self-test: update.sh on a cloud-started feature (self/features/cloud-pull-fixes/, defect
# A). Run by self/gate.sh, or by hand: bash self/tests/update-cloud-branch.sh
#
# In a Claude Code cloud container the feature's branch is the session's assigned branch
# (`claude/<name>`), not the slug, so a pull feature's manifest sits at
# plans/features/pull-agenttooling-pr<N>/README.md with that branch as its fence's
# `branches[0]` — and update.sh, which only looked for plans/features/<branch>/README.md,
# refused every one of them. What this asserts:
#
#   U1. on a branch no manifest names (and no plans/features/<branch>/README.md) it still
#       refuses, exit 1, naming the path it looked for and pulling nothing;
#   U2. on a branch TWO tracked manifests name as branches[0] it refuses, exit 1, naming
#       both slugs, pulling nothing;
#   U3. a manifest that names the branch but is not tracked is not a started feature —
#       the refusal is the not-started one, not the dirty-tree one;
#   U4. on main it refuses even when a tracked manifest names main as its branch;
#   U5. on a cloud branch exactly one tracked manifest names, it pulls: exit 0, the
#       upstream file lands, the `pull` line names the slug, the `split` line is the
#       upstream head, the stub sync runs, the branch is unchanged and no branch is made.
#
# Builds a bare upstream holding the real update.sh and plan-runner-roots.sh beside a stub
# sync-plans.sh, and a consumer that `git subtree add`s it. No worktree: the cloud
# container is the checkout. No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/update-cloud-branch.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

# The layout and names a cloud start writes
SLUG="pull-agenttooling-pr9"
CLOUD_BRANCH="claude/stoic-ptolemy-l0sjze"
DUP_BRANCH="claude/two-features"
DUP_SLUG_A="pull-agenttooling-pr10"
DUP_SLUG_B="pull-agenttooling-pr11"
NONE_BRANCH="claude/nobody-started"
UNTRACKED_BRANCH="claude/untracked-manifest"
UNTRACKED_SLUG="pull-agenttooling-pr12"
MAIN_SLUG="odd-main-feature"
PREFIX="agentTooling"
FEATURES_REL="plans/features"
MANIFEST_NAME="README.md"
UPSTREAM_BRANCH="main"
# What the stub sync-plans.sh prints, so U5 can see the pulled copy ran
SYNC_STUB_LINE="sync-plans stub ran"
REFUSED_RC=1

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

gitq() { git -c user.email=test@example.invalid -c user.name="update cloud test" "$@"; }

# manifest <checkout> <slug> <branch> — a started feature's manifest, as a start writes it
manifest() {
  mkdir -p "$1/$FEATURES_REL/$2"
  printf '# %s\n\n```json\n{"slug": "%s", "method": "hand", "plans": ["01-review-opus"], "branches": ["%s"]}\n```\n' \
    "$2" "$2" "$3" > "$1/$FEATURES_REL/$2/$MANIFEST_NAME"
}

run_update() { (cd "$TMP" && "$CONSUMER/$PREFIX/update.sh" --remote "$UPSTREAM" 2>&1); }

echo "update-cloud-branch"

# ── Fixture ──────────────────────────────────────────────────────────────────
UPSTREAM="$TMP/upstream.git"
WORK="$TMP/work"
CONSUMER="$TMP/consumer"

git init -q --bare "$UPSTREAM"
git -C "$UPSTREAM" symbolic-ref HEAD "refs/heads/$UPSTREAM_BRANCH"
git clone -q "$UPSTREAM" "$WORK" 2>/dev/null
git -C "$WORK" symbolic-ref HEAD "refs/heads/$UPSTREAM_BRANCH"
cp "$AT/update.sh" "$WORK/update.sh" 2>/dev/null || true
cp "$AT/plan-runner-roots.sh" "$WORK/plan-runner-roots.sh" 2>/dev/null || true
printf '#!/usr/bin/env bash\necho "%s"\nexit 0\n' "$SYNC_STUB_LINE" > "$WORK/sync-plans.sh"
chmod +x "$WORK/update.sh" "$WORK/sync-plans.sh" 2>/dev/null || true
gitq -C "$WORK" add -A && gitq -C "$WORK" commit -q -m "upstream: update.sh, roots and a stub sync"
git -C "$WORK" push -q origin "$UPSTREAM_BRANCH" 2>/dev/null

mkdir -p "$CONSUMER"
git -C "$CONSUMER" init -q
git -C "$CONSUMER" symbolic-ref HEAD refs/heads/main
echo "consumer root" > "$CONSUMER/README.md"
gitq -C "$CONSUMER" add -A && gitq -C "$CONSUMER" commit -q -m "init"
gitq -C "$CONSUMER" subtree add --prefix="$PREFIX" "$UPSTREAM" "$UPSTREAM_BRANCH" --squash >/dev/null 2>&1
# A tracked manifest on main that names main itself: U4 must still refuse
manifest "$CONSUMER" "$MAIN_SLUG" "main"
gitq -C "$CONSUMER" add -A && gitq -C "$CONSUMER" commit -q -m "$MAIN_SLUG: start"

# The upstream moves on: this is what a pull must bring across
echo "marker" > "$WORK/MARKER.txt"
gitq -C "$WORK" add -A && gitq -C "$WORK" commit -q -m "add MARKER.txt"
git -C "$WORK" push -q origin "$UPSTREAM_BRANCH" 2>/dev/null
UPSTREAM_HEAD="$(git -C "$WORK" rev-parse HEAD)"

# ── U1. a branch nobody started ──────────────────────────────────────────────
git -C "$CONSUMER" checkout -q -b "$NONE_BRANCH" main 2>/dev/null
manifest "$CONSUMER" "some-other-feature" "claude/some-other-branch"
gitq -C "$CONSUMER" add -A && gitq -C "$CONSUMER" commit -q -m "some-other-feature: start"
out="$(run_update)"; rc=$?
check "U1a. no manifest names $NONE_BRANCH: exit $REFUSED_RC (got $rc)" '[[ $rc -eq $REFUSED_RC ]]'
check "U1b. the refusal names the path it looked for" \
  'grep -qF "$FEATURES_REL/$NONE_BRANCH/$MANIFEST_NAME" <<<"$out"'
check "U1c. nothing pulled" '[[ ! -e "$CONSUMER/$PREFIX/MARKER.txt" ]]'

# ── U2. two tracked manifests name the branch ────────────────────────────────
git -C "$CONSUMER" checkout -q -b "$DUP_BRANCH" main 2>/dev/null
manifest "$CONSUMER" "$DUP_SLUG_A" "$DUP_BRANCH"
manifest "$CONSUMER" "$DUP_SLUG_B" "$DUP_BRANCH"
gitq -C "$CONSUMER" add -A && gitq -C "$CONSUMER" commit -q -m "two starts on one branch"
out="$(run_update)"; rc=$?
check "U2a. two features on $DUP_BRANCH: exit $REFUSED_RC (got $rc)" '[[ $rc -eq $REFUSED_RC ]]'
check "U2b. the refusal names both slugs" \
  'grep -qF "$DUP_SLUG_A" <<<"$out" && grep -qF "$DUP_SLUG_B" <<<"$out"'
check "U2c. nothing pulled" '[[ ! -e "$CONSUMER/$PREFIX/MARKER.txt" ]]'

# ── U3. an untracked manifest is not a started feature ───────────────────────
git -C "$CONSUMER" checkout -q -b "$UNTRACKED_BRANCH" main 2>/dev/null
manifest "$CONSUMER" "$UNTRACKED_SLUG" "$UNTRACKED_BRANCH"
out="$(run_update)"; rc=$?
check "U3a. an untracked manifest naming $UNTRACKED_BRANCH: exit $REFUSED_RC (got $rc)" '[[ $rc -eq $REFUSED_RC ]]'
check "U3b. the refusal is the not-started one, not the dirty-tree one" \
  'grep -qF "is not a started feature" <<<"$out" && ! grep -qF "uncommitted changes" <<<"$out"'
check "U3c. nothing pulled" '[[ ! -e "$CONSUMER/$PREFIX/MARKER.txt" ]]'
rm -rf "$CONSUMER/$FEATURES_REL/$UNTRACKED_SLUG"

# ── U4. main is refused, whatever names it ───────────────────────────────────
git -C "$CONSUMER" checkout -q main 2>/dev/null
MAIN_BEFORE="$(git -C "$CONSUMER" rev-parse main)"
out="$(run_update)"; rc=$?
check "U4a. on main with a manifest naming main: exit $REFUSED_RC (got $rc)" '[[ $rc -eq $REFUSED_RC ]]'
check "U4b. the refusal names feature-start.sh" 'grep -qF "feature-start.sh" <<<"$out"'
check "U4c. main has not moved and nothing was pulled" \
  '[[ "$(git -C "$CONSUMER" rev-parse main)" == "$MAIN_BEFORE" && ! -e "$CONSUMER/$PREFIX/MARKER.txt" ]]'

# ── U5. a cloud branch exactly one tracked manifest names: pulled ────────────
git -C "$CONSUMER" checkout -q -b "$CLOUD_BRANCH" main 2>/dev/null
manifest "$CONSUMER" "$SLUG" "$CLOUD_BRANCH"
gitq -C "$CONSUMER" add -A && gitq -C "$CONSUMER" commit -q -m "$SLUG: start"
BRANCHES_BEFORE="$(git -C "$CONSUMER" for-each-ref --format='%(refname)' refs/heads | sort)"
HEAD_BEFORE="$(git -C "$CONSUMER" rev-parse HEAD)"
out="$(run_update)"; rc=$?
check "U5a. on $CLOUD_BRANCH, started as $SLUG: exit 0 (got $rc: $out)" '[[ $rc -eq 0 ]]'
check "U5b. MARKER.txt pulled" '[[ -e "$CONSUMER/$PREFIX/MARKER.txt" ]]'
check "U5c. the pull line names the branch and the slug" \
  'grep -E "^  pull " <<<"$out" | grep -qF "$CLOUD_BRANCH" && grep -E "^  pull " <<<"$out" | grep -qF "$SLUG"'
check "U5d. the split line is the upstream head" 'grep -qE "^  split +$UPSTREAM_HEAD\$" <<<"$out"'
check "U5e. the freshly pulled sync-plans.sh ran" 'grep -qF "$SYNC_STUB_LINE" <<<"$out"'
check "U5f. still on $CLOUD_BRANCH, which moved; main unmoved" \
  '[[ "$(git -C "$CONSUMER" branch --show-current)" == "$CLOUD_BRANCH" && "$(git -C "$CONSUMER" rev-parse HEAD)" != "$HEAD_BEFORE" && "$(git -C "$CONSUMER" rev-parse main)" == "$MAIN_BEFORE" ]]'
check "U5g. no branch was created" \
  '[[ "$(git -C "$CONSUMER" for-each-ref --format="%(refname)" refs/heads | sort)" == "$BRANCHES_BEFORE" ]]'

echo
if (( fails > 0 )); then
  echo "update-cloud-branch: $fails failed"
  exit 1
fi
echo "update-cloud-branch: all passed"
