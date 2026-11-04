#!/usr/bin/env bash
set -uo pipefail

# Re-attach a cloud container's detached HEAD to its feature's branch, moving nothing.
#
#   attach-branch.sh [--self] [<branch>]
#
# The shape (self/features/detached-at-branch-tip-attach/): a cloud session launched to
# CONTINUE a feature's branch can come up with HEAD detached exactly at origin/<branch>
# while the local <branch> — left by an earlier session's cached clone — is a strict
# ancestor, behind. A fresh session reproduces it, and the session itself is stuck: the
# hook refuses `git checkout -B` (a cloud session never moves a branch ref,
# LIFECYCLE.md rule 2), a plain `git checkout <branch>` would put the working tree back on
# the stale commit, and the harness's commit steps refuse a detached HEAD.
#
# This script is the one way out, and it only ever takes it when nothing moves: HEAD is
# detached, <branch> is a started feature's branch (a tracked manifest's branches[0]),
# origin/<branch> IS HEAD's commit, and the local <branch> is absent or an ancestor of
# HEAD — plan-runner-roots.sh's attachable_branches, the same reading session-start.sh
# names and the hook's reason checks. Then it points refs/heads/<branch> at HEAD (a
# compare-and-swap against the old value), checks it out — the same commit, so the working
# tree and any local change stay exactly as they are — and sets its upstream. With no
# <branch> it takes the only candidate; none, or several, is a refusal naming them.
#
# Cloud only: locally a detached checkout is the human's to sort out. Exit 0 attached (or
# already on a started feature's branch), 1 refused, 2 usage.

USAGE="usage: attach-branch.sh [--self] [<branch>]"
EXIT_REFUSED=1
EXIT_USAGE=2
# What the local branch's reflog says moved it
REFLOG_MESSAGE="attach-branch.sh: re-attach a detached HEAD at the branch's remote tip"
# How `git worktree list --porcelain` names a worktree's checked-out branch
WORKTREE_BRANCH_LINE_PREFIX="branch refs/heads/"
# The docs a refusal points at, relative to agentTooling's own directory
LIFECYCLE_DOC="LIFECYCLE.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
source "$SCRIPT_DIR/env-profile.sh"

SELF_FLAG=""
if [[ "${1:-}" == "--self" ]]; then
  SELF_FLAG="--self"
  shift
fi
if (( $# > 1 )) || [[ "${1:-}" == -* ]]; then
  echo "$USAGE" >&2
  exit "$EXIT_USAGE"
fi
WANTED="${1:-}"
resolve_roots "$SELF_FLAG"
DOC="$LIFECYCLE_DOC"
(( SELF_MODE )) || DOC="agentTooling/$LIFECYCLE_DOC"

refuse() {
  echo "attach-branch: $1" >&2
  exit "$EXIT_REFUSED"
}

profile_check >/dev/null || refuse "$(profile_check)"
profile_is_cloud || refuse "this is the local profile: a detached checkout there is the human's to re-attach, not an agent's ($DOC)"

CURRENT="$(git -C "$REPO_DIR" branch --show-current 2>/dev/null)"
if [[ -n "$CURRENT" ]]; then
  if [[ -n "$(started_features_on "$REPO_DIR" "$FEATURES_LABEL" "$CURRENT")" ]] \
     && [[ -z "$WANTED" || "$WANTED" == "$CURRENT" ]]; then
    echo "attach-branch: already on '$CURRENT', a started feature's branch — nothing to do"
    exit 0
  fi
  refuse "HEAD is on '$CURRENT', not detached: this script only re-attaches a detached HEAD, and a cloud session never switches branches ($DOC rule 2)"
fi

CANDIDATES=()
while IFS= read -r branch; do
  CANDIDATES+=("$branch")
done < <(attachable_branches "$REPO_DIR" "$FEATURES_LABEL")

# why_not <branch> — the first condition <branch> fails, for the refusal
why_not() {
  local branch="$1" head tip
  if [[ -z "$(started_features_on "$REPO_DIR" "$FEATURES_LABEL" "$branch")" ]]; then
    echo "no tracked manifest under $FEATURES_LABEL/ names '$branch' as its branches[0]"
    return
  fi
  head="$(git -C "$REPO_DIR" rev-parse -q --verify 'HEAD^{commit}')"
  tip="$(git -C "$REPO_DIR" rev-parse -q --verify "refs/remotes/$ATTACH_REMOTE/$branch^{commit}")"
  if [[ -z "$tip" ]]; then
    echo "there is no $ATTACH_REMOTE/$branch to match HEAD against"
  elif [[ "$tip" != "$head" ]]; then
    echo "HEAD (${head:0:12}) is not $ATTACH_REMOTE/$branch (${tip:0:12}), so attaching would move the working tree"
  else
    echo "the local '$branch' is not an ancestor of HEAD — it holds commits HEAD does not, and attaching would throw them away"
  fi
}

if [[ -n "$WANTED" ]]; then
  TARGET=""
  for branch in "${CANDIDATES[@]}"; do
    [[ "$branch" == "$WANTED" ]] && TARGET="$branch"
  done
  [[ -n "$TARGET" ]] || refuse "cannot re-attach to '$WANTED': $(why_not "$WANTED"). Nothing was changed; stop and say that this container is off its feature's branch ($DOC)"
elif (( ${#CANDIDATES[@]} == 1 )); then
  TARGET="${CANDIDATES[0]}"
elif (( ${#CANDIDATES[@]} == 0 )); then
  refuse "HEAD is detached, but at no started feature's branch tip ($ATTACH_REMOTE/<branch> == HEAD, local <branch> absent or behind). Nothing was changed; stop and say that this container is off its feature's branch ($DOC)"
else
  refuse "HEAD is the tip of several started features' branches (${CANDIDATES[*]}): name one"
fi

# update-ref is plumbing and does not check worktrees: moving a branch another worktree has
# checked out would leave that tree's files behind its HEAD, and the checkout below would
# then fail with the ref already moved
if git -C "$REPO_DIR" worktree list --porcelain 2>/dev/null \
     | grep -qxF "$WORKTREE_BRANCH_LINE_PREFIX$TARGET"; then
  refuse "'$TARGET' is checked out in another worktree (git worktree list), so moving it would change that tree. Nothing was changed; stop and say so ($DOC)"
fi

OLD="$(git -C "$REPO_DIR" rev-parse -q --verify "refs/heads/$TARGET" 2>/dev/null)"
git -C "$REPO_DIR" update-ref -m "$REFLOG_MESSAGE" "refs/heads/$TARGET" HEAD "$OLD" \
  || refuse "could not point '$TARGET' at HEAD (it moved under this script?); nothing was checked out"
git -C "$REPO_DIR" checkout -q "$TARGET" \
  || refuse "pointed '$TARGET' at HEAD but could not check it out; run git status and say what it shows"
git -C "$REPO_DIR" branch -q --set-upstream-to="$ATTACH_REMOTE/$TARGET" "$TARGET" 2>/dev/null \
  || echo "attach-branch: (could not set '$TARGET''s upstream to $ATTACH_REMOTE/$TARGET; push with -u)"
if [[ -n "$OLD" ]]; then
  echo "attach-branch: '$TARGET' moved ${OLD:0:12} → $(git -C "$REPO_DIR" rev-parse --short=12 HEAD) (fast-forward to $ATTACH_REMOTE/$TARGET) and checked out; the working tree did not change"
else
  echo "attach-branch: '$TARGET' created at $ATTACH_REMOTE/$TARGET ($(git -C "$REPO_DIR" rev-parse --short=12 HEAD)) and checked out; the working tree did not change"
fi
