#!/usr/bin/env bash
set -uo pipefail

# Pulls the latest agentTooling into a consuming repo and re-syncs plans/:
#   update.sh [--remote <url>] [--branch <name>]
#
# A pull is its own feature in the consuming repo (LIFECYCLE.md -> "Propagate"):
# `feature-start.sh pull-agenttooling-pr<N> --method hand` first, then this script, run as
# that worktree's copy — `<repo>/.worktrees/<slug>/agentTooling/update.sh` — so the pull
# lands on the feature's branch and the session that ran it is billed to that feature.
#
#   1. refuses when the directory holding this script IS the git toplevel — the source
#      checkout itself, with no prefix to pull into;
#   2. refuses unless the toplevel is on a started feature's branch: a detached HEAD, or a
#      branch B with no manifest at plans/features/B/README.md, is refused naming
#      feature-start.sh — `main` among them, since a pull onto main is exactly the spend no
#      feature's record ever counts. It creates no branch and no worktree itself;
#   3. refuses, naming the paths, when the toplevel's working tree is dirty — a subtree
#      pull aborts on any uncommitted change, not just one under this prefix, and a
#      clear refusal here beats git's own partway-through failure;
#   4. `git subtree pull --prefix=<this dir, relative to the toplevel> <remote> <branch>
#      --squash`, run from the toplevel, then prints the upstream sha the squash commit
#      records (`git-subtree-split:`) on a `split` line — what the feature's manifest
#      prose names as the sha pulled;
#   5. runs the freshly pulled copy of sync-plans.sh, so the stubs and repo-owned
#      scripts are checked against whatever the pull just changed, and exits with its
#      status.
#
# Step 4's `git subtree pull` overwrites this very file on disk while bash is still
# reading it, so the whole procedure lives inside main(), invoked on the last line:
# bash has already parsed the function body before the pull happens, and nothing after
# the call is ever read — a line placed there could execute out of the new file's bytes
# at whatever offset the old one left the interpreter.

# Also `analysis/roots.py`'s SELF_CORPUS_IDENTITY, which declares who agentTooling's own
# corpus belongs to, and the URL the root `README.md` -> "Updating" passes to
# `git subtree`. All three are the same string and move together.
DEFAULT_REMOTE="https://github.com/ssdesai/agentTooling.git"
DEFAULT_BRANCH="main"
USAGE_RC=2
REFUSED_RC=1

# Where a consuming repo keeps a started feature's manifest (sync-plans.sh's PLANS_DIR,
# feature-start.sh's features directory): a branch B is a feature's when this holds
# plans/features/B/README.md.
FEATURES_REL="plans/features"
MANIFEST_NAME="README.md"
# The slug the recipe names for a pull, with <N> the agentTooling PR it propagates
PULL_SLUG_PATTERN="pull-agenttooling-pr<N>"
# The trailers `git subtree --squash` writes on its squash commit
SUBTREE_DIR_TRAILER="git-subtree-dir:"
SUBTREE_SPLIT_TRAILER="git-subtree-split:"

usage() {
  echo "usage: update.sh [--remote <url>] [--branch <name>]" >&2
  exit "$USAGE_RC"
}

main() {
  local remote="$DEFAULT_REMOTE" branch="$DEFAULT_BRANCH"
  while (( $# )); do
    # Every value-taking flag checks its arity first: with no set -e here, a truncated
    # flag would otherwise spin this loop forever instead of printing the usage.
    case "$1" in
      --remote) (( $# >= 2 )) || usage; remote="$2"; shift 2 ;;
      --branch) (( $# >= 2 )) || usage; branch="$2"; shift 2 ;;
      *) usage ;;
    esac
  done

  local script_dir toplevel prefix
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  toplevel="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "  refused  $script_dir is not inside a git repository" >&2
    exit "$REFUSED_RC"
  }

  if [[ "$script_dir" == "$toplevel" ]]; then
    echo "  refused  this is the source checkout ($toplevel) — nothing to pull into" >&2
    exit "$REFUSED_RC"
  fi
  prefix="${script_dir#"$toplevel"/}"

  local start_hint="start the pull as its own feature first — from the primary checkout, agentTooling/feature-start.sh $PULL_SLUG_PATTERN --method hand — then run this script as that worktree's copy (LIFECYCLE.md -> \"Propagate\")"
  local current manifest
  current="$(git -C "$toplevel" branch --show-current)"
  if [[ -z "$current" ]]; then
    echo "  refused  $toplevel is on a detached HEAD; $start_hint" >&2
    exit "$REFUSED_RC"
  fi
  manifest="$FEATURES_REL/$current/$MANIFEST_NAME"
  if [[ ! -f "$toplevel/$manifest" ]]; then
    echo "  refused  branch '$current' is not a started feature (no $manifest); $start_hint" >&2
    exit "$REFUSED_RC"
  fi

  local dirty
  dirty="$(git -C "$toplevel" status --porcelain)"
  if [[ -n "$dirty" ]]; then
    echo "  refused  $toplevel has uncommitted changes; commit them first:" >&2
    echo "$dirty" | sed 's/^/           /' >&2
    exit "$REFUSED_RC"
  fi

  echo "  pull   $prefix <- $remote $branch  (on $current)"
  git -C "$toplevel" subtree pull --prefix="$prefix" "$remote" "$branch" --squash || exit "$REFUSED_RC"

  local split
  split="$(git -C "$toplevel" log -n 1 --format=%B --grep="^$SUBTREE_DIR_TRAILER $prefix\$" HEAD \
    | sed -n "s/^$SUBTREE_SPLIT_TRAILER *//p" | head -n 1)"
  echo "  split  ${split:-unknown}"

  echo "  sync   $prefix/sync-plans.sh"
  "$toplevel/$prefix/sync-plans.sh"
  exit $?
}

main "$@"
