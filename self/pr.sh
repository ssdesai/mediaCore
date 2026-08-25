#!/usr/bin/env bash
set -uo pipefail

# Opens a pull request for the batch just built, run by ../run-review.sh --self after
# a clean review pass. agentTooling's own copy of templates/plans/pr.sh — not written
# by sync-plans.sh (see self/README.md "Not generated"), so keep it in step by hand
# when the template changes.
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

BASE_BRANCH="main"
BRANCH_PREFIX="review"
FORGE_CLI="gh"

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

# Never commit onto the base branch. `checkout -b` creates from the current HEAD and
# leaves every file — tracked and untracked — exactly where it is, so the plan queue
# this run is being driven from travels with it. That is the one git operation in this
# script that touches a ref, and it is safe for the reason `git stash` is not.
if [[ "$current_branch" == "$BASE_BRANCH" ]]; then
  current_branch="$BRANCH_PREFIX/$SLUG"
  if git show-ref --verify --quiet "refs/heads/$current_branch"; then
    echo "  fail  branch $current_branch already exists; not switching onto it"
    exit 1
  fi
  git checkout -b "$current_branch" || exit 1
  echo "  branch  created $current_branch off $BASE_BRANCH"
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
