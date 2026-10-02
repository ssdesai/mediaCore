#!/usr/bin/env bash
set -uo pipefail
# template-version: 4

# Opens a pull request for the feature being closed, run by ../feature-close.sh --self
# after a clean review round. agentTooling's own copy of templates/plans/pr.sh — not
# written by sync-plans.sh (see self/README.md "Not generated"), so keep it in step by
# hand when the template changes.
#
# It lives here, not in the shared harness, for the same reason gate.sh does: opening a
# PR is forge-specific (`gh` is GitHub's, `glab` is GitLab's, `tea` is Gitea's) and the
# harness must not pin every consuming repo to one vendor. The runner's contract with
# this script is small enough to satisfy from any of them.
#
# Contract feature-close.sh relies on — do not change this part when customizing. Two
# entry points, because the two things a forge is asked for happen at different moments
# of the close and the order between them is load-bearing:
#
#   OPEN (the default)
#     argv[1]            feature slug
#     argv[2]            path to the PR body (may not exist; treat as optional)
#     cwd                repo root
#     exit 0             PR opened, already open, or deliberately skipped
#     exit non-zero      something went wrong and the human should look
#     stdout             human-readable; print the PR URL if you have one
#
#   MERGE REQUEST
#     argv[1]            --merge-request
#     argv[2]            feature slug
#     exit 0             merge requested, or deliberately not requested
#     It opens nothing and pushes nothing: it only asks the forge to merge the PR that is
#     already open, and only under PR_AUTO_MERGE — which this copy keeps off.
#
# Advisory, exactly like gate.sh: feature-close.sh reports a non-zero exit and carries on.
# A failure here never unwinds a review round that already came back clean.
#
# What runs BEFORE this script: the review pass commits its own output as
# `<slug>: review round N`, and feature-close.sh commits the stamps that followed it. So
# the working tree here is normally already clean and the commit below is only ever a
# no-op — it is the fallback for a repo whose runner predates that, and it keeps its old
# subject for exactly that reason.
#
# What runs AFTER the open entry point: feature-close.sh stamps `pr_opened`, then runs
# feature-capture.sh, which commits the feature's cost records on this same branch and
# pushes it again — so the PR ends up carrying both — and only THEN calls this script
# again with --merge-request.

MERGE_REQUEST=0
if [[ "${1:-}" == "--merge-request" ]]; then MERGE_REQUEST=1; shift; fi
SLUG="${1:?feature slug required}"
REPORT="${2:-}"

# Auto-merge is OFF here, whatever PR_AUTO_MERGE says — the one line that differs from the
# template's logic, and deliberately placed above the repo-specific section so the logic
# in it stays identical to templates/plans/pr.sh. A change to agentTooling ships to every
# consuming repo on its next `git subtree pull`, so a human reads the PR before it merges.
AUTO_MERGE=0

# ---------------------------------------------------------------------------
# REPO-SPECIFIC — everything below is yours to change.
# ---------------------------------------------------------------------------

FORGE_CLI="gh"
# The base of last resort, when neither the manifest nor the environment names one.
FALLBACK_BASE="main"
# The AUTO_MERGE value that turns auto-merge on, and how the forge is asked to merge.
# A merge commit, never a squash: feature-start.sh's prune and feature-capture.sh's
# post-merge path both decide "merged" by the branch being an ancestor of main, which a
# squash merge never makes it.
AUTO_MERGE_ON="1"
AUTO_MERGE_ARGS=(--auto --merge --delete-branch)

# auto_merge — ask the forge to merge the open PR once its requirements pass. Called only
# from the --merge-request entry point, which feature-close.sh calls last. Advisory: a
# refusal is reported and the PR stays open for a human, which is where it would be with
# auto-merge off.
auto_merge() {
  if [[ "$AUTO_MERGE" != "$AUTO_MERGE_ON" ]]; then
    echo "  merge   auto-merge is off (PR_AUTO_MERGE=${PR_AUTO_MERGE:-unset}) — no merge requested; merge the PR when it reads right"
    return 0
  fi
  if "$FORGE_CLI" pr merge "$current_branch" "${AUTO_MERGE_ARGS[@]}" >/dev/null 2>&1; then
    echo "  merge   auto-merge requested for $current_branch"
  else
    echo "  warn    $FORGE_CLI pr merge --auto was refused — merge the PR by hand"
  fi
}

if ! command -v "$FORGE_CLI" >/dev/null 2>&1; then
  echo "  skip  $FORGE_CLI not installed — no PR opened"
  exit 0
fi

if ! "$FORGE_CLI" auth status >/dev/null 2>&1; then
  echo "  skip  $FORGE_CLI is not authenticated — no PR opened"
  exit 0
fi

current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
if [[ -z "$current_branch" || "$current_branch" == "HEAD" ]]; then
  echo "  skip  detached HEAD or not a git repo — no PR opened"
  exit 0
fi

# The second entry point, and the whole of it: the PR is already open and its branch
# already carries the cost record, so all that is left is to ask.
if (( MERGE_REQUEST )); then
  auto_merge
  exit 0
fi

# This script never creates a branch. The head is whatever is checked out: feature-start.sh
# cut the feature branch and the whole feature — plans, build, verify, review — ran in its
# worktree, so the output is already on its own branch and there is nothing left to cut.
# The base is what that branch was cut from: FEATURE_BASE, which feature-close.sh exports
# from the manifest's `base`, else BASE_BRANCH from the environment, else main. A stacked feature
# therefore targets the feature beneath it, and the forge retargets the PR once that merges.
#
# On the base branch itself there is no feature branch to open a PR from, and committing
# and pushing it would be the one thing the branch rule exists to prevent — so refuse, and
# say what to do instead. (LIFECYCLE.md; self/features/feature-lifecycle/README.md item 13.)
BASE_BRANCH="${FEATURE_BASE:-${BASE_BRANCH:-$FALLBACK_BASE}}"
if [[ "$current_branch" == "$BASE_BRANCH" ]]; then
  echo "  fail  on '$current_branch', which is this PR's base — nothing to open a PR from."
  echo "        Run the batch inside the feature worktree feature-start.sh made, so it"
  echo "        builds on its own branch; nothing is committed or pushed from here."
  exit 1
fi

# The batch's output IS the working tree, so everything goes in — including this
# feature's plan corpus, which is part of the record. `.gitignore` already excludes the
# raw event streams.
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A || exit 1
  git commit -q -m "$SLUG: build, verify and review passes" || exit 1
  echo "  commit  $(git rev-parse --short HEAD) on $current_branch"
else
  echo "  commit  nothing to commit — working tree clean"
fi

if ! git push -q -u origin "$current_branch" 2>&1; then
  echo "  fail  could not push $current_branch"
  exit 1
fi
echo "  push    $current_branch -> origin"

existing="$("$FORGE_CLI" pr view "$current_branch" --json url --jq .url 2>/dev/null || true)"
if [[ -n "$existing" ]]; then
  echo "  pr      already open: $existing"
  exit 0
fi

# The review pass's own findings are the PR body — that is the thing a human is being
# asked to approve, and re-summarizing it here would be a second, drifting account of
# the same review.
body_args=()
if [[ -n "$REPORT" && -f "$REPORT" ]]; then
  body_args=(--body-file "$REPORT")
else
  body_args=(--body "Built, verified and reviewed by the agentTooling batch for \`$SLUG\`. No review report was written.")
fi

url="$("$FORGE_CLI" pr create --base "$BASE_BRANCH" --head "$current_branch" \
  --title "$SLUG" "${body_args[@]}" 2>&1)" || {
  echo "  fail  $FORGE_CLI pr create failed:"
  echo "$url"
  exit 1
}
echo "  pr      $url"
