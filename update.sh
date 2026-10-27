#!/usr/bin/env bash
set -uo pipefail

# Pulls the latest agentTooling into a consuming repo and re-syncs plans/:
#   update.sh [--remote <url>] [--branch <name>] [--base <sha>]
#   update.sh --check [--remote <url>] [--branch <name>]
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
#   4. fetches <remote> <branch> and checks the base the pull will merge from — the
#      trailer chain (self/features/subtree-pull-keeps-base/). `git subtree pull --squash`
#      takes as its base the newest commit reachable from HEAD whose message carries
#      `git-subtree-dir: <prefix>` and a `git-subtree-split:` (latest_squash replays that
#      lookup). A forge squash-merge of a propagation PR keeps that commit only as text
#      copied into its own body, and a body that lost the text leaves the base one or more
#      pulls behind the vendored tree, so the pull conflicts on every file upstream changed
#      since. One `chain` line says which (chain_state): `intact`; `fragile` — intact, but
#      the base is a mainline commit holding copied text; `broken` — the vendored tree is a
#      newer upstream commit's than the recorded split, and the base is RE-ANCHORED there
#      (anchor) before the pull, which is refused unless the lookup then lands on the new
#      squash commit; `edited` — the vendored tree is no upstream commit's
#      (local edits), base left alone, re-anchor by hand with `--base <sha>`; `none` — no
#      commit carries the trailers. `--base <sha>` anchors at that upstream commit whatever
#      the state;
#   5. `git subtree pull --prefix=<this dir, relative to the toplevel> <remote> <branch>
#      --squash`, run from the toplevel, then prints the upstream sha the squash commit
#      records (`git-subtree-split:`) on a `split` line — what the feature's manifest
#      prose names as the sha pulled. When a fetch or the pull fails, its stderr reads as a
#      failed authentication (AUTH_FAILURE_RE), and env-profile.sh beside this script says
#      the profile is `cloud`, one `remedy` line follows git's own error: a Claude Code
#      cloud session's git proxy serves only the repositories attached to the session, so
#      the remote's GitHub repo must be attached with the `add_repo` tool
#      (claude-code-remote MCP, read access) and this script run again
#      (self/features/propagate-agenttooling-access/). No env-profile.sh beside it, or
#      the `local` profile, and nothing is added. When the pull stops on conflicts, the
#      merge is left in progress and `conflict` / `resolve` lines say how to finish it:
#      commit THAT merge, never a fresh commit after an abort;
#   6. runs the freshly pulled copy of sync-plans.sh, so the stubs and repo-owned
#      scripts are checked against whatever the pull just changed, and exits with its
#      status.
#
# `--check` runs step 1 and step 4's fetch and `chain` line, writes nothing else, and exits
# 1 on `broken` or `none` — the diagnostic a propagation round runs in each consumer.
#
# Step 5's `git subtree pull` overwrites this very file on disk while bash is still
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
# --check's verdict: the chain needs a repair this script would make, or cannot be found
CHECK_FAILED_RC=1

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
# The trailers `git subtree --squash` writes on its squash commit, and the one a rejoin adds
SUBTREE_DIR_TRAILER="git-subtree-dir:"
SUBTREE_SPLIT_TRAILER="git-subtree-split:"
SUBTREE_MAINLINE_TRAILER="git-subtree-mainline:"
# How much of a sha the human-facing lines show
SHORT_SHA_LEN=7

# The cloud remedy (step 5): the profile detector beside this script, and git's ways of
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
  echo "usage: update.sh [--remote <url>] [--branch <name>] [--base <sha>] | update.sh --check [--remote <url>] [--branch <name>]" >&2
  exit "$USAGE_RC"
}

# cloud_auth_remedy <script dir> <remote> — the one `remedy` line of step 5, printed to
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

# git_or_remedy <script dir> <remote> <git args…> — git with its stderr shown as it comes
# and kept, so a failure can be read afterwards: one that reads as a failed authentication
# adds the cloud remedy. Returns git's status.
git_or_remedy() {
  local dir="$1" remote="$2" errlog rc
  shift 2
  errlog="$(mktemp "${TMPDIR:-/tmp}/update-pull.XXXXXX")"
  { git "$@" 2>&1 1>&3 3>&- | tee "$errlog" >&2; rc=${PIPESTATUS[0]}; } 3>&1
  if (( rc != 0 )) && grep -qE "$AUTH_FAILURE_RE" "$errlog"; then
    cloud_auth_remedy "$dir" "$remote"
  fi
  rm -f "$errlog"
  return "$rc"
}

# latest_squash <toplevel> <prefix> — git subtree's own base lookup (find_latest_squash),
# replayed: the newest commit reachable from HEAD whose message names <prefix> in
# git-subtree-dir and carries a git-subtree-split. Like git subtree it reads every line of
# the message, leading blanks dropped: the last split line wins, and any mainline line marks
# a rejoin, whose squash is its second parent. Prints "<squash commit> <split sha>", or
# nothing when no commit qualifies.
latest_squash() {
  local top="$1" prefix="$2" commit body sub
  while IFS= read -r commit; do
    body="$(git -C "$top" log -n 1 --format=%B "$commit")"
    sub="$(sed -n "s/^[[:space:]]*$SUBTREE_SPLIT_TRAILER[[:space:]]*\([^[:space:]]*\).*/\1/p" <<<"$body" | tail -n 1)"
    [[ -n "$sub" ]] || continue
    if grep -q "^[[:space:]]*$SUBTREE_MAINLINE_TRAILER" <<<"$body"; then
      commit="$(git -C "$top" rev-parse -q --verify "$commit^2")" || return 0
    fi
    echo "$commit $sub"
    return 0
  done < <(git -C "$top" log --format=%H --grep="^$SUBTREE_DIR_TRAILER $prefix/*\$" HEAD)
}

# chain_state <toplevel> <prefix> <upstream tip> — prints "<state> <squash> <split> <match>"
# (step 4): intact, fragile, broken (<match> the upstream commit whose tree the vendored
# directory is), edited, or none; absent fields are `-`.
chain_state() {
  local top="$1" prefix="$2" tip="$3" found sq split vtree rtree match
  found="$(latest_squash "$top" "$prefix")"
  if [[ -z "$found" ]]; then
    echo "none - - -"
    return 0
  fi
  read -r sq split <<<"$found"
  vtree="$(git -C "$top" rev-parse -q --verify "HEAD:$prefix")"
  rtree="$(git -C "$top" rev-parse -q --verify "$split^{tree}" 2>/dev/null)"
  if [[ -n "$rtree" && "$rtree" == "$vtree" ]]; then
    # A squash commit's tree is upstream's, at the root; a mainline commit holds the prefix.
    if git -C "$top" cat-file -e "$sq:$prefix" 2>/dev/null; then
      echo "fragile $sq $split -"
    else
      echo "intact $sq $split -"
    fi
    return 0
  fi
  match="$(git -C "$top" log --format='%H %T' "$tip" | awk -v t="$vtree" '$2 == t { print $1; exit }')"
  if [[ -n "$match" ]]; then
    echo "broken $sq $split $match"
  else
    echo "edited $sq $split -"
  fi
}

# anchor <toplevel> <prefix> <upstream sha> — re-anchors git subtree's base at <sha>: a
# parentless squash commit holding <sha>'s tree, its trailers in a closing trailer block,
# joined to the branch by an `ours` merge that changes no file. The next pull's base lookup
# finds that squash commit, as it finds any; the merge's own message carries no trailer
# line, since a mainline one would send git subtree to a second parent that a forge
# squash-merge never keeps. A squash-merge that keeps commit bodies keeps the trailer block.
anchor() {
  local top="$1" prefix="$2" sha="$3" sq
  sq="$(git -C "$top" commit-tree "$sha^{tree}" \
    -m "Squashed '$prefix/' content from commit ${sha:0:$SHORT_SHA_LEN}" \
    -m "$SUBTREE_DIR_TRAILER $prefix
$SUBTREE_SPLIT_TRAILER $sha")" || return 1
  git -C "$top" merge -q --no-ff -s ours --allow-unrelated-histories \
    -m "Re-anchor the '$prefix/' subtree at upstream ${sha:0:$SHORT_SHA_LEN}" \
    -m "The vendored tree already matches that commit; this records it as the base the next subtree pull merges from (agentTooling update.sh, self/features/subtree-pull-keeps-base/). No file changes." \
    "$sq" || return 1
  echo "$sq"
}

main() {
  local remote="$DEFAULT_REMOTE" branch="$DEFAULT_BRANCH" base="" check=0
  while (( $# )); do
    # Every value-taking flag checks its arity first: with no set -e here, a truncated
    # flag would otherwise spin this loop forever instead of printing the usage.
    case "$1" in
      --remote) (( $# >= 2 )) || usage; remote="$2"; shift 2 ;;
      --branch) (( $# >= 2 )) || usage; branch="$2"; shift 2 ;;
      --base) (( $# >= 2 )) || usage; base="$2"; shift 2 ;;
      --check) check=1; shift ;;
      *) usage ;;
    esac
  done
  if (( check )) && [[ -n "$base" ]]; then
    usage
  fi

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

  local current=""
  if (( ! check )); then
    local start_hint="start the pull as its own feature first — from the primary checkout, agentTooling/feature-start.sh $PULL_SLUG_PATTERN --method hand — then run this script as that worktree's copy (LIFECYCLE.md -> \"Propagate\")"
    local manifest feature
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
  fi

  # Step 4: the base check reads upstream's history, so fetch it first (the pull fetches
  # again on its own).
  git_or_remedy "$script_dir" "$remote" -C "$toplevel" fetch -q "$remote" "$branch" || exit "$REFUSED_RC"
  local tip state sq recorded match
  tip="$(git -C "$toplevel" rev-parse FETCH_HEAD)"
  read -r state sq recorded match <<<"$(chain_state "$toplevel" "$prefix" "$tip")"
  case "$state" in
    intact)  echo "  chain  intact — base ${sq:0:$SHORT_SHA_LEN} records split ${recorded:0:$SHORT_SHA_LEN}, the vendored tree's" ;;
    fragile) echo "  chain  fragile — base ${sq:0:$SHORT_SHA_LEN} is a mainline commit whose message holds trailers copied by a squash-merge; the pull works from that text alone (merge propagation PRs with a merge commit, README.md -> \"Updating\")" ;;
    broken)  echo "  chain  broken — base ${sq:0:$SHORT_SHA_LEN} records split ${recorded:0:$SHORT_SHA_LEN}, but $prefix/ is upstream ${match:0:$SHORT_SHA_LEN}'s tree; a pull from the stale base conflicts on whatever upstream changed in between" ;;
    edited)  echo "  chain  edited — $prefix/ matches no upstream commit (local edits under it); base ${sq:0:$SHORT_SHA_LEN} at split ${recorded:0:$SHORT_SHA_LEN} is left as it is; --base <sha> re-anchors at an upstream commit by hand" ;;
    none)    echo "  chain  none — no commit reachable from HEAD carries $SUBTREE_DIR_TRAILER $prefix with a split; git subtree cannot pull a prefix it never added" ;;
  esac

  if (( check )); then
    case "$state" in
      broken|none) exit "$CHECK_FAILED_RC" ;;
      *) exit 0 ;;
    esac
  fi

  local anchor_at=""
  if [[ -n "$base" ]]; then
    anchor_at="$(git -C "$toplevel" rev-parse -q --verify "$base^{commit}")"
    if [[ -z "$anchor_at" ]] || ! git -C "$toplevel" merge-base --is-ancestor "$anchor_at" "$tip"; then
      echo "  refused  --base $base is not a commit in $remote $branch's history" >&2
      exit "$REFUSED_RC"
    fi
  elif [[ "$state" == broken ]]; then
    anchor_at="$match"
  fi
  if [[ -n "$anchor_at" ]]; then
    local anchored found
    anchored="$(anchor "$toplevel" "$prefix" "$anchor_at")" || {
      echo "  refused  could not re-anchor $prefix/ at ${anchor_at:0:$SHORT_SHA_LEN}" >&2
      exit "$REFUSED_RC"
    }
    # The base lookup walks commits by date, so make sure it now lands on the new squash
    # commit — an older trailer-bearing commit dated at or after it (clock skew) would not.
    found="$(latest_squash "$toplevel" "$prefix")"
    if [[ "${found%% *}" != "$anchored" ]]; then
      echo "  refused  re-anchored $prefix/ at ${anchor_at:0:$SHORT_SHA_LEN}, but git subtree's base lookup still finds ${found%% *}; the pull would merge from that — not pulling (README.md -> \"Updating\")" >&2
      exit "$REFUSED_RC"
    fi
    echo "  anchor $prefix/ re-anchored at upstream ${anchor_at:0:$SHORT_SHA_LEN} (one no-change merge commit on $current)"
  fi

  echo "  pull   $prefix <- $remote $branch  (on $current, feature $feature)"
  if ! git_or_remedy "$script_dir" "$remote" -C "$toplevel" subtree pull --prefix="$prefix" "$remote" "$branch" --squash; then
    if git -C "$toplevel" rev-parse -q --verify MERGE_HEAD >/dev/null; then
      echo "  conflict  the subtree merge stopped on conflicts and is still in progress — MERGE_HEAD is the squash commit carrying the trailers the next pull's base is found by:" >&2
      git -C "$toplevel" diff --name-only --diff-filter=U | sed 's/^/            /' >&2
      echo "  resolve   with no local edits under $prefix/, take upstream's whole tree — git rm -r -q -- $prefix, then git read-tree --prefix=$prefix/ -u MERGE_HEAD, then git commit (a file upstream deleted goes too, which a per-file --theirs cannot do) — commit THIS merge, never a fresh commit after git merge --abort; then run $prefix/sync-plans.sh (LIFECYCLE.md -> \"Propagate\")" >&2
    fi
    exit "$REFUSED_RC"
  fi

  local split
  split="$(latest_squash "$toplevel" "$prefix")"
  split="${split#* }"
  echo "  split  ${split:-unknown}"

  echo "  sync   $prefix/sync-plans.sh"
  "$toplevel/$prefix/sync-plans.sh"
  exit $?
}

main "$@"
