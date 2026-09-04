#!/usr/bin/env bash
set -uo pipefail

# Pulls the latest agentTooling into a consuming repo and re-syncs plans/:
#   update.sh [--remote <url>] [--branch <name>]
#
#   1. refuses when the directory holding this script IS the git toplevel — the source
#      checkout itself, with no prefix to pull into;
#   2. refuses, naming the paths, when the toplevel's working tree is dirty — a subtree
#      pull aborts on any uncommitted change, not just one under this prefix, and a
#      clear refusal here beats git's own partway-through failure;
#   3. `git subtree pull --prefix=<this dir, relative to the toplevel> <remote> <branch>
#      --squash`, run from the toplevel;
#   4. runs the freshly pulled copy of sync-plans.sh, so the stubs and repo-owned
#      scripts are checked against whatever the pull just changed, and exits with its
#      status.
#
# Step 3's `git subtree pull` overwrites this very file on disk while bash is still
# reading it, so the whole procedure lives inside main(), invoked on the last line:
# bash has already parsed the function body before the pull happens, and nothing after
# the call is ever read — a line placed there could execute out of the new file's bytes
# at whatever offset the old one left the interpreter.

DEFAULT_REMOTE="https://github.com/ssdesai/agentTooling.git"
DEFAULT_BRANCH="main"
USAGE_RC=2
REFUSED_RC=1

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

  local dirty
  dirty="$(git -C "$toplevel" status --porcelain)"
  if [[ -n "$dirty" ]]; then
    echo "  refused  $toplevel has uncommitted changes; commit or stash first:" >&2
    echo "$dirty" | sed 's/^/           /' >&2
    exit "$REFUSED_RC"
  fi

  echo "  pull   $prefix <- $remote $branch"
  git -C "$toplevel" subtree pull --prefix="$prefix" "$remote" "$branch" --squash || exit "$REFUSED_RC"

  echo "  sync   $prefix/sync-plans.sh"
  "$toplevel/$prefix/sync-plans.sh"
  exit $?
}

main "$@"
