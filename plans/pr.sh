#!/usr/bin/env bash
set -uo pipefail
# template-version: 6

# This is what `sync-plans.sh --check` compares a seeded copy against to report drift.
# Bump it whenever the body below the marker changes in a way seeded copies must
# merge by hand.
#
# Opens a pull request for the feature being closed, run by
# ../agentTooling/feature-close.sh after a clean review round. Seeded once from
# agentTooling/templates/plans/pr.sh by sync-plans.sh, then REPO-OWNED and never
# overwritten — customize it freely.
#
# It lives here, not in the shared harness, for the same reason gate.sh does: opening a
# PR is forge-specific (`gh` is GitHub's, `glab` is GitLab's, `tea` is Gitea's) and the
# harness must not pin every consuming repo to one vendor. The runner's contract with
# this script is small enough to satisfy from any of them.
#
# For GitHub this copy does the git part itself — commit, push — and hands the forge part
# to agentTooling/forge.sh (`pr-find`, then `pr-open`; on the merge request `pr-find`,
# then `auto-merge`). forge.sh opens over `gh api` REST, the one path that works both on a
# laptop and in a Claude Code cloud container, whose proxy refuses GraphQL (`gh pr …`)
# and fails `gh auth status`, and asks for the merge the way each of the two allows. A
# repo on another forge replaces those calls with its own CLI and never calls forge.sh.
#
# Contract feature-close.sh relies on — do not change this part when customizing. Two
# entry points, because the two things a forge is asked for happen at different moments
# of the close and the order between them is load-bearing:
#
#   OPEN (the default)
#     argv[1]            feature slug
#     argv[2]            path to the PR body (may not exist; treat as optional)
#     cwd                repo root
#     FORGE_SCRIPT       env: the forge adapter's path, exported by feature-close.sh
#     exit 0             PR opened, already open, or deliberately skipped — and skipped
#                        ONLY where there is no forge CLI at all: a forge that is there
#                        and refused is a failure, never a skip
#     exit non-zero      something went wrong and the human should look
#     stdout             human-readable; print the PR URL if you have one
#
#   MERGE REQUEST
#     argv[1]            --merge-request
#     argv[2]            feature slug
#     exit 0             merge requested, or deliberately not requested
#     It opens nothing and pushes nothing: it only asks the forge to merge the PR that is
#     already open, and only under PR_AUTO_MERGE.
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
# again with --merge-request. That ordering is why the merge request moved out of the open
# path: asked for here, the forge could merge before the cost commit was pushed.

MERGE_REQUEST=0
if [[ "${1:-}" == "--merge-request" ]]; then MERGE_REQUEST=1; shift; fi
SLUG="${1:?feature slug required}"
REPORT="${2:-}"

# Opt-in auto-merge, asked for only through --merge-request and therefore only after the
# cost record has been committed and pushed: PR_AUTO_MERGE=1 in the environment asks
# forge.sh to auto-merge the open PR, and anything else leaves the merge to a human.
# Off by default. With it on, the tail from verdict to costed merge is unattended.
AUTO_MERGE="${PR_AUTO_MERGE:-0}"

# ---------------------------------------------------------------------------
# REPO-SPECIFIC — everything below is yours to change.
# ---------------------------------------------------------------------------

FORGE_CLI="gh"
# The base of last resort, when neither the manifest nor the environment names one.
FALLBACK_BASE="main"
# Where the forge adapter is when FORGE_SCRIPT (which feature-close.sh exports) is unset —
# this script run by hand. Relative to the cwd, which the contract says is the repo root:
# a consuming repo's vendored copy first, then agentTooling's own root (`--self`). Each
# carries a slash, so it runs from the cwd and is never looked up on PATH.
FORGE_SCRIPT_FALLBACKS=(./agentTooling/forge.sh ./forge.sh)
# The body when the review wrote no report.
FALLBACK_BODY_TEMPLATE="pr-body.XXXXXX"
# The AUTO_MERGE value that turns auto-merge on. HOW the forge is asked — a merge commit,
# never a squash, by `gh pr merge` on a laptop and the proxy's REST route in a cloud
# container — is forge.sh's `auto-merge`, which picks by profile.
AUTO_MERGE_ON="1"

# auto_merge — ask the forge to merge the open PR once its requirements pass. Called only
# from the --merge-request entry point, which feature-close.sh calls last. The PR is the
# one forge.sh pr-find finds open for this branch. Advisory: no adapter, no open PR, or a
# refusal is reported and the PR stays open for a human, which is where it would be with
# auto-merge off.
auto_merge() {
  local forge pr_url
  if [[ "$AUTO_MERGE" != "$AUTO_MERGE_ON" ]]; then
    echo "  merge   auto-merge is off (PR_AUTO_MERGE=${PR_AUTO_MERGE:-unset}) — no merge requested; merge the PR when it reads right"
    return 0
  fi
  forge="$(forge_script)"
  if [[ -z "$forge" || ! -x "$forge" ]]; then
    echo "  warn    no forge adapter (FORGE_SCRIPT is ${FORGE_SCRIPT:-unset}) — no merge requested; merge the PR by hand"
    return 0
  fi
  if ! pr_url="$("$forge" pr-find "$current_branch")" || [[ -z "$pr_url" ]]; then
    echo "  warn    $forge pr-find found no open PR for $current_branch — no merge requested; merge the PR by hand"
    return 0
  fi
  if "$forge" auto-merge "$pr_url" >/dev/null; then
    echo "  merge   auto-merge requested for $pr_url"
  else
    echo "  warn    $forge auto-merge $pr_url was refused — merge the PR by hand"
  fi
}

# forge_script — the forge adapter to call: FORGE_SCRIPT, else the first of
# FORGE_SCRIPT_FALLBACKS that is here, else nothing.
forge_script() {
  local candidate
  if [[ -n "${FORGE_SCRIPT:-}" ]]; then echo "$FORGE_SCRIPT"; return 0; fi
  for candidate in "${FORGE_SCRIPT_FALLBACKS[@]}"; do
    if [[ -x "$candidate" ]]; then echo "$candidate"; return 0; fi
  done
}

# No forge CLI at all is the one deliberate skip: a repo with no forge. There is no
# `auth status` probe — a forge that is there and refuses says so below, as a failure.
if ! command -v "$FORGE_CLI" >/dev/null 2>&1; then
  echo "  skip  $FORGE_CLI not installed — no PR opened"
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

# Found before anything is committed or pushed, so a missing adapter changes nothing.
FORGE="$(forge_script)"
if [[ -z "$FORGE" || ! -x "$FORGE" ]]; then
  echo "  fail  no forge adapter: FORGE_SCRIPT is ${FORGE_SCRIPT:-unset} and none of"
  echo "        ${FORGE_SCRIPT_FALLBACKS[*]} is executable from $(pwd) — run this through"
  echo "        feature-close.sh, which exports it; nothing was committed or pushed."
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

# A forge that cannot be asked is a failure, not "nothing open": carrying on would open a
# second PR, or report one opened that never was.
if ! existing="$("$FORGE" pr-find "$current_branch")"; then
  echo "  fail  $FORGE pr-find $current_branch failed — no PR opened"
  exit 1
fi
if [[ -n "$existing" ]]; then
  echo "  pr      already open: $existing"
  exit 0
fi

# The review pass's own findings are the PR body — that is the thing a human is being
# asked to approve, and re-summarizing it here would be a second, drifting account of
# the same review. The adapter reads the body from a file, so the fallback is one too.
body_file="$REPORT"
if [[ -z "$REPORT" || ! -f "$REPORT" ]]; then
  body_file="$(mktemp "${TMPDIR:-/tmp}/$FALLBACK_BODY_TEMPLATE")" || exit 1
  trap 'rm -f "$body_file"' EXIT
  echo "Built, verified and reviewed by the agentTooling batch for \`$SLUG\`. No review report was written." > "$body_file"
fi

if ! url="$("$FORGE" pr-open "$current_branch" "$BASE_BRANCH" "$SLUG" "$body_file")"; then
  echo "  fail  $FORGE pr-open $current_branch into $BASE_BRANCH failed — no PR opened"
  exit 1
fi
echo "  pr      $url"
