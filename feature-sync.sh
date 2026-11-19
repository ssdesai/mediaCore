#!/usr/bin/env bash
set -uo pipefail

# Bring a started feature's branch up to date with its base: feature-sync.sh [--self] <slug>
#
# The shape (self/features/branch-sync-and-fanout-docs/): a sibling's PR merges and `main`
# moves past a feature that is still in flight, so the later feature has to take the new
# `main` in before its own PR can land — and the hook denies every quick way of doing it
# (`reset --hard`, `checkout -B`, a rebase, a force-push; LIFECYCLE.md rule 2). In the
# 2026-11-17 wave every child that met this did the merge by hand. This script is the one
# sanctioned shape: it fetches `origin <base>` (the manifest's `base`, `main` when absent)
# and merges it into the feature's branch with an ordinary merge commit. It never rebases,
# resets, force-pushes or pushes at all, and the only ref it moves is the current branch,
# forward, by that merge.
#
# Refused, with nothing moved: a dirty working tree (tracked or untracked changes, or a
# merge already in progress); a checkout that is not on the slug's started branch — its
# TRACKED manifest's `branches[0]`, read by manifest_branch and started_features_on
# (plan-runner-roots.sh), never derived from the slug; an orchestrator's session; a base
# that cannot be fetched.
#
# On a conflict the merge is left IN PROGRESS for whoever runs it, the conflicted files are
# named and the next commands printed: resolve each, `git add` it, `git commit`; or
# `git merge --abort` to go back. On success it says what comes next: renumber any migration
# or test id that now collides with the base's, keep every sibling's fields, re-run the gate,
# and run a review scoped to the merge — a merge after the judged head is a new round
# (LIFECYCLE.md → step 5), and feature-close.sh refuses it until one has judged it.
#
# Exit codes: 0 merged, or already up to date; 1 refused; 2 usage; 3 conflict, merge in
# progress.

USAGE_RC=2
REFUSED_RC=1
CONFLICT_RC=3
SYNC_SCRIPT_NAME="feature-sync.sh"
REVIEW_RUNNER_NAME="run-review.sh"
# The remote the base is fetched from (plan-runner-roots.sh's PUSH_REMOTE, the same string)
SYNC_REMOTE="origin"
# A manifest with no `base` branched from this (manifest.py's default, LIFECYCLE.md step 2)
DEFAULT_BASE="main"
# The merge commit's subject: `<slug>: merge origin/<base>`, in the `<slug>: …` family every
# commit on a feature's branch uses
MERGE_SUBJECT_INFIX=": merge "
# The line layout of the other lifecycle scripts' output
LEAD_REFUSED="  refused  "
LEAD_INFO="  sync     "
LEAD_NEXT="  next     "
LEAD_FILE="    "

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
SELF_FLAG=()
if [[ "${1:-}" == "--self" ]]; then SELF_FLAG=(--self); shift; fi

usage() {
  echo "usage: $SYNC_SCRIPT_NAME [--self] <slug>" >&2
  exit "$USAGE_RC"
}
refuse() { echo "${LEAD_REFUSED}$*" >&2; exit "$REFUSED_RC"; }
# MERGE_HEAD as a ref, not as a file: `rev-parse --git-path` answers relative to the -C
# directory, so a `-f` test of it is wrong whenever this runs from anywhere but $CHECKOUT
merge_in_progress() { git -C "$CHECKOUT" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; }

(( $# == 1 )) || usage
FEATURE_SLUG="$1"
[[ -n "$FEATURE_SLUG" && "$FEATURE_SLUG" != -* ]] || usage
refuse_orchestrator_session "${CLAUDE_CODE_SESSION_ID:-}"   # an orchestrator builds nothing

CHECKOUT="$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null)" \
  || refuse "$REPO_DIR is not inside a git repository"
MANIFEST="$FEATURES_DIR/$FEATURE_SLUG/README.md"
FEATURE_LABEL="$FEATURES_LABEL/$FEATURE_SLUG"
SLUG_ARGS="${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG"

# ── Refusals: every one before anything is fetched or merged ──────────────────

[[ -f "$MANIFEST" ]] || refuse "no manifest at $FEATURE_LABEL/README.md — is that the right slug?"
CURRENT_BRANCH="$(git -C "$CHECKOUT" branch --show-current 2>/dev/null)"
FEATURE_BRANCH="$(manifest_branch "$MANIFEST" "$FEATURE_SLUG")"
if [[ "$CURRENT_BRANCH" != "$FEATURE_BRANCH" ]]; then
  refuse "this checkout is on '${CURRENT_BRANCH:-a detached HEAD}', not on '$FEATURE_BRANCH', the branch $FEATURE_LABEL/README.md names — run this from the feature's checkout, on that branch. Nothing was changed"
fi
STARTED=0
while IFS= read -r slug; do
  [[ "$slug" == "$FEATURE_SLUG" ]] && STARTED=1
done < <(started_features_on "$REPO_DIR" "$FEATURES_LABEL" "$CURRENT_BRANCH")
(( STARTED )) || refuse "$FEATURE_LABEL/README.md is not a tracked manifest naming '$CURRENT_BRANCH' — only a started feature's branch is synced (feature-start.sh commits the manifest). Nothing was changed"

if merge_in_progress; then
  refuse "a merge is already in progress here — finish it (resolve, git add, git commit) or abandon it (git merge --abort), then run this again"
fi
DIRTY="$(git -C "$CHECKOUT" status --porcelain --untracked-files=all 2>/dev/null)"
if [[ -n "$DIRTY" ]]; then
  refuse "the working tree is not clean — commit or remove these first, then run this again. Nothing was changed:"$'\n'"$DIRTY"
fi

BASE="$(manifest_field "$MANIFEST" base)"
BASE="${BASE:-$DEFAULT_BASE}"
git -C "$CHECKOUT" fetch -q "$SYNC_REMOTE" "refs/heads/$BASE" \
  || refuse "could not fetch $BASE from $SYNC_REMOTE — nothing was merged"
TARGET="$(git -C "$CHECKOUT" rev-parse -q --verify 'FETCH_HEAD^{commit}' 2>/dev/null)"
[[ -n "$TARGET" ]] || refuse "the fetch of $SYNC_REMOTE $BASE named no commit — nothing was merged"
HEAD_BEFORE="$(git -C "$CHECKOUT" rev-parse HEAD)"

if git -C "$CHECKOUT" merge-base --is-ancestor "$TARGET" HEAD 2>/dev/null; then
  echo "${LEAD_INFO}'$FEATURE_BRANCH' already contains $SYNC_REMOTE/$BASE (${TARGET:0:12}) — nothing to merge"
  exit 0
fi
INCOMING="$(git -C "$CHECKOUT" rev-list --count "HEAD..$TARGET" 2>/dev/null)"

# ── The merge: an ordinary merge commit, never a fast-forward, rebase or reset ──
SUBJECT="$FEATURE_SLUG$MERGE_SUBJECT_INFIX$SYNC_REMOTE/$BASE"
MERGE_OUT="$(git -C "$CHECKOUT" merge --no-ff --no-edit -m "$SUBJECT" "$TARGET" 2>&1)"
MERGE_RC=$?

if (( MERGE_RC == 0 )); then
  echo "${LEAD_INFO}merged $SYNC_REMOTE/$BASE (${TARGET:0:12}, $INCOMING commit(s)) into '$FEATURE_BRANCH': $(git -C "$CHECKOUT" rev-parse --short=12 HEAD) '$SUBJECT'"
  echo "${LEAD_NEXT}1. renumber any migration or test id that now collides with one $BASE brought in, and keep every sibling's fields in the shared schemas and fixtures"
  echo "${LEAD_NEXT}2. re-run the gate ($GATE_SCRIPT_LABEL)"
  echo "${LEAD_NEXT}3. review the merge: it landed after any review's judged head, so it is a new round — queue a brief scoped to the merge in $FEATURE_LABEL/review/incomplete/ and run '$SCRIPT_DIR/$REVIEW_RUNNER_NAME $SLUG_ARGS'"
  echo "${LEAD_NEXT}4. push the branch: git push -u $SYNC_REMOTE $FEATURE_BRANCH"
  exit 0
fi

if merge_in_progress; then
  echo "${LEAD_INFO}merging $SYNC_REMOTE/$BASE (${TARGET:0:12}) into '$FEATURE_BRANCH' CONFLICTED — the merge is left in progress. Conflicted files:" >&2
  while IFS= read -r path; do
    [[ -n "$path" ]] && echo "${LEAD_FILE}$path" >&2
  done < <(git -C "$CHECKOUT" diff --name-only --diff-filter=U 2>/dev/null)
  echo "${LEAD_NEXT}resolve each file, keeping both sides' intent (every sibling's fields; a colliding migration or test id renumbered), then: git add <file> … ; git commit --no-edit" >&2
  echo "${LEAD_NEXT}or abandon the merge, leaving the branch where it was: git merge --abort" >&2
  echo "${LEAD_NEXT}after the commit: re-run the gate ($GATE_SCRIPT_LABEL) and a review scoped to the merge ('$SCRIPT_DIR/$REVIEW_RUNNER_NAME $SLUG_ARGS')" >&2
  exit "$CONFLICT_RC"
fi

# git refused before it began (no MERGE_HEAD): say what it said, and that nothing moved
if [[ "$(git -C "$CHECKOUT" rev-parse HEAD)" == "$HEAD_BEFORE" ]]; then
  refuse "git merge refused and left the branch where it was:"$'\n'"$MERGE_OUT"
fi
refuse "git merge failed with no merge in progress, and HEAD moved from ${HEAD_BEFORE:0:12} — run git status and say what it shows:"$'\n'"$MERGE_OUT"
