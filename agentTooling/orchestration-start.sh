#!/usr/bin/env bash
set -uo pipefail

# Start an orchestration record:
#   orchestration-start.sh [--self] <slug> [--session <id>] [--coordinator] [--from <instant>]
#                          [--branch <name>]
#
# A record lives in the corpus of the checkout it was started in, as a feature does
# (self/features/orchestration-records-in-repo/): the consuming repo's
# `plans/orchestrations/<slug>/` by default, agentTooling's own `self/orchestrations/<slug>/`
# under `--self`. A slug that exists only at the old vendored place,
# `agentTooling/self/orchestrations/<slug>` AND is the consuming repo's own (its last fence
# lists a feature of that repo: `roots.is_stranded_record`) is refused with the `git mv` that
# moves it; agentTooling's own shipped records there block nothing. Without `--self` in
# agentTooling's own checkout (no consuming repo above it) the start is refused, naming `--self`;
# WITH `--self` in a copy vendored in a consuming repo it is refused too, before any write,
# naming `plans/orchestrations/<slug>/` (roots.py's `record_write_refusal`;
# self/features/consumer-record-guard/).
#
# `--coordinator` writes a COORDINATOR record instead (self/features/coordinator-cost-records/):
# the fence gains `"kind": "coordinator"`, which is a cost record and never a role —
# hooks/orchestrator_role.py skips it, so neither the session nor the delegates that share
# its session id are refused anything. It is for a session that coordinates several features
# by delegating each to an Agent subagent (ORCHESTRATION.md → "Coordinator shapes"): its
# delegates are claimed by the features they built, and its own transcript is the one line
# this record prices. Registering one is allowed at any time — live, or retroactively with
# `--session <id>` from any session — and the reverse guard below does not apply to it.
# Under `--coordinator` the window's `from` defaults to the session's first transcript
# instant (`manifest.py session-start`), the clock when no transcript is found; `--from`
# overrides it in either kind.
#
# An orchestrator session spawns one implementer session per feature and builds nothing
# itself. This writes the record of that group — `<orchestrations>/<slug>/README.md`,
# an opening paragraph and a JSON fence — so the cost of the group (the orchestrator's own
# transcript plus every feature it spawned) can be read together:
#
#   orchestration-start.sh [--self] <slug>
#   python3 analysis/manifest.py [--self] --orchestration <slug> add-feature repo=R slug=S …
#   orchestration-capture.sh [--self] <slug>
#   python3 analysis/report.py [--self] --orchestration <slug>
#
# The fence (analysis/README.md → manifest.py, "the orchestration record"):
#
#   slug           the record's slug
#   session        the orchestrator's session id: `--session`, else $CLAUDE_CODE_SESSION_ID —
#                  the way feature-start.sh learns the current session
#   agent_tooling  `git rev-parse HEAD` of this checkout, or null when it is not a git
#                  checkout of its own (a vendored copy has no .git to ask) — the version an
#                  experiment comparing two agentTooling versions at the orchestrator level
#                  pins the run to
#   session_window {from: now, to: null} — `manifest.py --orchestration <slug> set-window-to
#                  now` closes it
#   features       empty; `manifest.py --orchestration <slug> add-feature` fills it
#
# It refuses a slug that fails the pattern, an existing record, a run with no session id,
# and a session id outside SESSION_PATTERN (it is written into the fence unescaped). Outside
# `--branch` it commits nothing: the orchestrator commits its record, and nothing else, on
# its assigned branch, as a records-only PR (the README's prose says so).
#
# **The orchestrator's branch** (self/features/orchestration-start-branch-v2/). A cloud
# session created with no branch comes up on a detached HEAD (or `main`), and once its record
# exists its Bash allowlist holds no `git checkout -b`. So under the cloud profile an
# orchestrator record (never a `--coordinator` one) in a git checkout is refused on a detached
# HEAD or on `main` without `--branch <name>`, the refusal naming `--branch claude/<slug>` —
# the convention feature-start.sh's own cloud refusal names. Given `--branch`, the start cuts
# that branch off `origin/main` BEFORE it writes the record, the way feature-start.sh does,
# then commits the record on it (the record only) and pushes it as a checkpoint (advisory).
# Before anything is written it refuses:
#   - a branch of that name that exists locally, or on origin — asked of ORIGIN with
#     `git ls-remote --exit-code --heads origin refs/heads/<name>`, never the local
#     remote-tracking cache (a single-branch clone, a refspec mapping `claude/*` elsewhere and
#     a failed fetch all leave that cache silent): exit 0 refuses, exit 2 goes on, any other
#     exit refuses ("cannot ask origin");
#   - a branch a tracked feature manifest on `origin/main` names as its `branches[0]` (a
#     merged feature whose branch origin has since deleted), in agentTooling's own corpus and,
#     from a vendored copy, the consuming repo's;
#   - a checkout carrying commits not on `origin/main`, or uncommitted changes — somebody's
#     work, which a branch cut off `origin/main` would leave behind;
#   - `--branch` on another branch than the one named (it cuts from a detached HEAD or `main`
#     only, and switches to no existing branch), a `--branch` that is not `claude/<slug>`
#     with a slug matching the shared SLUG_PATTERN (`main`, `+main`, `origin/main` and every
#     other ref's spelling with it), and `--branch` under the local profile, where the human
#     creates branches.
# An unmerged feature's manifest is not read off origin's `claude/*` branches: every pushed one
# is already refused by the ls-remote above, and an unpushed one exists only in its own
# container (the feature's NOTES.md). On an assigned branch that is not `main`, with no
# `--branch`, nothing changes: the record is written there and committed by the orchestrator.
#
# Exit codes: 2 usage; 1 any refusal.

USAGE_RC=2
REFUSED_RC=1
# The rules this script shares with the hook and analysis/ — where records live (`--self`
# relative to this script, otherwise relative to the consuming repo's root), the record's file
# name, the `.git` entry that marks a standalone checkout, a coordinator record's `kind`, the
# orchestrator ledger's name, the slug pattern, and the refusal for a slug found only at the
# old vendored place and for a no-`--self` start in agentTooling's own checkout — are READ
# from their one definition, hooks/shared_rules.py, never restated here
# (self/features/shared-hook-rules/): one `python3 -B` call prints the values below in order.
# A script that cannot read them refuses, naming the module; there is no literal to fall back to.
SHARED_RULES_MODULE="hooks/shared_rules.py"
SHARED_RULES_NAMES=(ORCHESTRATIONS_SELF_REL ORCHESTRATIONS_CONSUMER_REL RECORD_NAME GIT_ENTRY
  KIND_COORDINATOR LEDGER_NAME SLUG_PATTERN LEGACY_RECORD_REFUSAL STANDALONE_REFUSAL)
# The refusal's `{slug}` placeholder, filled with the slug
LEGACY_SLUG_PLACEHOLDER='{slug}'
# ... but only a STRANDED one (the consuming repo's own, by its last fence's features): the
# classifier is analysis/roots.py's `is_stranded_record`, asked through `roots.py stranded`.
# A vendored record that is not stranded is agentTooling's own and blocks nothing.
STRANDED_CLASSIFIER="analysis/roots.py"
STRANDED_ARGV="stranded"
# Under --self, a copy vendored in a consuming repo writes no record into its own
# self/orchestrations/ (self/features/consumer-record-guard/): the decision is roots.py's
# `record_write_refusal`, asked through `roots.py self-write <slug>` — exit 0 to write, else
# its refusal text. Any other outcome, a crash included, refuses: the check fails closed.
SELF_WRITE_ARGV="self-write"
SELF_WRITE_OK_RC=0
UTC_STAMP_FORMAT='+%Y-%m-%dT%H:%M:%SZ'
# An instant `--from` accepts: ISO 8601 UTC, to the second or finer, ending in Z
FROM_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$'
# A session id the fence may carry (self/features/hook-role-hardening/, F2): it is written
# into the JSON unescaped, so anything that could close the string — a quote, a backslash,
# a newline — or a glob is refused rather than quoted. Every id Claude Code issues (a UUID,
# a `session_…` id) fits.
# Its first character is no dash (security audit round 1, F13: `--session --reason` used to
# pass and be eaten as a flag by a reader), and it is capped in length.
SESSION_PATTERN='^[A-Za-z0-9_][A-Za-z0-9_-]*$'
SESSION_MAX_CHARS=128
# The orchestrator ledger under the git common dir (LEDGER_NAME, read from the shared rules;
# self/features/hook-role-hardening/): `<session> <slug>`, appended for an orchestrator
# record only, never a coordinator one.
# The manifest.py slug argparse needs before `session-start` (it reads no manifest)
SESSION_START_SLUG="orchestration-start"

# The script's own directory with every symlink resolved, before anything is sourced from it
# (security audit round 4): a link to this script placed elsewhere must not make it source a
# library planted beside the link.
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  SCRIPT_LINK="$(readlink "$SCRIPT_PATH")"
  if [[ "$SCRIPT_LINK" == /* ]]; then SCRIPT_PATH="$SCRIPT_LINK"; else SCRIPT_PATH="$(dirname "$SCRIPT_PATH")/$SCRIPT_LINK"; fi
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
# manifest_branch and manifest_field, for the reverse guard below
source "$SCRIPT_DIR/plan-runner-roots.sh"

# The reverse guard (self/features/orchestrator-role-guard/): the record this writes makes
# the session an orchestrator, which builds nothing, so a session that already holds a
# feature — its branch is a tracked manifest's branches[0], or its id is in that manifest's
# `sessions` — cannot become one mid-feature. The corpora it reads: agentTooling's own
# (relative to this copy) and, when this copy is vendored, the consuming repo's.
SELF_FEATURES_LABEL="self/features"
CONSUMER_FEATURES_LABEL="plans/features"
MANIFEST_NAME="README.md"

# The orchestrator's branch (header): cut off origin/<base> under the cloud profile
BASE_BRANCH="main"
ORIGIN_REMOTE="origin"
# The conventional cloud branch for slug S, the name the refusal offers (feature-start.sh's
# CLOUD_BRANCH_PREFIX, ORCHESTRATION.md → "Cloud sessions")
CLOUD_BRANCH_PREFIX="claude/"
# A `--branch` the start takes is exactly CLOUD_BRANCH_PREFIX followed by a slug (the shared
# SLUG_PATTERN), and nothing else (owner ruling, round 4). Patching spellings one at a time
# failed three audits running: `+main` was a force-push refspec (round 2), `origin/main` a
# local branch that shadows the remote-tracking ref (round 3). A `claude/<slug>` name can be
# neither, nor `main`, nor any other ref's spelling.
# `git ls-remote --exit-code`: 0 a matching ref exists, 2 none does; anything else is no answer
LS_REMOTE_FOUND_RC=0
LS_REMOTE_ABSENT_RC=2
# The record's commit on the cut branch: `orchestration <slug>: start`
START_COMMIT_LEAD="orchestration "
START_COMMIT_TAIL=": start"
# The profile adapter, beside this script; without it the cloud rule cannot be decided
PROFILE_ADAPTER="env-profile.sh"

usage() {
  echo "usage: orchestration-start.sh [--self] <slug> [--session <id>] [--coordinator] [--from <instant>] [--branch <name>]" >&2
  exit "$USAGE_RC"
}
refuse() {
  echo "  refused  $*" >&2
  exit "$REFUSED_RC"
}

# REPO_DIR, SELF_MODE and SELF_ARG, from the same resolver every lifecycle script uses
resolve_roots "${1:-}"
if [[ "${1:-}" == "--self" ]]; then shift; fi
SLUG="${1:-}"; [[ -n "$SLUG" ]] || usage; shift
SESSION_OPT=""; COORDINATOR=0; FROM_OPT=""; BRANCH_OPT=""; BRANCH_GIVEN=0
while (( $# )); do
  case "$1" in
    --session) (( $# >= 2 )) || usage; SESSION_OPT="$2"; shift 2 ;;
    --branch) (( $# >= 2 )) || usage; BRANCH_OPT="$2"; BRANCH_GIVEN=1; shift 2 ;;
    --coordinator) COORDINATOR=1; shift ;;
    --from) (( $# >= 2 )) || usage; FROM_OPT="$2"; shift 2 ;;
    *) usage ;;
  esac
done
# The shared rules, each into the shell variable of its own name (printf -v: no eval of what the
# module printed). The count is the check: a missing, broken or refusing module prints fewer
# values than were asked for, and so does one that prints an empty line.
shared_index=0
while IFS= read -r shared_value; do
  [[ -n "$shared_value" && $shared_index -lt ${#SHARED_RULES_NAMES[@]} ]] || break
  printf -v "${SHARED_RULES_NAMES[$shared_index]}" '%s' "$shared_value"
  shared_index=$((shared_index + 1))
done < <(python3 -B "$SCRIPT_DIR/$SHARED_RULES_MODULE" "${SHARED_RULES_NAMES[@]}" 2>/dev/null)
(( shared_index == ${#SHARED_RULES_NAMES[@]} )) \
  || refuse "cannot read the shared rules (python3 -B $SHARED_RULES_MODULE ${SHARED_RULES_NAMES[*]}) — $SHARED_RULES_MODULE is missing or broken, so nothing is written"
# A standalone checkout (a .git of its own — a directory in a clone, a file in a linked
# worktree) has no consuming repo — without --self the record would land in its parent,
# outside any repo. The test is the entry's presence, as roots.py's is_standalone_checkout and
# hooks/orchestrator_role.py's record_roots make it: comparing `rev-parse --show-toplevel`
# (symlinks resolved) with SCRIPT_DIR (`pwd`, not resolved) misses a checkout reached through
# a symlink, and the start would then write into the parent.
TOPLEVEL="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
if (( ! SELF_MODE )) && [[ -e "$SCRIPT_DIR/$GIT_ENTRY" ]]; then
  refuse "$STANDALONE_REFUSAL"
fi
[[ "$SLUG" =~ $SLUG_PATTERN ]] || refuse "slug '$SLUG' must match $SLUG_PATTERN — kebab-case, no slash, no prefix"
if (( SELF_MODE )); then
  SELF_WRITE_TEXT="$(python3 -B "$SCRIPT_DIR/$STRANDED_CLASSIFIER" "$SELF_WRITE_ARGV" "$SLUG" 2>/dev/null)"
  SELF_WRITE_RC=$?
  if (( SELF_WRITE_RC != SELF_WRITE_OK_RC )); then
    refuse "${SELF_WRITE_TEXT:-cannot ask $STRANDED_CLASSIFIER whether a --self record may be written here (exit $SELF_WRITE_RC), so nothing is written}"
  fi
fi
SESSION="${SESSION_OPT:-${CLAUDE_CODE_SESSION_ID:-}}"
[[ -n "$SESSION" ]] || refuse "no session id: \$CLAUDE_CODE_SESSION_ID is unset and --session was not given"
[[ "$SESSION" =~ $SESSION_PATTERN && ${#SESSION} -le $SESSION_MAX_CHARS ]] \
  || refuse "session id '${SESSION:0:$SESSION_MAX_CHARS}' must match $SESSION_PATTERN and be at most $SESSION_MAX_CHARS characters — letters, digits, '_' and '-', not starting with '-'"
[[ -z "$FROM_OPT" || "$FROM_OPT" =~ $FROM_PATTERN ]] || refuse "--from '$FROM_OPT' must be a UTC instant ending in Z (e.g. 2026-11-05T16:39:00Z)"

if (( SELF_MODE )); then
  ORCHESTRATIONS_REL="$ORCHESTRATIONS_SELF_REL"
  FOLDER="$SCRIPT_DIR/$ORCHESTRATIONS_REL/$SLUG"
else
  ORCHESTRATIONS_REL="$ORCHESTRATIONS_CONSUMER_REL"
  FOLDER="$REPO_DIR/$ORCHESTRATIONS_REL/$SLUG"
fi
[[ ! -e "$FOLDER" ]] || refuse "$FOLDER already exists — a record is started once; edit it with analysis/manifest.py ${SELF_ARG}--orchestration $SLUG"
if (( ! SELF_MODE )) && [[ -e "$SCRIPT_DIR/$ORCHESTRATIONS_SELF_REL/$SLUG" ]] \
    && python3 -B "$SCRIPT_DIR/$STRANDED_CLASSIFIER" "$STRANDED_ARGV" "$SLUG"; then
  refuse "${LEGACY_RECORD_REFUSAL//$LEGACY_SLUG_PLACEHOLDER/$SLUG}"
fi

# held_feature <checkout-dir> <features-label> <branch> <session> — the first TRACKED manifest
# under <checkout-dir>/<features-label>/<slug>/README.md that names this branch as its
# branches[0] or this session among its `sessions`: prints `<slug> <label>/<slug>/README.md
# <what it matched>`, or nothing. NUL-separated (`ls-files -z`): without it git C-quotes a path
# holding a non-ASCII byte, a tab or a quote, and the quoted line names no file, so that
# manifest was silently skipped (self/features/orchestration-start-branch-v2/).
held_feature() {
  local dir="$1" label="$2" branch="$3" session="$4" rel slug path
  while IFS= read -r -d '' rel; do
    slug="${rel#"$label"/}"; slug="${slug%/"$MANIFEST_NAME"}"
    [[ "$slug" != */* ]] || continue
    path="$dir/$rel"
    if [[ -n "$branch" && "$(manifest_branch "$path" "$slug")" == "$branch" ]]; then
      echo "$slug $rel on this branch"; return 0
    fi
    if [[ "$(manifest_field "$path" sessions | jq -r --arg s "$session" 'if type == "array" and index($s) != null then "yes" else empty end' 2>/dev/null)" == "yes" ]]; then
      echo "$slug $rel naming this session"; return 0
    fi
  done < <(git -C "$dir" ls-files -z -- "$label/*/$MANIFEST_NAME" 2>/dev/null)
}

# branch_named_at <dir> <label> <ref> <branch> — the first manifest tracked at <ref> under
# <dir>/<label>/<slug>/README.md whose branches[0] is <branch>: prints `<label>/<slug>/README.md`,
# or nothing. NUL-separated (`ls-tree -z`), for the reason held_feature is. Each manifest is
# read through `git show <ref>:./<path>` into a scratch file manifest_branch can read.
branch_named_at() {
  local dir="$1" label="$2" ref="$3" branch="$4" rel slug scratch found=""
  scratch="$(mktemp)" || return 0
  while IFS= read -r -d '' rel; do
    slug="${rel#"$label"/}"; slug="${slug%/"$MANIFEST_NAME"}"
    [[ "$rel" == "$label/$slug/$MANIFEST_NAME" && "$slug" != */* ]] || continue
    git -C "$dir" show "$ref:./$rel" > "$scratch" 2>/dev/null || continue
    if [[ "$(manifest_branch "$scratch" "")" == "$branch" ]]; then found="$rel"; break; fi
  done < <(git -C "$dir" ls-tree -r -z --name-only "$ref" -- "$label" 2>/dev/null)
  rm -f "$scratch"
  [[ -z "$found" ]] || echo "$found"
}
# Not for a coordinator record: it is no role, so it cannot stop a feature this checkout
# holds from being built — and the coordinator's delegates are exactly the sessions that
# hold features under its session id.
if [[ -n "$TOPLEVEL" ]] && (( ! COORDINATOR )); then
  CURRENT_BRANCH="$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null)"
  HELD="$(held_feature "$SCRIPT_DIR" "$SELF_FEATURES_LABEL" "$CURRENT_BRANCH" "$SESSION")"
  if [[ -z "$HELD" && "$TOPLEVEL" != "$SCRIPT_DIR" ]]; then
    HELD="$(held_feature "$TOPLEVEL" "$CONSUMER_FEATURES_LABEL" "$CURRENT_BRANCH" "$SESSION")"
  fi
  if [[ -n "$HELD" ]]; then
    HELD_SLUG="${HELD%% *}"; HELD_REST="${HELD#* }"
    HELD_PATH="${HELD_REST%% *}"; HELD_HOW="${HELD_REST#* }"
    refuse "this checkout holds the feature \`$HELD_SLUG\` (\`$HELD_PATH\`) $HELD_HOW — a coordinator cannot become an orchestrator mid-feature: start the orchestration in a session of its own"
  fi
fi

# `.git` is a directory in a standalone clone and a file in a linked worktree; a vendored
# copy has neither of its own, and `git -C` there would answer with the consuming repo's HEAD.
AGENT_TOOLING="null"
if [[ -e "$SCRIPT_DIR/$GIT_ENTRY" ]]; then
  head_id="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)"
  if [[ -n "$head_id" ]]; then AGENT_TOOLING="\"$head_id\""; fi
fi
NOW="$(date -u "$UTC_STAMP_FORMAT")"
WINDOW_FROM="${FROM_OPT:-$NOW}"
FROM_NOTE=""
if (( COORDINATOR )) && [[ -z "$FROM_OPT" ]]; then
  first_instant="$(python3 -B "$SCRIPT_DIR/analysis/manifest.py" --self "$SESSION_START_SLUG" \
    session-start "$SESSION" 2>/dev/null)"
  if [[ -n "$first_instant" ]]; then
    WINDOW_FROM="$first_instant"; FROM_NOTE=", from the session's first instant"
  else
    FROM_NOTE=", from the clock: no transcript of $SESSION was found"
  fi
fi

# ── The orchestrator's branch (header) ────────────────────────────────────────
# Every refusal here precedes the first write, which is the `checkout -b`.
CUT_BRANCH=""
if (( COORDINATOR )); then
  (( ! BRANCH_GIVEN )) || refuse "--branch is for an orchestrator record: a coordinator record is a cost record, registered from any branch"
elif [[ -n "$TOPLEVEL" ]]; then
  [[ -f "$SCRIPT_DIR/$PROFILE_ADAPTER" ]] \
    || refuse "cannot decide the profile: $PROFILE_ADAPTER is missing beside this script, so nothing is written"
  # shellcheck source=env-profile.sh
  source "$SCRIPT_DIR/$PROFILE_ADAPTER"
  profile_why="$(profile_check)" || refuse "$profile_why — nothing is written"
  LAUNCH_BRANCH="$(git -C "$TOPLEVEL" branch --show-current 2>/dev/null)"
  if ! profile_is_cloud; then
    (( ! BRANCH_GIVEN )) || refuse "--branch is the cloud layout's (a container with no branch of its own); under the $(profile_name) profile the orchestrator's branch is the human's to create — drop --branch"
  elif (( ! BRANCH_GIVEN )); then
    if [[ -z "$LAUNCH_BRANCH" || "$LAUNCH_BRANCH" == "$BASE_BRANCH" ]]; then
      if [[ -n "$LAUNCH_BRANCH" ]]; then on_what="'$LAUNCH_BRANCH', the base"; else on_what="a detached HEAD"; fi
      refuse "in the cloud the orchestrator commits its record on a branch of its own, and this checkout is on $on_what — pass the branch this session was assigned with --branch <name>, or with none assigned, the convention: --branch $CLOUD_BRANCH_PREFIX$SLUG (the start creates it off $ORIGIN_REMOTE/$BASE_BRANCH)"
    fi
  else
    branch_slug="${BRANCH_OPT#"$CLOUD_BRANCH_PREFIX"}"
    [[ "$BRANCH_OPT" == "$CLOUD_BRANCH_PREFIX"* && "$branch_slug" =~ $SLUG_PATTERN ]] \
      && git check-ref-format --branch "$BRANCH_OPT" >/dev/null 2>&1 \
      || refuse "--branch '$BRANCH_OPT' is not a branch the orchestrator can take: it must be $CLOUD_BRANCH_PREFIX<slug>, the slug matching $SLUG_PATTERN — pass --branch $CLOUD_BRANCH_PREFIX$SLUG, or the $CLOUD_BRANCH_PREFIX<slug> branch this session was assigned"
    if [[ "$BRANCH_OPT" != "$LAUNCH_BRANCH" ]]; then
      [[ -z "$LAUNCH_BRANCH" || "$LAUNCH_BRANCH" == "$BASE_BRANCH" ]] \
        || refuse "this checkout is on '$LAUNCH_BRANCH', not --branch '$BRANCH_OPT' — the start cuts a branch from a detached HEAD or $BASE_BRANCH only, and switches to no other; run it without --branch to keep '$LAUNCH_BRANCH'"
      ! git -C "$TOPLEVEL" show-ref --verify --quiet "refs/heads/$BRANCH_OPT" \
        || refuse "--branch '$BRANCH_OPT' already exists in this checkout — the start creates the orchestrator's branch; it does not switch to one"
      if git -C "$TOPLEVEL" remote get-url "$ORIGIN_REMOTE" >/dev/null 2>&1; then
        GIT_TERMINAL_PROMPT=0 git -C "$TOPLEVEL" ls-remote -q --exit-code --heads "$ORIGIN_REMOTE" "refs/heads/$BRANCH_OPT" >/dev/null 2>&1
        ls_remote_rc=$?
        case "$ls_remote_rc" in
          "$LS_REMOTE_FOUND_RC") refuse "--branch '$BRANCH_OPT' already exists on $ORIGIN_REMOTE — somebody's branch; pick a new name (the convention: $CLOUD_BRANCH_PREFIX$SLUG)" ;;
          "$LS_REMOTE_ABSENT_RC") ;;
          *) refuse "cannot ask $ORIGIN_REMOTE whether '$BRANCH_OPT' exists (git ls-remote exited $ls_remote_rc), so no branch is cut and nothing is written" ;;
        esac
        git -C "$TOPLEVEL" fetch -q "$ORIGIN_REMOTE" "$BASE_BRANCH" 2>/dev/null \
          || echo "  warn      git fetch $ORIGIN_REMOTE $BASE_BRANCH failed; cutting from the last fetched $ORIGIN_REMOTE/$BASE_BRANCH"
      fi
      if git -C "$TOPLEVEL" show-ref --verify --quiet "refs/remotes/$ORIGIN_REMOTE/$BASE_BRANCH"; then
        START_POINT="$ORIGIN_REMOTE/$BASE_BRANCH"
      elif git -C "$TOPLEVEL" show-ref --verify --quiet "refs/heads/$BASE_BRANCH"; then
        START_POINT="$BASE_BRANCH"
      else
        refuse "the base '$BASE_BRANCH' exists neither as $ORIGIN_REMOTE/$BASE_BRANCH nor locally, so there is nothing to cut '$BRANCH_OPT' from"
      fi
      named_by="$(branch_named_at "$SCRIPT_DIR" "$SELF_FEATURES_LABEL" "$START_POINT" "$BRANCH_OPT")"
      if [[ -z "$named_by" && "$TOPLEVEL" != "$SCRIPT_DIR" ]]; then
        named_by="$(branch_named_at "$TOPLEVEL" "$CONSUMER_FEATURES_LABEL" "$START_POINT" "$BRANCH_OPT")"
      fi
      [[ -z "$named_by" ]] \
        || refuse "--branch '$BRANCH_OPT' is the branch of the feature manifest \`$named_by\` on $START_POINT — a branch is one feature's or one orchestration's, never both; pick a new name"
      if (( SELF_MODE )); then record_base="$SCRIPT_DIR"; else record_base="$REPO_DIR"; fi
      ! git -C "$record_base" cat-file -e "$START_POINT:./$ORCHESTRATIONS_REL/$SLUG" 2>/dev/null \
        || refuse "$ORCHESTRATIONS_REL/$SLUG already exists on $START_POINT — a record is started once; edit it with analysis/manifest.py ${SELF_ARG}--orchestration $SLUG"
      own="$(git -C "$TOPLEVEL" rev-list --count "$START_POINT..HEAD" 2>/dev/null)"
      [[ "${own:-0}" == 0 ]] \
        || refuse "'${LAUNCH_BRANCH:-HEAD}' carries $own commit(s) not on $START_POINT — somebody's work, which a branch cut off $START_POINT would leave behind"
      dirty="$(git -C "$TOPLEVEL" status --porcelain 2>/dev/null)"
      [[ -z "$dirty" ]] \
        || refuse "$TOPLEVEL has uncommitted changes — somebody's work; commit or remove them, then run this again"
      git -C "$TOPLEVEL" checkout -q -b "$BRANCH_OPT" "$START_POINT" \
        || refuse "git checkout -b $BRANCH_OPT $START_POINT failed in $TOPLEVEL; nothing is written"
      echo "  branch    $BRANCH_OPT off $START_POINT"
    else
      echo "  branch    $BRANCH_OPT — the branch this session is on"
    fi
    CUT_BRANCH="$BRANCH_OPT"
  fi
fi

mkdir -p "$FOLDER" || refuse "cannot create $FOLDER"
if (( COORDINATOR )); then
  cat > "$FOLDER/$RECORD_NAME" <<RECORD
# Coordination: $SLUG

<One paragraph: the features this coordinator session ran through its delegates, in which
repositories, and why they are measured together.>

This is a **coordinator record** (\`"kind": "coordinator"\`): the session coordinated
several features by delegating each to an Agent subagent, and every delegate is claimed by
the feature it built (its brief header or a pin). The coordinator's own transcript — the
briefs, the analysis, the reading of results — is claimed by no feature, so it is priced
here, on a line of its own, with only its own \`feature: none\` delegates that no feature
claims: \`orchestration-capture.sh ${SELF_ARG}$SLUG\`
writes \`planning.json\`, and \`python3 analysis/report.py ${SELF_ARG}--orchestration $SLUG\` sets it
beside every feature's \`report.json\` in \`report.md\` and \`report.json\`. The record is no
role: nothing is refused in the session or in its delegates, which share its session id.

\`\`\`json
{
  "slug": "$SLUG",
  "kind": "$KIND_COORDINATOR",
  "session": "$SESSION",
  "agent_tooling": $AGENT_TOOLING,
  "session_window": {"from": "$WINDOW_FROM", "to": null},
  "features": []
}
\`\`\`
RECORD
  [[ -f "$FOLDER/$RECORD_NAME" ]] || refuse "could not write $FOLDER/$RECORD_NAME"
  echo "  record    $ORCHESTRATIONS_REL/$SLUG/$RECORD_NAME  (coordinator $SESSION$FROM_NOTE, agent_tooling ${AGENT_TOOLING//\"/})"
  echo ""
  echo "Next:"
  echo "  1. Replace the placeholder paragraph in the record's README."
  echo "  2. For each feature the session coordinated, in any repository:"
  echo "       python3 analysis/manifest.py ${SELF_ARG}--orchestration $SLUG add-feature repo=<repo> slug=<feature> pr=<url> report=<its report.json, relative to its repo>"
  echo "  3. At the end: python3 analysis/manifest.py ${SELF_ARG}--orchestration $SLUG set-window-to now,"
  echo "       orchestration-capture.sh ${SELF_ARG}$SLUG, python3 analysis/report.py ${SELF_ARG}--orchestration $SLUG [--checkout <repo>=<path> …]"
  exit 0
fi
cat > "$FOLDER/$RECORD_NAME" <<RECORD
# Orchestration: $SLUG

<One paragraph: the group of features this orchestrator session was asked to run, and
why they are measured together.>

The orchestrator spawns one implementer session per feature and builds nothing itself.
It commits nothing except this record, which it pushes on its assigned branch as a
records-only PR; each feature's own record travels in that feature's PR. Cost is read
together: \`orchestration-capture.sh ${SELF_ARG}$SLUG\` prices the orchestrator's own transcript
(overhead) into \`planning.json\`, and \`python3 analysis/report.py ${SELF_ARG}--orchestration $SLUG\`
joins it with every feature's \`report.json\` into \`report.md\` and \`report.json\`.

\`\`\`json
{
  "slug": "$SLUG",
  "session": "$SESSION",
  "agent_tooling": $AGENT_TOOLING,
  "session_window": {"from": "$WINDOW_FROM", "to": null},
  "features": []
}
\`\`\`
RECORD
[[ -f "$FOLDER/$RECORD_NAME" ]] || refuse "could not write $FOLDER/$RECORD_NAME"
# The ledger (LEDGER_NAME, read from hooks/shared_rules.py; hooks/orchestrator_role.py reads it): the role written where the Edit tool
# cannot reach, so a hand-edit of the record cannot drop it. Only with a git checkout to hold
# it; a failure to append is a warning, the record being the role's primary copy.
# A ledger whose last line has no newline would swallow this one into it, so one is added
# first (security audit round 1, F12). No git dir to hold it is a warning here — the
# record stays the role — while the reader fails closed on a checkout whose `.git` it
# cannot resolve (hooks/orchestrator_role.py's ledger_lookup; NOTES.md).
COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --git-common-dir 2>/dev/null)"
if [[ -n "$COMMON_DIR" ]]; then
  [[ "$COMMON_DIR" == /* ]] || COMMON_DIR="$SCRIPT_DIR/$COMMON_DIR"
  LEDGER="$COMMON_DIR/$LEDGER_NAME"
  LEDGER_LEAD=""
  if [[ -s "$LEDGER" && -n "$(tail -c 1 "$LEDGER")" ]]; then LEDGER_LEAD=$'\n'; fi
  printf '%s%s %s\n' "$LEDGER_LEAD" "$SESSION" "$SLUG" >> "$LEDGER" \
    || echo "  warn      could not append to $LEDGER — the record alone holds the role"
else
  echo "  warn      no git directory found for $SCRIPT_DIR — the orchestrator ledger was not written, and the record alone holds the role"
fi
echo "  record    $ORCHESTRATIONS_REL/$SLUG/$RECORD_NAME  (session $SESSION, agent_tooling ${AGENT_TOOLING//\"/})"
# On the branch --branch named (header): the record, and nothing else, is its first commit,
# pushed as a checkpoint since a container is reclaimed with whatever it never pushed.
if [[ -n "$CUT_BRANCH" ]]; then
  git -C "$TOPLEVEL" add -- "$FOLDER/$RECORD_NAME" \
    && git -C "$TOPLEVEL" commit -q -m "$START_COMMIT_LEAD$SLUG$START_COMMIT_TAIL" -- "$FOLDER/$RECORD_NAME" \
    || refuse "the record is written but could not be committed on $CUT_BRANCH (git's reason is above) — commit $ORCHESTRATIONS_REL/$SLUG/$RECORD_NAME by hand"
  echo "  commit    $START_COMMIT_LEAD$SLUG$START_COMMIT_TAIL on $CUT_BRANCH"
  checkpoint_push "$TOPLEVEL" "$CUT_BRANCH"
fi
echo ""
echo "Next:"
echo "  1. Replace the placeholder paragraph in the record's README${CUT_BRANCH:+, and commit it on $CUT_BRANCH}."
echo "  2. For each feature: feature-start.sh ${SELF_ARG}<slug> --orchestration $SLUG …, then"
echo "       python3 analysis/manifest.py ${SELF_ARG}--orchestration $SLUG add-feature repo=<repo> slug=<feature> session=<id> branch=<branch>"
echo "  3. At the end: python3 analysis/manifest.py ${SELF_ARG}--orchestration $SLUG set-window-to now,"
echo "       orchestration-capture.sh ${SELF_ARG}$SLUG, python3 analysis/report.py ${SELF_ARG}--orchestration $SLUG"
