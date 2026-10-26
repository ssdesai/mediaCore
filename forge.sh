#!/usr/bin/env bash
set -uo pipefail

# The forge adapter: forge.sh <verb> <args…>
#
#   forge.sh pr-find <head>                             the open PR whose head is <head>:
#                                                       prints its html_url, or nothing
#   forge.sh pr-open <head> <base> <title> <body-file>  opens one: prints its html_url
#   forge.sh auto-merge <pr-url>                        asks the forge to merge that PR
#                                                       once its checks pass: prints the url
#   forge.sh reachable                                  whether the forge answers: prints
#                                                       `reachable <o>/<r>`
#
# The one piece of agentTooling that talks to the forge (self/DESIGN-2026-10-05-cloud-
# execution.md §5). It is called by a repo's `pr.sh` (template-version 6), which keeps its
# repo-owned shell — the commit, the push, the "already open" line — and hands the forge
# part here: `pr-find`, and `pr-open` when that finds nothing; and, on the merge request,
# `pr-find` then `auto-merge`. A non-GitHub repo keeps its own forge code in `pr.sh` and
# never calls this.
#
# It is an ADAPTER (design §1): it sources env-profile.sh, and two verbs differ by profile.
# Find and open share one REST path everywhere:
#
#   pr-find     GET  /repos/{o}/{r}/pulls?head={o}:{head}&state=open   → .[0].html_url
#   pr-open     POST /repos/{o}/{r}/pulls  head, base, title, body     → .html_url
#   auto-merge  local: gh pr merge <url> --auto --merge --delete-branch
#               cloud: PUT /repos/{o}/{r}/pulls/{n}/ccr/auto_merge  merge_method=merge
#   reachable   local: gh auth status
#               cloud: GET /repos/{o}/{r}
#
# In the cloud: never `gh pr …` (GraphQL, which the proxy refuses), never `gh auth status`
# (the proxy's placeholder token fails it while REST works — the probe that made an old
# pr.sh skip with exit 0 and the close stamp `pr_opened` with no url), never GraphQL by
# any other spelling; `ccr/auto_merge` is the proxy's own REST route for the one thing
# GraphQL did. Locally the two GraphQL-backed calls are what `gh` does best and what pr.sh
# did before. A merge COMMIT, never a squash, in both: feature-start.sh's prune and
# feature-capture.sh's post-merge path decide "merged" by the branch being an ancestor of
# main, which a squash never makes it. The cloud body field is `merge_method` (the REST
# spelling of GitHub's own merge endpoint) — chosen, not yet seen answered by the live
# route (self/features/execution-profiles/NOTES.md ruling 19). Every value travels as its
# own argv word: the head, base, title and merge method as `-f key=value`, the body as
# `-F body=@<file>`, read by gh from the file and never by a shell, and the responses are
# parsed by gh's own `--jq`.
#
# {o}/{r} come from the origin of the checkout this copy lives in — `remote.origin.url`
# as configured, read raw: `url.<x>.insteadOf` is a transport rewrite and does not change
# which repository the forge knows it as. https (with or without `.git`, with or without a
# user or port), ssh:// and scp-style `git@host:o/r(.git)` are read; the last two path
# segments are the owner and the repository, so a proxied `http://…/git/o/r` reads as o/r
# too. Anything else — a local path, `file://`, no origin at all — is refused before any
# forge call.
#
# Depends on (README.md Rule 2, none of it visible from a call site):
#   - env-profile.sh beside this file, which decides `local` or `cloud`;
#   - the origin URL above, in the checkout holding this file (a vendored copy's is the
#     consuming repo's, since a vendored agentTooling/ has no .git of its own);
#   - `gh` on PATH, with credentials that reach the REST API: a token locally, the proxy's
#     injected credentials in a Claude Code cloud container. Which host it talks to is
#     gh's own (GH_HOST, default github.com); the origin's host is not passed.
#
# Exit codes: 0 success — and only pr-find may print nothing on it; 1 failure (a profile
# that is neither local nor cloud, an origin that names no repository, `gh` missing, a
# call that failed, a response with no url, a body file that is not there, a PR url with
# no number), with one line on stderr saying which; 2 usage.

USAGE_RC=2
FAILED_RC=1
FORGE_SCRIPT_NAME="forge.sh"
FORGE_CLI="gh"
ORIGIN_REMOTE="origin"
PULL_STATE_OPEN="open"
# What gh's --jq takes out of each response: the first open PR's url (nothing when the
# list is empty), and the created PR's url.
FIND_URL_JQ='.[0].html_url // empty'
OPEN_URL_JQ='.html_url // empty'
# One owner or repository path segment, as GitHub spells them.
REPO_SEGMENT_RE='^[A-Za-z0-9._-]+$'
GIT_SUFFIX=".git"
# auto-merge: a PR url ends in its number (…/pull/<n>); the local call's flags; the
# proxy's route under a PR, and the merge method it is sent — a merge commit, never squash.
PR_NUMBER_RE='^[0-9]+$'
LOCAL_AUTO_MERGE_ARGS=(--auto --merge --delete-branch)
CLOUD_AUTO_MERGE_ROUTE="ccr/auto_merge"
CLOUD_MERGE_METHOD_FIELD="merge_method"
CLOUD_MERGE_METHOD="merge"
# reachable: what the cloud's REST probe takes out of the repository it fetched.
REACHABLE_JQ='.full_name // empty'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env-profile.sh"

usage() {
  echo "usage: $FORGE_SCRIPT_NAME pr-find <head>" >&2
  echo "       $FORGE_SCRIPT_NAME pr-open <head> <base> <title> <body-file>" >&2
  echo "       $FORGE_SCRIPT_NAME auto-merge <pr-url>" >&2
  echo "       $FORGE_SCRIPT_NAME reachable" >&2
  exit "$USAGE_RC"
}
fail() { echo "  forge     $*" >&2; exit "$FAILED_RC"; }

# origin_url — remote.origin.url of the checkout this copy lives in, as configured.
origin_url() { git -C "$SCRIPT_DIR" config --get "remote.$ORIGIN_REMOTE.url" 2>/dev/null; }

# repo_of <url> — "<owner>/<repo>" for a forge URL, or nothing for anything else.
repo_of() {
  local url="$1" rest path owner repo
  case "$url" in
    https://*|http://*|ssh://*|git://*)
      rest="${url#*://}"
      if [[ "$rest" != */* ]]; then return 0; fi
      path="${rest#*/}" ;;
    *://*) return 0 ;;
    *@*:*) path="${url#*:}" ;;
    *) return 0 ;;
  esac
  path="${path%/}"
  path="${path%"$GIT_SUFFIX"}"
  if [[ "$path" != */* ]]; then return 0; fi
  repo="${path##*/}"
  owner="${path%/*}"
  owner="${owner##*/}"
  if [[ "$owner" =~ $REPO_SEGMENT_RE && "$repo" =~ $REPO_SEGMENT_RE ]]; then
    echo "$owner/$repo"
  fi
}

VERB="${1:-}"
if (( $# > 0 )); then shift; fi
case "$VERB" in
  pr-find)
    if (( $# != 1 )) || [[ -z "$1" ]]; then usage; fi ;;
  pr-open)
    if (( $# != 4 )) || [[ -z "$1" || -z "$2" || -z "$3" || -z "$4" ]]; then usage; fi ;;
  auto-merge)
    if (( $# != 1 )) || [[ -z "$1" ]]; then usage; fi ;;
  reachable)
    if (( $# != 0 )); then usage; fi ;;
  *) usage ;;
esac

if ! profile_why="$(profile_check)"; then
  fail "$profile_why — nothing was asked of the forge"
fi

ORIGIN_URL="$(origin_url)"
REPO="$(repo_of "$ORIGIN_URL")"
if [[ -z "$REPO" ]]; then
  fail "the origin of $SCRIPT_DIR (${ORIGIN_URL:-none configured}) names no forge repository <owner>/<repo> — nothing was asked of the forge"
fi
OWNER="${REPO%%/*}"
PULLS_ENDPOINT="repos/$REPO/pulls"
if ! command -v "$FORGE_CLI" >/dev/null 2>&1; then
  fail "$FORGE_CLI is not installed — nothing was asked of the forge"
fi

case "$VERB" in
  pr-find)
    HEAD_BRANCH="$1"
    if ! FOUND="$("$FORGE_CLI" api -X GET "$PULLS_ENDPOINT" \
        -f "head=$OWNER:$HEAD_BRANCH" -f "state=$PULL_STATE_OPEN" --jq "$FIND_URL_JQ")"; then
      fail "GET $PULLS_ENDPOINT (head $OWNER:$HEAD_BRANCH) failed — see $FORGE_CLI's message above"
    fi
    if [[ -n "$FOUND" ]]; then printf '%s\n' "$FOUND" | head -n 1; fi
    ;;
  pr-open)
    HEAD_BRANCH="$1"; BASE_BRANCH="$2"; TITLE="$3"; BODY_FILE="$4"
    if [[ ! -f "$BODY_FILE" || ! -r "$BODY_FILE" ]]; then
      fail "no readable body file at $BODY_FILE — nothing was asked of the forge"
    fi
    if ! OPENED="$("$FORGE_CLI" api -X POST "$PULLS_ENDPOINT" \
        -f "head=$HEAD_BRANCH" -f "base=$BASE_BRANCH" -f "title=$TITLE" \
        -F "body=@$BODY_FILE" --jq "$OPEN_URL_JQ")"; then
      fail "POST $PULLS_ENDPOINT ($HEAD_BRANCH into $BASE_BRANCH) failed — see $FORGE_CLI's message above; no PR was opened"
    fi
    if [[ -z "$OPENED" ]]; then
      fail "POST $PULLS_ENDPOINT answered with no html_url — treat the PR as not opened, and look on the forge"
    fi
    printf '%s\n' "$OPENED" | head -n 1
    ;;
  auto-merge)
    PR_URL="$1"
    PR_NUMBER="${PR_URL%/}"
    PR_NUMBER="${PR_NUMBER##*/}"
    if [[ ! "$PR_NUMBER" =~ $PR_NUMBER_RE ]]; then
      fail "$PR_URL does not end in a PR number — nothing was asked of the forge"
    fi
    if profile_is_cloud; then
      MERGE_ENDPOINT="$PULLS_ENDPOINT/$PR_NUMBER/$CLOUD_AUTO_MERGE_ROUTE"
      if ! "$FORGE_CLI" api -X PUT "$MERGE_ENDPOINT" \
          -f "$CLOUD_MERGE_METHOD_FIELD=$CLOUD_MERGE_METHOD" >/dev/null; then
        fail "PUT $MERGE_ENDPOINT failed — see $FORGE_CLI's message above; no merge was requested"
      fi
    else
      if ! "$FORGE_CLI" pr merge "$PR_URL" "${LOCAL_AUTO_MERGE_ARGS[@]}" >/dev/null; then
        fail "$FORGE_CLI pr merge $PR_URL ${LOCAL_AUTO_MERGE_ARGS[*]} failed — see its message above; no merge was requested"
      fi
    fi
    printf '%s\n' "$PR_URL"
    ;;
  reachable)
    if profile_is_cloud; then
      if ! "$FORGE_CLI" api "repos/$REPO" --jq "$REACHABLE_JQ" >/dev/null; then
        fail "GET repos/$REPO failed — the forge is not reachable from here"
      fi
    else
      if ! "$FORGE_CLI" auth status >/dev/null 2>&1; then
        fail "$FORGE_CLI auth status failed — run '$FORGE_CLI auth login'"
      fi
    fi
    echo "reachable $REPO"
    ;;
esac
exit 0
