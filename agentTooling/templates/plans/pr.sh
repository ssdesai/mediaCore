#!/usr/bin/env bash
set -uo pipefail
# template-version: 2

# This is what `sync-plans.sh --check` compares a seeded copy against to report drift.
# Bump it whenever the body below the marker changes in a way seeded copies must
# merge by hand.
#
# Opens a pull request for the batch just built, run by ../agentTooling/run-review.sh
# after a clean review pass. Seeded once from agentTooling/templates/plans/pr.sh by
# sync-plans.sh, then REPO-OWNED and never overwritten — customize it freely.
#
# It lives here, not in the shared harness, for the same reason gate.sh does: opening a
# PR is forge-specific (`gh` is GitHub's, `glab` is GitLab's, `tea` is Gitea's) and the
# harness must not pin every consuming repo to one vendor. The runner's contract with
# this script is small enough to satisfy from any of them.
#
# Contract run-review.sh relies on — do not change this part when customizing:
#
#   argv[1]              feature slug
#   argv[2]              path to the review report (may not exist; treat as optional)
#   cwd                  repo root
#   exit 0               PR opened, already open, or deliberately skipped
#   exit non-zero        something went wrong and the human should look
#   stdout               human-readable; print the PR URL if you have one
#
# Advisory, exactly like gate.sh: run-review.sh reports a non-zero exit and carries on.
# A failure here never unwinds a review pass that already succeeded.

SLUG="${1:?feature slug required}"
REPORT="${2:-}"

# ---------------------------------------------------------------------------
# REPO-SPECIFIC — everything below is yours to change.
# ---------------------------------------------------------------------------

FORGE_CLI="gh"
# The base of last resort, when neither the manifest nor the environment names one.
FALLBACK_BASE="main"

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

# This script never creates a branch. The head is whatever is checked out: feature-start.sh
# cut the feature branch and the whole feature — plans, build, verify, review — ran in its
# worktree, so the output is already on its own branch and there is nothing left to cut.
# The base is what that branch was cut from: FEATURE_BASE, which run-review.sh exports from
# the manifest's `base`, else BASE_BRANCH from the environment, else main. A stacked feature
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
