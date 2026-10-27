#!/usr/bin/env bash
set -uo pipefail

# Pulls the latest agentTooling into a consuming repo and re-syncs plans/:
#   update.sh [--remote <url>] [--branch <name>]
#
# A pull is its own feature in the consuming repo (LIFECYCLE.md -> "Propagate"):
# `feature-start.sh pull-agenttooling-pr<N> --method hand` first, then this script, run as
# that worktree's copy — `<repo>/.worktrees/<slug>/agentTooling/update.sh` — so the pull
# lands on the feature's branch and the session that ran it is billed to that feature. In
# a Claude Code cloud container the container IS the worktree: the start runs on the
# session's assigned branch and this script is the checkout's own
# `<repo>/agentTooling/update.sh`.
#
#   1. refuses when the directory holding this script IS the git toplevel — the source
#      checkout itself, with no prefix to pull into;
#   2. refuses unless the toplevel is on a started feature's branch: a detached HEAD and
#      `main` are refused naming feature-start.sh, since a pull onto main is exactly the
#      spend no feature's record ever counts. A branch B is a feature's when
#      plans/features/B/README.md exists — the local layout, where the branch IS the slug —
#      or, failing that, when exactly ONE tracked manifest's branch (its fence's
#      `branches[0]`) is B — the cloud layout, where B is the session's assigned
#      `claude/…` branch and the manifest sits at plans/features/<slug>/README.md. That
#      lookup is plan-runner-roots.sh's started_features_on, the one session-start.sh's
#      orientation makes, sourced only on that path. No match is refused naming the path
#      it looked for; two or more are refused naming every slug. It creates no branch and
#      no worktree itself;
#   3. refuses, naming the paths, when the toplevel's working tree is dirty — a subtree
#      pull aborts on any uncommitted change, not just one under this prefix, and a
#      clear refusal here beats git's own partway-through failure;
#   4. `git subtree pull --prefix=<this dir, relative to the toplevel> <remote> <branch>
#      --squash`, run from the toplevel, then prints the upstream sha the squash commit
#      records (`git-subtree-split:`) on a `split` line — what the feature's manifest
#      prose names as the sha pulled. When the pull fails, its stderr reads as a failed
#      authentication (AUTH_FAILURE_RE), and env-profile.sh beside this script says the
#      profile is `cloud`, one `remedy` line follows git's own error: a Claude Code cloud
#      session's git proxy serves only the repositories attached to the session, so the
#      remote's GitHub repo must be attached with the `add_repo` tool (claude-code-remote
#      MCP, read access) and this script run again
#      (self/features/propagate-agenttooling-access/). No env-profile.sh beside it, or
#      the `local` profile, and nothing is added;
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
# plans/features/B/README.md, or else exactly one tracked manifest here names B (step 2).
FEATURES_REL="plans/features"
MANIFEST_NAME="README.md"
# The branch a pull never lands on, whatever names it (feature-start.sh's PRIMARY_BRANCH)
PROTECTED_BRANCH="main"
# The shared reader of "which feature is started on this branch", beside this script
ROOTS_LIB="plan-runner-roots.sh"
# The slug the recipe names for a pull, with <N> the agentTooling PR it propagates
PULL_SLUG_PATTERN="pull-agenttooling-pr<N>"
# The trailers `git subtree --squash` writes on its squash commit
SUBTREE_DIR_TRAILER="git-subtree-dir:"
SUBTREE_SPLIT_TRAILER="git-subtree-split:"

# The cloud remedy (step 4): the profile detector beside this script, and git's ways of
# saying an https fetch could not authenticate — a cloud container's proxy answers a repo
# not attached to the session with the first (seen 2026-10-26, three consuming repos).
PROFILE_LIB="env-profile.sh"
AUTH_FAILURE_RE="could not read Username|Authentication failed|returned error: 40[13]|Repository not found"
# owner/repo out of a GitHub remote URL (https or ssh), `.git` dropped
GITHUB_REPO_RE='github\.com[/:]([^/]+)/([^/]+)$'
GIT_SUFFIX=".git"
# The tool a cloud session attaches a repository with, and the access a pull needs
ATTACH_TOOL="add_repo"
ATTACH_SERVER="claude-code-remote MCP"
ATTACH_ACCESS="read"

usage() {
  echo "usage: update.sh [--remote <url>] [--branch <name>]" >&2
  exit "$USAGE_RC"
}

# cloud_auth_remedy <script dir> <remote> — the one `remedy` line of step 4, printed to
# stderr only when env-profile.sh beside this script exists and decides `cloud`
cloud_auth_remedy() {
  local dir="$1" remote="$2" repo
  [[ -f "$dir/$PROFILE_LIB" ]] || return 0
  source "$dir/$PROFILE_LIB"
  profile_is_cloud || return 0
  repo="$remote"
  if [[ "${remote%"$GIT_SUFFIX"}" =~ $GITHUB_REPO_RE ]]; then
    repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  fi
  echo "  remedy  the fetch from $remote could not authenticate, and this is a Claude Code cloud session, whose git proxy serves only the repositories attached to the session: attach $repo with the $ATTACH_TOOL tool ($ATTACH_SERVER, $ATTACH_ACCESS access), then run this script again (README.md -> \"Updating\")" >&2
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
  local current manifest feature
  current="$(git -C "$toplevel" branch --show-current)"
  if [[ -z "$current" ]]; then
    echo "  refused  $toplevel is on a detached HEAD; $start_hint" >&2
    exit "$REFUSED_RC"
  fi
  if [[ "$current" == "$PROTECTED_BRANCH" ]]; then
    echo "  refused  $toplevel is on $PROTECTED_BRANCH, which a pull never lands on; $start_hint" >&2
    exit "$REFUSED_RC"
  fi
  manifest="$FEATURES_REL/$current/$MANIFEST_NAME"
  feature="$current"
  if [[ ! -f "$toplevel/$manifest" ]]; then
    # The cloud layout: the branch is the session's, the manifest the slug's.
    local -a matches=()
    local match
    if [[ -f "$script_dir/$ROOTS_LIB" ]]; then
      source "$script_dir/$ROOTS_LIB"
      while IFS= read -r match; do
        matches+=("$match")
      done < <(started_features_on "$toplevel" "$FEATURES_REL" "$current")
    fi
    if (( ${#matches[@]} == 0 )); then
      echo "  refused  branch '$current' is not a started feature (no $manifest, and no tracked $FEATURES_REL/<slug>/$MANIFEST_NAME names it in its branches); $start_hint" >&2
      exit "$REFUSED_RC"
    fi
    if (( ${#matches[@]} > 1 )); then
      echo "  refused  branch '$current' carries ${#matches[@]} started features (${matches[*]}) — a branch holds one feature; finish all but one, or pull from a branch of its own" >&2
      exit "$REFUSED_RC"
    fi
    feature="${matches[0]}"
  fi

  local dirty
  dirty="$(git -C "$toplevel" status --porcelain)"
  if [[ -n "$dirty" ]]; then
    echo "  refused  $toplevel has uncommitted changes; commit them first:" >&2
    echo "$dirty" | sed 's/^/           /' >&2
    exit "$REFUSED_RC"
  fi

  echo "  pull   $prefix <- $remote $branch  (on $current, feature $feature)"
  # git's stderr is shown as it comes and kept, so a failure can be read afterwards
  local errlog pull_rc
  errlog="$(mktemp "${TMPDIR:-/tmp}/update-pull.XXXXXX")"
  { git -C "$toplevel" subtree pull --prefix="$prefix" "$remote" "$branch" --squash 2>&1 1>&3 3>&- \
      | tee "$errlog" >&2; pull_rc=${PIPESTATUS[0]}; } 3>&1
  if (( pull_rc != 0 )); then
    if grep -qE "$AUTH_FAILURE_RE" "$errlog"; then
      cloud_auth_remedy "$script_dir" "$remote"
    fi
    rm -f "$errlog"
    exit "$REFUSED_RC"
  fi
  rm -f "$errlog"

  local split
  split="$(git -C "$toplevel" log -n 1 --format=%B --grep="^$SUBTREE_DIR_TRAILER $prefix\$" HEAD \
    | sed -n "s/^$SUBTREE_SPLIT_TRAILER *//p" | head -n 1)"
  echo "  split  ${split:-unknown}"

  echo "  sync   $prefix/sync-plans.sh"
  "$toplevel/$prefix/sync-plans.sh"
  exit $?
}

main "$@"
