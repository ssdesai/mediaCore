#!/usr/bin/env bash
set -uo pipefail

# Self-test: a repo-owned template cannot change without its version stamp moving
# (self/features/cloud-pull-fixes/, defect B). Run by self/gate.sh, or by hand:
# bash self/tests/template-version-bump.sh
#
# PR 85 reworded templates/plans/cloud-setup.sh's header comment — it is now run by
# agentTooling/session-start.sh, not wired directly as the SessionStart hook — and left
# `# template-version: 1`. template-versions.sh hashed the file with its comments
# stripped, so the edit passed, and sync-plans.sh --check reported every consumer's stale
# copy `in-sync` forever. What this asserts:
#
#   B1. the checked-in tree passes template-versions.sh;
#   B2. cloud-setup.sh is at template-version 3 (hand-start-friction's --wait contract),
#       recorded as 3 in TEMPLATE_VERSIONS, and
#       its header names session-start.sh as its runner;
#   B3. in a copy of templates/plans, a COMMENT-ONLY edit to a template fails
#       template-versions.sh, naming the file — the case PR 85 slipped through;
#   B4. so does a body edit;
#   B5. bumping the version line without re-recording the hash still fails;
#   B6. bumping it AND re-recording the hash with the command TEMPLATE_VERSIONS' own header
#       documents passes;
#   B7. a consumer whose seeded cloud-setup.sh still says version 1 is reported DRIFT
#       `template-version 1 < 3` by sync-plans.sh --check, and setting its line to 3 — the
#       whole hand-merge for a consumer that already carries the new comment — clears it.
#
#   B8-B14 tie the hash to the version, against a fixture repo standing in for origin/main
#   (the checker's TEMPLATE_BASE_REPO / TEMPLATE_BASE_REF):
#   B8.  an unchanged tree passes;
#   B9.  a hash re-recorded at an unchanged version FAILS, naming the file — the finding;
#   B10. a bump with a new hash passes;
#   B11. a version below the base's fails;
#   B12. a template the base lacks is new and passes;
#   B13. an unavailable base fails, naming `git fetch origin main`;
#   B14. all of it works through a depth-1 clone of the base;
#   B15. the comparison is at the branch's FORK POINT, not the base tip: main bumps a template
#        after the branch forks and the branch touched none: passes (a); the branch edits one
#        without a bump while main moved: fails (b); lowering below the fork point fails
#        without "merge" advice (c); with no shared history it falls back to the tip and says
#        to merge (d).
#
# Reads the real tree (B1, B2, against the real origin/main — the branch itself passes)
# and copies of it (B3-B15). Needs only a base tip (the fork point when the history is
# there, the tip otherwise), so it runs in a shallow clone as it does locally. No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/template-version-bump.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

CHECKER="$AT/self/tests/template-versions.sh"
REAL_TEMPLATES="$AT/templates/plans"
TABLE_NAME="TEMPLATE_VERSIONS"
SUBJECT="cloud-setup.sh"
SUBJECT_VERSION="3"
SUBJECT_RUNNER="session-start.sh"
VERSION_LINE_PREFIX="# template-version:"
# The edits B3 and B4 make to the copy
COMMENT_EDIT="# a reworded comment nobody bumped for"
BODY_EDIT='echo "a new step"'

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# fresh_copy <dir> — a copy of templates/plans to edit
fresh_copy() { rm -rf "$1"; cp -r "$REAL_TEMPLATES" "$1"; }

# rerecord <dir> <file> — re-record <file>'s row the way TEMPLATE_VERSIONS' header says:
# the hash command is read from that header, not restated here, so the documented
# recipe is what is tested.
rerecord() {
  local dir="$1" file="$2" cmd version hash
  cmd="$(sed -n 's/^#[[:space:]]*\(.*shasum -a 256\)[[:space:]]*$/\1/p' "$dir/$TABLE_NAME" | head -n 1)"
  cmd="${cmd//<file>/$dir/$file}"
  version="$(sed -n "s/^$VERSION_LINE_PREFIX[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$dir/$file" | head -n 1)"
  hash="$(bash -c "$cmd" | awk '{print $1}')"
  awk -v f="$file" -v v="$version" -v h="$hash" '$1 == f { print f, v, h; next } { print }' \
    "$dir/$TABLE_NAME" > "$dir/$TABLE_NAME.new" && mv "$dir/$TABLE_NAME.new" "$dir/$TABLE_NAME"
}

# set_version <file> <N>
set_version() {
  sed "s/^$VERSION_LINE_PREFIX.*/$VERSION_LINE_PREFIX $2/" "$1" > "$1.new" && mv "$1.new" "$1"
}

echo "template-version-bump"

# ── B1. the real tree ────────────────────────────────────────────────────────
out="$(bash "$CHECKER" 2>&1)"; rc=$?
check "B1. the checked-in templates pass template-versions.sh (rc $rc)" '[[ $rc -eq 0 ]]'

# ── B2. cloud-setup.sh at 3 ──────────────────────────────────────────────────
check "B2a. templates/plans/$SUBJECT carries '$VERSION_LINE_PREFIX $SUBJECT_VERSION'" \
  'grep -qxF "$VERSION_LINE_PREFIX $SUBJECT_VERSION" "$REAL_TEMPLATES/$SUBJECT"'
check "B2b. $TABLE_NAME records $SUBJECT at $SUBJECT_VERSION" \
  '[[ "$(awk -v f="$SUBJECT" "\$1 == f {print \$2}" "$REAL_TEMPLATES/$TABLE_NAME")" == "$SUBJECT_VERSION" ]]'
check "B2c. its header names $SUBJECT_RUNNER as what runs it" \
  'grep -qF "Run by agentTooling/$SUBJECT_RUNNER" "$REAL_TEMPLATES/$SUBJECT"'

# ── B3. a comment-only edit, unbumped ────────────────────────────────────────
COPY="$TMP/templates"
fresh_copy "$COPY"
echo "$COMMENT_EDIT" >> "$COPY/$SUBJECT"
out="$(bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B3a. a comment-only edit without a bump fails (rc $rc)" '[[ $rc -ne 0 ]]'
check "B3b. ... naming the file" 'grep -F "FAIL" <<<"$out" | grep -qF "$SUBJECT"'

# ── B4. a body edit, unbumped ────────────────────────────────────────────────
fresh_copy "$COPY"
echo "$BODY_EDIT" >> "$COPY/$SUBJECT"
out="$(bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B4. a body edit without a bump fails (rc $rc)" '[[ $rc -ne 0 ]] && grep -F "FAIL" <<<"$out" | grep -qF "$SUBJECT"'

# ── B5. bumped, hash not re-recorded ─────────────────────────────────────────
fresh_copy "$COPY"
echo "$COMMENT_EDIT" >> "$COPY/$SUBJECT"
set_version "$COPY/$SUBJECT" "$((SUBJECT_VERSION + 1))"
out="$(bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B5. a bump without re-recording the table fails (rc $rc)" '[[ $rc -ne 0 ]]'

# ── B6. bumped and re-recorded ───────────────────────────────────────────────
rerecord "$COPY" "$SUBJECT"
out="$(bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B6. a bump with the hash re-recorded by the documented command passes (rc $rc: $out)" '[[ $rc -eq 0 ]]'

# ── B7. a consumer's stale copy is DRIFT ─────────────────────────────────────
CONSUMER="$TMP/consumer"
mkdir -p "$CONSUMER/agentTooling"
cp "$AT/sync-plans.sh" "$CONSUMER/agentTooling/sync-plans.sh"
cp -r "$AT/templates" "$CONSUMER/agentTooling/templates"
cp -r "$AT/hooks" "$CONSUMER/agentTooling/hooks"
cp "$AT/env-profile.sh" "$CONSUMER/agentTooling/env-profile.sh"
git -C "$CONSUMER" init -q
git -C "$CONSUMER" symbolic-ref HEAD refs/heads/main
unset GATE_RESUME
bash "$CONSUMER/agentTooling/sync-plans.sh" >/dev/null 2>&1
set_version "$CONSUMER/plans/$SUBJECT" 1
out="$(bash "$CONSUMER/agentTooling/sync-plans.sh" --check 2>&1)"
check "B7a. a seeded $SUBJECT at 1 is DRIFT 1 < $SUBJECT_VERSION" \
  'grep -qF "DRIFT      plans/$SUBJECT (template-version 1 < $SUBJECT_VERSION;" <<<"$out"'
set_version "$CONSUMER/plans/$SUBJECT" "$SUBJECT_VERSION"
out="$(bash "$CONSUMER/agentTooling/sync-plans.sh" --check 2>&1)"
check "B7b. setting its line to $SUBJECT_VERSION makes it in-sync" \
  'grep -qF "in-sync    plans/$SUBJECT (template-version $SUBJECT_VERSION)" <<<"$out"'

# ── B8-B14. the hash is tied to the version, against a base branch ──────────
# A fixture repo whose only commit holds the real templates stands in for origin/main. Its
# branch is not `main`, so the checker's local-main fallback finds nothing there (B13).
BASE_REPO="$TMP/base"
BASE_BRANCH="fixture-base"
mkdir -p "$BASE_REPO/templates"
cp -r "$REAL_TEMPLATES" "$BASE_REPO/templates/plans"
rm -f "$BASE_REPO/templates/plans/$TABLE_NAME"   # the base's table is never trusted
git -C "$BASE_REPO" init -q
git -C "$BASE_REPO" symbolic-ref HEAD "refs/heads/$BASE_BRANCH"
git -C "$BASE_REPO" add -A
git -C "$BASE_REPO" -c user.name=t -c user.email=t@t commit -q -m base
export TEMPLATE_BASE_REPO="$BASE_REPO" TEMPLATE_BASE_REF="$BASE_BRANCH"

fresh_copy "$COPY"
out="$(bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B8. an unchanged tree passes against the base (rc $rc)" '[[ $rc -eq 0 ]]'

# the finding: edit, re-record the hash, leave the version
fresh_copy "$COPY"
echo "$COMMENT_EDIT" >> "$COPY/$SUBJECT"
rerecord "$COPY" "$SUBJECT"
out="$(bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B9a. a hash re-recorded at an unchanged version fails (rc $rc)" '[[ $rc -eq 1 ]]'
check "B9b. ... naming the file and the missing bump" \
  'grep -F "FAIL" <<<"$out" | grep -F "$SUBJECT" | grep -qF "not a bump"'

# a bump with a new hash
fresh_copy "$COPY"
echo "$COMMENT_EDIT" >> "$COPY/$SUBJECT"
set_version "$COPY/$SUBJECT" "$((SUBJECT_VERSION + 1))"
rerecord "$COPY" "$SUBJECT"
out="$(bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B10. a bump with a new hash passes (rc $rc)" '[[ $rc -eq 0 ]]'

# a version that goes backwards
fresh_copy "$COPY"
set_version "$COPY/$SUBJECT" "$((SUBJECT_VERSION - 1))"
rerecord "$COPY" "$SUBJECT"
out="$(bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B11. a version lower than the base's fails (rc $rc)" \
  '[[ $rc -eq 1 ]] && grep -F "FAIL" <<<"$out" | grep -qF "backwards"'

# a template the base does not have
NEWBASE="$TMP/newbase"
cp -r "$BASE_REPO" "$NEWBASE"
git -C "$NEWBASE" rm -q "templates/plans/$SUBJECT"
git -C "$NEWBASE" -c user.name=t -c user.email=t@t commit -q -m "no subject"
fresh_copy "$COPY"
out="$(TEMPLATE_BASE_REPO="$NEWBASE" bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B12. a template with no copy on the base is new and passes (rc $rc)" \
  '[[ $rc -eq 0 ]] && grep -qF "new template" <<<"$out"'

# no base at all
out="$(TEMPLATE_BASE_REF=no-such-ref bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B13. an unavailable base fails, naming the fetch (rc $rc)" \
  '[[ $rc -eq 1 ]] && grep -qF "git fetch origin main" <<<"$out"'

# a depth-1 clone of the base is enough
SHALLOW="$TMP/shallow"
git -c protocol.file.allow=always clone -q --depth 1 "file://$BASE_REPO" "$SHALLOW" 2>/dev/null
fresh_copy "$COPY"
echo "$COMMENT_EDIT" >> "$COPY/$SUBJECT"
rerecord "$COPY" "$SUBJECT"
out="$(TEMPLATE_BASE_REPO="$SHALLOW" TEMPLATE_BASE_REF="origin/$BASE_BRANCH" bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B14a. the re-record is caught through a depth-1 clone (shallow: $(git -C "$SHALLOW" rev-parse --is-shallow-repository), rc $rc)" \
  '[[ $rc -eq 1 && "$(git -C "$SHALLOW" rev-parse --is-shallow-repository)" == true ]]'
fresh_copy "$COPY"
out="$(TEMPLATE_BASE_REPO="$SHALLOW" TEMPLATE_BASE_REF="origin/$BASE_BRANCH" bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B14b. ... and an unchanged tree passes through it (rc $rc)" '[[ $rc -eq 0 ]]'

# ── B15. compared at the fork point: main moves on after the branch forks ────
# FORK: commit 1 (the real templates) is the fork point; the base branch then gains commit 2,
# a bump of $SUBJECT; HEAD is the branch, still at commit 1. Branch and base live in one
# repo here, so the checker's merge base resolves (TEMPLATE_BRANCH_REPO).
FORK="$TMP/fork"
FORK_BRANCH="feature-branch"
MAIN_BUMP_VERSION="$((SUBJECT_VERSION + 1))"
cp -r "$BASE_REPO" "$FORK"
git -C "$FORK" branch "$FORK_BRANCH"
echo "$COMMENT_EDIT main" >> "$FORK/templates/plans/$SUBJECT"
set_version "$FORK/templates/plans/$SUBJECT" "$MAIN_BUMP_VERSION"
git -C "$FORK" -c user.name=t -c user.email=t@t commit -q -a -m "main bumps $SUBJECT"
git -C "$FORK" symbolic-ref HEAD "refs/heads/$FORK_BRANCH"
fork_env() { TEMPLATE_BASE_REPO="$FORK" TEMPLATE_BASE_REF="$BASE_BRANCH" TEMPLATE_BRANCH_REPO="$FORK" bash "$CHECKER" "$COPY" 2>&1; }

# the branch touched no template: it passes though main's copy is at a newer version
fresh_copy "$COPY"
out="$(fork_env)"; rc=$?
check "B15a. a branch that never touched a template passes after main bumped it (rc $rc)" \
  '[[ $rc -eq 0 ]] && grep -qF "fork point" <<<"$out"'

# the branch edited a template without a bump, relative to its fork point: still fails
fresh_copy "$COPY"
echo "$COMMENT_EDIT" >> "$COPY/$SUBJECT"
rerecord "$COPY" "$SUBJECT"
out="$(fork_env)"; rc=$?
check "B15b. an unbumped edit fails against the fork point though main moved (rc $rc)" \
  '[[ $rc -eq 1 ]] && grep -F "FAIL" <<<"$out" | grep -F "$SUBJECT" | grep -qF "not a bump"'

# a branch that lowers the version below its fork point fails, without the "merge" advice
fresh_copy "$COPY"
set_version "$COPY/$SUBJECT" "$((SUBJECT_VERSION - 1))"
rerecord "$COPY" "$SUBJECT"
out="$(fork_env)"; rc=$?
check "B15c. a version below the fork point fails and does not tell the author to merge (rc $rc)" \
  '[[ $rc -eq 1 ]] && grep -F "FAIL" <<<"$out" | grep -qF "backwards" && ! grep -F "FAIL" <<<"$out" | grep -qF "merge"'

# the tip fallback: with no shared history the stale copy is below main's tip and the
# message says to merge (B11 above covers the fallback's other failure)
fresh_copy "$COPY"
out="$(TEMPLATE_BASE_REPO="$FORK" TEMPLATE_BASE_REF="$BASE_BRANCH" bash "$CHECKER" "$COPY" 2>&1)"; rc=$?
check "B15d. without shared history it falls back to the tip, fails, and says to merge (rc $rc)" \
  '[[ $rc -eq 1 ]] && grep -qF "compare point: tip" <<<"$out" && grep -F "FAIL" <<<"$out" | grep -qF "merge"'

echo
if (( fails > 0 )); then
  echo "template-version-bump: $fails failed"
  exit 1
fi
echo "template-version-bump: all passed"
