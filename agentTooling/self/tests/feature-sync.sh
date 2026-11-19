#!/usr/bin/env bash
set -uo pipefail

# Self-test for feature-sync.sh, the one sanctioned way to bring a started feature's branch
# up to date with its base (self/features/branch-sync-and-fanout-docs/). Run by
# self/gate.sh, or by hand: bash self/tests/feature-sync.sh
#
# Fixtures under mktemp -d: a bare origin holding main and the feature's branch, whose
# TRACKED manifest names it as branches[0]; a second clone moves origin/main past it. Each
# case is a fresh clone with feature-sync.sh and plan-runner-roots.sh under agentTooling/,
# on the feature's branch unless the case says otherwise. Asserts:
#   M1. main moved with no overlap: exit 0; HEAD is a merge commit whose parents are the
#       old HEAD and origin/main, subject `<slug>: merge origin/main`; the tree is clean;
#       the output names the gate and a review of the merge; nothing was pushed;
#   M2. ... run again: exit 0, already up to date, HEAD unmoved;
#   R1. a tracked file edited: refused (exit 1), nothing moved, the edit kept;
#   R2. an untracked file: refused, nothing moved;
#   R3. on main, not the feature's branch: refused, nothing moved;
#   R4. a detached HEAD: refused, nothing moved;
#   R5. the manifest present but untracked (ignored): refused, nothing moved;
#   R6. a slug with no manifest: refused;
#   C1. main changed the same line: exit 3; the merge is left in progress (MERGE_HEAD);
#       the conflicted file is named; `git merge --abort` and `git commit` are printed;
#       the branch ref has not moved;
#   C2. ... run again with that merge in progress: refused, nothing moved;
#   C3. ... `git merge --abort` puts the branch back exactly where it was;
#   U1. no slug, and two arguments: exit 2.
#
# No model, no network, no profile read.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/feature-sync.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

BASE="main"
BR="claude/feat-x"
SLUG="feat-x"
COPIED=(feature-sync.sh plan-runner-roots.sh)
EXIT_REFUSED=1
EXIT_USAGE=2
EXIT_CONFLICT=3
SHARED_FILE="notes.txt"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

gitq() { git -C "$1" "${@:2}"; }
identity() {
  gitq "$1" config user.email test@example.invalid
  gitq "$1" config user.name "feature sync test"
}

# The origin: main with a shared file, then the feature's branch carrying its manifest and
# an edit of its own to a separate file
SEED="$TMP/seed"
ORIGIN="$TMP/origin.git"
git init -q "$SEED"
gitq "$SEED" symbolic-ref HEAD "refs/heads/$BASE"
identity "$SEED"
mkdir -p "$SEED/agentTooling" "$SEED/plans/features/$SLUG"
for f in "${COPIED[@]}"; do cp "$HERE/$f" "$SEED/agentTooling/$f"; done
printf 'line one\nline two\n' > "$SEED/$SHARED_FILE"
gitq "$SEED" add -A
gitq "$SEED" commit -q -m init
git init -q --bare "$ORIGIN"
gitq "$SEED" remote add origin "$ORIGIN"
gitq "$SEED" push -q origin "$BASE"
gitq "$SEED" checkout -q -b "$BR"
printf '# %s\n\n```json\n{"slug": "%s", "base": "%s", "branches": ["%s"]}\n```\n' \
  "$SLUG" "$SLUG" "$BASE" "$BR" > "$SEED/plans/features/$SLUG/README.md"
echo "feature work" > "$SEED/feature.txt"
gitq "$SEED" add -A
gitq "$SEED" commit -q -m "$SLUG: start"
gitq "$SEED" push -q origin "$BR"
FEATURE_TIP="$(gitq "$SEED" rev-parse HEAD)"

# advance_main <file> <content> — a sibling's PR lands: origin/main moves by one commit
advance_main() {
  local other="$TMP/other-$RANDOM"
  git clone -q --branch "$BASE" "$ORIGIN" "$other"
  identity "$other"
  printf '%s' "$2" > "$other/$1"
  gitq "$other" add -A
  gitq "$other" commit -q -m "sibling lands on $BASE"
  gitq "$other" push -q origin "$BASE"
}

# clone <name> — a fresh checkout of the feature's branch, as its session has it
clone() {
  local repo="$TMP/$1"
  git clone -q --branch "$BR" "$ORIGIN" "$repo"
  identity "$repo"
  echo "$repo"
}

# sync <repo> [args] — run from the repo root, as a session would
sync() {
  local repo="$1"; shift
  ( cd "$repo" && env -u CLAUDE_CODE_SESSION_ID "$repo/agentTooling/feature-sync.sh" "$@" 2>&1 </dev/null )
}

# state <repo> — what must not move on a refusal: HEAD, the branch ref, the current branch
state() {
  echo "$(gitq "$1" rev-parse HEAD) $(gitq "$1" rev-parse -q --verify "refs/heads/$BR") $(gitq "$1" branch --show-current)"
}

# refused <label> <repo> <want> [args] — exit 1, the reason carries <want>, nothing moved
refused() {
  local label="$1" repo="$2" want="$3" before out rc
  shift 3
  before="$(state "$repo")"
  out="$(sync "$repo" "$@")"; rc=$?
  check "$label (got $rc: $out)" \
    '[[ $rc -eq $EXIT_REFUSED && "$(state "$repo")" == "$before" ]] && grep -qF -- "$want" <<<"$out"'
}

echo "feature-sync"

# ── M. merged ─────────────────────────────────────────────────────────────────
advance_main "sibling.txt" "from a sibling"$'\n'
R="$(clone m1)"
HEAD_BEFORE="$(gitq "$R" rev-parse HEAD)"
MAIN_TIP="$(gitq "$R" rev-parse "origin/$BASE")"
out="$(sync "$R" "$SLUG")"; rc=$?
check "M1a. main moved with no overlap: exit 0 (got $rc: $out)" '[[ $rc -eq 0 ]]'
check "M1b. ... HEAD is a merge of the old HEAD and origin/$BASE" \
  '[[ "$(gitq "$R" rev-parse HEAD^1)" == "$HEAD_BEFORE" && "$(gitq "$R" rev-parse HEAD^2)" == "$MAIN_TIP" && "$(gitq "$R" branch --show-current)" == "$BR" ]]'
check "M1c. ... its subject is '$SLUG: merge origin/$BASE'" \
  '[[ "$(gitq "$R" log -1 --format=%s)" == "$SLUG: merge origin/$BASE" ]]'
check "M1d. ... the sibling's file arrived and the tree is clean" \
  '[[ -f "$R/sibling.txt" && -z "$(gitq "$R" status --porcelain)" ]]'
check "M1e. ... the output names the gate and a review of the merge" \
  'grep -qF "gate" <<<"$out" && grep -qF "run-review.sh" <<<"$out"'
check "M1f. ... nothing was pushed" \
  '[[ "$(git -C "$ORIGIN" rev-parse "refs/heads/$BR")" == "$FEATURE_TIP" ]]'
HEAD_MERGED="$(gitq "$R" rev-parse HEAD)"
out="$(sync "$R" "$SLUG")"; rc=$?
check "M2. run again: exit 0, already up to date, HEAD unmoved (got $rc: $out)" \
  '[[ $rc -eq 0 && "$(gitq "$R" rev-parse HEAD)" == "$HEAD_MERGED" ]] && grep -qF "nothing to merge" <<<"$out"'

# ── R. refused, nothing moved ─────────────────────────────────────────────────
R="$(clone r1)"
echo "uncommitted" >> "$R/feature.txt"
refused "R1. a tracked file edited: refused, nothing moved" "$R" "not clean" "$SLUG"
check "R1b. ... the edit is kept" 'grep -qF uncommitted "$R/feature.txt"'
R="$(clone r2)"
echo "stray" > "$R/untracked.txt"
refused "R2. an untracked file: refused, nothing moved" "$R" "not clean" "$SLUG"
R="$(clone r3)"
gitq "$R" checkout -q "$BASE"
# the manifest is not on main, so the slug is unknown there
refused "R3. on $BASE, not the feature's branch: refused, nothing moved" "$R" "no manifest" "$SLUG"
R="$(clone r4)"
gitq "$R" checkout -q --detach HEAD
refused "R4. a detached HEAD: refused, nothing moved" "$R" "a detached HEAD" "$SLUG"
# R5: a branch whose manifest names it but was never committed (kept out of status by
# info/exclude, so the tree reads clean and only the tracked-manifest rule can refuse)
R="$(clone r5)"
gitq "$R" rm -q --cached "plans/features/$SLUG/README.md"
gitq "$R" commit -q -m "untrack the manifest"
echo "plans/features/$SLUG/README.md" >> "$R/.git/info/exclude"
refused "R5. the manifest present but untracked: refused, nothing moved" "$R" "not a tracked manifest" "$SLUG"
refused "R6. a slug with no manifest: refused" "$(clone r6)" "no manifest" "no-such-slug"

# ── C. conflict: the merge is left in progress ────────────────────────────────
R="$(clone c1)"
printf 'line one\nfeature edit\n' > "$R/$SHARED_FILE"
gitq "$R" commit -q -am "$SLUG: edit the shared line"
advance_main "$SHARED_FILE" $'line one\nmain edit\n'
HEAD_BEFORE="$(gitq "$R" rev-parse HEAD)"
out="$(sync "$R" "$SLUG")"; rc=$?
check "C1a. main changed the same line: exit $EXIT_CONFLICT (got $rc: $out)" '[[ $rc -eq $EXIT_CONFLICT ]]'
check "C1b. ... the merge is left in progress" '[[ -f "$R/.git/MERGE_HEAD" ]]'
check "C1c. ... the conflicted file is named" 'grep -qE "^ +$SHARED_FILE\$" <<<"$out"'
check "C1d. ... the next commands are printed" \
  'grep -qF "git merge --abort" <<<"$out" && grep -qF "git commit" <<<"$out" && grep -qF "git add" <<<"$out"'
check "C1e. ... the branch ref has not moved" \
  '[[ "$(gitq "$R" rev-parse HEAD)" == "$HEAD_BEFORE" && "$(gitq "$R" rev-parse "refs/heads/$BR")" == "$HEAD_BEFORE" ]]'
refused "C2. run again with that merge in progress: refused, nothing moved" "$R" "already in progress" "$SLUG"
gitq "$R" merge --abort
check "C3. git merge --abort puts the branch back where it was" \
  '[[ "$(gitq "$R" rev-parse HEAD)" == "$HEAD_BEFORE" && -z "$(gitq "$R" status --porcelain)" && ! -f "$R/.git/MERGE_HEAD" ]]'

# ── U. usage ──────────────────────────────────────────────────────────────────
R="$(clone u1)"
out="$(sync "$R")"; rc=$?
check "U1a. no slug: exit $EXIT_USAGE (got $rc)" '[[ $rc -eq $EXIT_USAGE ]]'
out="$(sync "$R" "$SLUG" extra)"; rc=$?
check "U1b. two arguments: exit $EXIT_USAGE (got $rc)" '[[ $rc -eq $EXIT_USAGE ]]'

echo
if (( fails )); then
  echo "feature-sync: $fails FAILED"
  exit 1
fi
echo "feature-sync: all assertions passed"
