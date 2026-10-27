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
# And the cloud remedy for a fetch the session's git proxy will not serve
# (self/features/propagate-agenttooling-access/), from the same branch:
#
#   U6. the cloud profile, a fetch failing as an unattached repo does: exit 1, git's own
#       error shown, one `remedy` line naming the owner/repo to attach and `add_repo`;
#   U7. the same failure under the local profile: exit 1, no `remedy` line;
#   U8. the cloud profile, a failure that is not about authentication: no `remedy` line.
#
# U5 also runs with stdout and stderr apart and a TMPDIR of its own: its `pull`, `split`
# and sync lines are on stdout and git's fetch line on stderr only (U5h — the tee that
# keeps the pull's stderr must not swap the two), and update.sh's temporary stderr copy is
# gone afterwards (U5i); U6 checks the same on the failure path (U6e).
#
# Builds a bare upstream holding the real update.sh, plan-runner-roots.sh, env-profile.sh
# and hooks/env_profile.py beside a stub sync-plans.sh, and a consumer that
# `git subtree add`s it. No worktree: the cloud container is the checkout. The failing
# fetch is a remote helper on PATH (`git-remote-<scheme>`) that prints the line a cloud
# proxy answers with and exits non-zero. No model, no network.

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

# U6–U8: a fetch that fails as an unattached repo's does in a cloud container
AUTH_SCHEME="testauth"
AUTH_REPO="ssdesai/agentTooling"
AUTH_REMOTE="$AUTH_SCHEME://github.com/$AUTH_REPO.git"
AUTH_ERROR="fatal: could not read Username for 'https://github.com': terminal prompts disabled"
HELPER_FAIL_RC=128
REMEDY_PREFIX="  remedy  "
ATTACH_TOOL="add_repo"
# update.sh's temporary copy of the pull's stderr (U5i, U6e), and the line git fetch
# writes to stderr on a successful pull (U5h)
ERRLOG_GLOB="update-pull.*"
FETCH_LINE="-> FETCH_HEAD"

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
cp "$AT/env-profile.sh" "$WORK/env-profile.sh" 2>/dev/null || true
mkdir -p "$WORK/hooks"
cp "$AT/hooks/env_profile.py" "$WORK/hooks/env_profile.py" 2>/dev/null || true
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
# Run with stdout and stderr apart (U5h) and a TMPDIR of its own (U5i)
U5_TMPDIR="$TMP/u5-tmpdir"
mkdir -p "$U5_TMPDIR"
(cd "$TMP" && TMPDIR="$U5_TMPDIR" "$CONSUMER/$PREFIX/update.sh" --remote "$UPSTREAM" \
  > "$TMP/u5.stdout" 2> "$TMP/u5.stderr"); rc=$?
out="$(cat "$TMP/u5.stdout" "$TMP/u5.stderr")"
u5_stdout="$(cat "$TMP/u5.stdout")"
u5_stderr="$(cat "$TMP/u5.stderr")"
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
check "U5h. pull, split and sync lines on stdout; git's fetch line on stderr only" \
  'grep -qE "^  pull " <<<"$u5_stdout" && grep -qE "^  split " <<<"$u5_stdout" && grep -qF "$SYNC_STUB_LINE" <<<"$u5_stdout" && grep -qF -e "$FETCH_LINE" <<<"$u5_stderr" && ! grep -qF -e "$FETCH_LINE" <<<"$u5_stdout"'
check "U5i. no $ERRLOG_GLOB left in TMPDIR on the success path" \
  '[[ -z "$(find "$U5_TMPDIR" -name "$ERRLOG_GLOB")" ]]'

# ── U6–U8. a fetch the cloud proxy will not serve ────────────────────────────
HELPER_DIR="$TMP/bin"
mkdir -p "$HELPER_DIR"
printf '#!/usr/bin/env bash\necho "%s" >&2\nexit %s\n' "$AUTH_ERROR" "$HELPER_FAIL_RC" \
  > "$HELPER_DIR/git-remote-$AUTH_SCHEME"
chmod +x "$HELPER_DIR/git-remote-$AUTH_SCHEME"
# run_failing <profile> <remote> — update.sh on the cloud branch, the helper on PATH
run_failing() {
  (cd "$TMP" && PATH="$HELPER_DIR:$PATH" AGENTTOOLING_PROFILE="$1" \
    "$CONSUMER/$PREFIX/update.sh" --remote "$2" 2>&1)
}
HEAD_BEFORE="$(git -C "$CONSUMER" rev-parse HEAD)"

U6_TMPDIR="$TMP/u6-tmpdir"
mkdir -p "$U6_TMPDIR"
out="$(TMPDIR="$U6_TMPDIR" run_failing cloud "$AUTH_REMOTE")"; rc=$?
check "U6a. cloud, unattached fetch: exit $REFUSED_RC (got $rc)" '[[ $rc -eq $REFUSED_RC ]]'
check "U6b. git's own error is shown" 'grep -qF "$AUTH_ERROR" <<<"$out"'
check "U6c. one remedy line, naming $AUTH_REPO and $ATTACH_TOOL" \
  '[[ "$(grep -c "^$REMEDY_PREFIX" <<<"$out")" -eq 1 ]] && grep "^$REMEDY_PREFIX" <<<"$out" | grep -qF "attach $AUTH_REPO with the $ATTACH_TOOL tool"'
check "U6d. nothing pulled: HEAD unmoved" '[[ "$(git -C "$CONSUMER" rev-parse HEAD)" == "$HEAD_BEFORE" ]]'
check "U6e. no $ERRLOG_GLOB left in TMPDIR on the failure path" \
  '[[ -z "$(find "$U6_TMPDIR" -name "$ERRLOG_GLOB")" ]]'

out="$(run_failing local "$AUTH_REMOTE")"; rc=$?
check "U7a. local, the same failure: exit $REFUSED_RC (got $rc)" '[[ $rc -eq $REFUSED_RC ]]'
check "U7b. no remedy line under local" '! grep -q "^$REMEDY_PREFIX" <<<"$out"'

out="$(run_failing cloud "$TMP/no-such-upstream.git")"; rc=$?
check "U8a. cloud, a missing remote: exit $REFUSED_RC (got $rc)" '[[ $rc -eq $REFUSED_RC ]]'
check "U8b. no remedy line for a failure that is not authentication" '! grep -q "^$REMEDY_PREFIX" <<<"$out"'

echo
if (( fails > 0 )); then
  echo "update-cloud-branch: $fails failed"
  exit 1
fi
echo "update-cloud-branch: all passed"
