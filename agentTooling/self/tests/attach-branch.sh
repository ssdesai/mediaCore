#!/usr/bin/env bash
set -uo pipefail

# Self-test for attach-branch.sh, the one way a cloud session re-attaches a detached HEAD
# to its feature's branch (self/features/detached-at-branch-tip-attach/). Run by
# self/gate.sh, or by hand: bash self/tests/attach-branch.sh
#
# Fixtures under mktemp -d: a bare origin holding main and the feature's branch, whose
# tracked manifest names it as branches[0]; each case is a fresh clone of it with
# attach-branch.sh, plan-runner-roots.sh, env-profile.sh and hooks/env_profile.py under
# agentTooling/. "The shape" is the observed one: HEAD detached exactly at
# origin/<branch>, the local <branch> a strict ancestor (behind by one). Asserts:
#   T1. cloud, the shape: exit 0; HEAD is now on <branch>, at the SAME commit; the local
#       ref moved to it; the upstream is origin/<branch>; an uncommitted edit survives;
#   T2. ... the branch argument may be omitted when there is one candidate;
#   T3. cloud, detached at the tip with NO local <branch>: created there, exit 0;
#   T4. cloud, already on the feature's branch: exit 0, nothing to do;
#   R1. cloud, detached at a commit that is not origin/<branch>: exit 1, nothing moved;
#   R2. cloud, the local <branch> holds a commit HEAD lacks: exit 1, nothing moved;
#   R3. cloud, the tip of a branch no manifest names: exit 1, nothing moved;
#   R4. local profile, the shape: exit 1, nothing moved;
#   R5. cloud, on another branch: exit 1;
#   R6. cloud, the shape, the local <branch> checked out in another worktree: exit 1,
#       nothing moved (update-ref would move that worktree's branch under it);
#   U1. two branch arguments: exit 2.
#
# No model, no network. The profile is forced with AGENTTOOLING_PROFILE.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/attach-branch.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

BASE="main"
BR="claude/feat-x"
SLUG="feat-x"
OTHER="claude/no-manifest"
COPIED=(attach-branch.sh plan-runner-roots.sh env-profile.sh)
EXIT_REFUSED=1
EXIT_USAGE=2

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

gitq() { git -C "$1" "${@:2}"; }
identity() {
  gitq "$1" config user.email test@example.invalid
  gitq "$1" config user.name "attach branch test"
}

# The origin: main, then the feature's branch carrying its manifest, then OTHER
SEED="$TMP/seed"
ORIGIN="$TMP/origin.git"
git init -q "$SEED"
gitq "$SEED" symbolic-ref HEAD "refs/heads/$BASE"
identity "$SEED"
mkdir -p "$SEED/agentTooling/hooks" "$SEED/plans/features/$SLUG"
for f in "${COPIED[@]}"; do cp "$HERE/$f" "$SEED/agentTooling/$f"; done
cp "$HERE/hooks/env_profile.py" "$SEED/agentTooling/hooks/env_profile.py"
echo fixture > "$SEED/notes.txt"
gitq "$SEED" add -A
gitq "$SEED" commit -q -m init
git init -q --bare "$ORIGIN"
gitq "$SEED" remote add origin "$ORIGIN"
gitq "$SEED" push -q origin "$BASE"
gitq "$SEED" push -q origin "HEAD:refs/heads/$OTHER"
gitq "$SEED" checkout -q -b "$BR"
printf '# %s\n\n```json\n{"slug": "%s", "base": "%s", "branches": ["%s"]}\n```\n' \
  "$SLUG" "$SLUG" "$BASE" "$BR" > "$SEED/plans/features/$SLUG/README.md"
gitq "$SEED" add -A
gitq "$SEED" commit -q -m "$SLUG: start"
gitq "$SEED" push -q origin "$BR"

# shape <name> [local-ahead|no-local|at-old] — a clone in the observed shape: the local
# BR at origin/BR's old tip, origin/BR one commit ahead, HEAD detached at origin/BR.
# `local-ahead` gives the local BR a commit of its own; `no-local` deletes it; `at-old`
# detaches at the OLD tip instead, so HEAD is not origin/BR.
shape() {
  local repo="$TMP/$1" variant="${2:-}"
  git clone -q --branch "$BASE" "$ORIGIN" "$repo"
  identity "$repo"
  gitq "$repo" branch -q "$BR" "origin/$BR"
  if [[ "$variant" == local-ahead ]]; then
    gitq "$repo" checkout -q "$BR"
    gitq "$repo" commit -q --allow-empty -m "local only"
  fi
  gitq "$repo" checkout -q --detach "origin/$BR"
  gitq "$repo" commit -q --allow-empty -m "newer on origin"
  gitq "$repo" update-ref "refs/remotes/origin/$BR" HEAD
  if [[ "$variant" == at-old ]]; then
    gitq "$repo" checkout -q --detach "HEAD~1"
  fi
  if [[ "$variant" == no-local ]]; then
    gitq "$repo" branch -q -D "$BR"
  fi
  echo "$repo"
}

# attach <profile> <repo> [args] — run from the repo root, as a session would
attach() {
  local profile="$1" repo="$2"; shift 2
  ( cd "$repo" && env -u CLAUDE_CODE_REMOTE AGENTTOOLING_PROFILE="$profile" \
      "$repo/agentTooling/attach-branch.sh" "$@" 2>&1 </dev/null )
}

# state <repo> — what must not move on a refusal: HEAD, the branch ref, the current branch
state() {
  echo "$(gitq "$1" rev-parse HEAD) $(gitq "$1" rev-parse -q --verify "refs/heads/$BR") $(gitq "$1" branch --show-current)"
}

echo "attach-branch"

# ── T. attached ───────────────────────────────────────────────────────────────
R="$(shape t1)"
HEAD_BEFORE="$(gitq "$R" rev-parse HEAD)"
echo edited >> "$R/notes.txt"
out="$(attach cloud "$R" "$BR")"; rc=$?
check "T1a. the shape: exit 0 (got $rc: $out)" '[[ $rc -eq 0 ]]'
check "T1b. ... HEAD is on $BR, at the same commit, and the ref moved to it" \
  '[[ "$(gitq "$R" branch --show-current)" == "$BR" && "$(gitq "$R" rev-parse HEAD)" == "$HEAD_BEFORE" && "$(gitq "$R" rev-parse "refs/heads/$BR")" == "$HEAD_BEFORE" ]]'
check "T1c. ... its upstream is origin/$BR" \
  '[[ "$(gitq "$R" rev-parse --abbrev-ref "$BR@{upstream}")" == "origin/$BR" ]]'
check "T1d. ... and the uncommitted edit survived" 'grep -qF edited "$R/notes.txt"'
R="$(shape t2)"
out="$(attach cloud "$R")"; rc=$?
check "T2. with no argument the only candidate is taken (got $rc: $out)" \
  '[[ $rc -eq 0 && "$(gitq "$R" branch --show-current)" == "$BR" ]]'
R="$(shape t3 no-local)"
HEAD_BEFORE="$(gitq "$R" rev-parse HEAD)"
out="$(attach cloud "$R" "$BR")"; rc=$?
check "T3. no local $BR: created at the tip and checked out (got $rc: $out)" \
  '[[ $rc -eq 0 && "$(gitq "$R" branch --show-current)" == "$BR" && "$(gitq "$R" rev-parse HEAD)" == "$HEAD_BEFORE" ]]'
out="$(attach cloud "$R")"; rc=$?
check "T4. already on the feature's branch: exit 0, nothing to do (got $rc: $out)" \
  '[[ $rc -eq 0 ]] && grep -qF "nothing to do" <<<"$out"'

# ── R. refused, nothing moved ─────────────────────────────────────────────────
refused() {
  local label="$1" repo="$2" profile="$3" want="$4" before out rc
  shift 4
  before="$(state "$repo")"
  out="$(attach "$profile" "$repo" "$@")"; rc=$?
  check "$label (got $rc: $out)" \
    '[[ $rc -eq $EXIT_REFUSED && "$(state "$repo")" == "$before" ]] && grep -qF "$want" <<<"$out"'
}
refused "R1. detached at a commit that is not origin/$BR: refused, nothing moved" \
  "$(shape r1 at-old)" cloud "is not origin/$BR" "$BR"
refused "R2. the local $BR holds a commit HEAD lacks: refused, nothing moved" \
  "$(shape r2 local-ahead)" cloud "not an ancestor of HEAD" "$BR"
R="$(shape r3)"
gitq "$R" update-ref "refs/remotes/origin/$OTHER" HEAD
refused "R3. the tip of a branch no manifest names: refused, nothing moved" \
  "$R" cloud "no tracked manifest" "$OTHER"
refused "R4. the local profile: refused, nothing moved" "$(shape r4)" local "local profile" "$BR"
R="$(shape r5)"
gitq "$R" checkout -q "$BASE"
refused "R5. on another branch: refused" "$R" cloud "not detached" "$BR"
R="$(shape r6)"
gitq "$R" worktree add -q "$TMP/r6-worktree" "$BR"
refused "R6. the local $BR checked out in another worktree: refused, nothing moved" \
  "$R" cloud "checked out in another worktree" "$BR"

# ── U. usage ──────────────────────────────────────────────────────────────────
out="$(attach cloud "$(shape u1)" "$BR" extra)"; rc=$?
check "U1. two branch arguments: exit $EXIT_USAGE (got $rc)" '[[ $rc -eq $EXIT_USAGE ]]'

echo
if (( fails )); then
  echo "attach-branch: $fails FAILED"
  exit 1
fi
echo "attach-branch: all assertions passed"
