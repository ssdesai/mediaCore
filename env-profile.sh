#!/usr/bin/env bash
# The profile detector and the checkout-layout adapter
# (self/DESIGN-2026-10-05-cloud-execution.md §1, §2). Sourced, never executed, by
# feature-start.sh and forge.sh — the two that need to know — beside plan-runner-roots.sh.
#
# **The lifecycle never asks where it is running.** Every difference between a laptop and
# a Claude Code cloud container lives here and in a few adapters with fixed interfaces
# (forge.sh, the repo's open-session.sh). The RULE lives in one Python module,
# hooks/env_profile.py, which the PreToolUse hook imports in-process and this file runs
# once when sourced (self/features/review-base-and-cloud-hook/); this file is the shell's
# one way in to it. self/profile-confinement.sh — a blocking self/gate.sh check — fails
# when either variable is spelled in any tracked file other than that module, this file,
# the adapters and their tests. This file stays on that list because it EXPORTS the
# decided value under AGENTTOOLING_PROFILE and its functions read it back; it no longer
# spells CLAUDE_CODE_REMOTE as anything but the text profile_describe prints. A lifecycle
# script calls the functions here instead.
#
# ── The detector ──────────────────────────────────────────────────────────────
# Run when this file is sourced: ONE `python3 -B <this dir>/hooks/env_profile.py`, whose
# two output lines are the profile and what decided it. AGENTTOOLING_PROFILE ends up
# `local` or `cloud`, and is EXPORTED, so an adapter the caller runs (open-session.sh)
# reads the decided value. The module's rule:
#
#   1. an explicit AGENTTOOLING_PROFILE already in the environment wins — tests, forcing;
#      a value that is neither `local` nor `cloud` is an error (profile_check), never a
#      fallback, since a typo in a forcing variable must not quietly mean `local`;
#   2. otherwise CLAUDE_CODE_REMOTE=true (exactly `true`) → `cloud`;
#   3. otherwise `local`.
#
# PROFILE_DECIDED_BY names which: `AGENTTOOLING_PROFILE`, `CLAUDE_CODE_REMOTE` or `default`.
# An invalid override comes back as itself, decided by AGENTTOOLING_PROFILE, so
# profile_check refuses it by name. When the module cannot be asked at all (python3 or
# hooks/env_profile.py missing — a broken install, never a real profile), the profile is
# EMPTY, a warning naming the module goes to stderr, and profile_check refuses: nothing
# here may quietly decide `local`.
#
#   profile_name        the profile, on stdout
#   profile_describe    one line: the profile and the variable that decided it — what
#                       feature-start.sh prints as its `profile` line
#   profile_is_cloud    status 0 under `cloud`
#   profile_check       status 0 when the profile is one of the two; otherwise prints why
#                       on stdout and returns 1 — callers refuse on it
#
# ── The checkout layout (design §1's table, §2) ──────────────────────────────
#
#   layout_init <primary> <worktrees-dir-name> <base> [<branch>]
#       Required first (a contract no import line shows): the primary checkout, the
#       directory under it that holds local worktrees (feature-start.sh's
#       WORKTREES_DIR_NAME), the feature's base, and the `--branch` value if one was given.
#       Also records the branch the primary is on NOW — the launch branch, before any
#       `checkout -b` (layout_launch_branch).
#   feature_checkout <slug>
#       local: <primary>/<worktrees-dir>/<slug>     cloud: <primary> — the container IS
#       the worktree
#   feature_branch <slug>
#       local: <slug>.  cloud: the `--branch` value, else the launch branch when that is not
#       the base; on the base (or detached) with no `--branch` it prints nothing and
#       returns 1, and the caller refuses naming the flag.
#   create_checkout <slug> <start-point>
#       local: `git worktree add -q <checkout> -b <slug> <start-point>` — exactly the call
#       feature-start.sh made before this file existed.  cloud: nothing when the primary is
#       already on the feature's branch; otherwise `git checkout -q -b <branch>
#       <start-point>` in the primary. The start is the only caller, so LIFECYCLE.md rule 2
#       holds: agents never create a branch, the start does.
#   layout_launch_branch
#       the branch the primary was on at layout_init, or nothing when detached.

PROFILE_LOCAL="local"
PROFILE_CLOUD="cloud"
# The value of CLAUDE_CODE_REMOTE that means "this is a Claude Code cloud container".
PROFILE_REMOTE_ON="true"
# What PROFILE_DECIDED_BY holds when neither variable decided the profile.
PROFILE_DEFAULT_DECIDER="default"
# The detector module, beside this file in agentTooling's own hooks/ — vendored with it,
# so a consuming repo's agentTooling/env-profile.sh finds agentTooling/hooks/env_profile.py.
PROFILE_DETECTOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hooks/env_profile.py"
# What PROFILE_DECIDED_BY holds when the module could not be asked
PROFILE_UNDETECTED_DECIDER="undetected"

# detect_profile — the module's answer into AGENTTOOLING_PROFILE (exported) and
# PROFILE_DECIDED_BY. Run once below, when this file is sourced: one python3 call, its
# two lines read through a process substitution so this shell keeps what it reads.
detect_profile() {
  local decided="" decider=""
  {
    IFS= read -r decided
    IFS= read -r decider
  } < <(python3 -B "$PROFILE_DETECTOR" 2>/dev/null)
  if [[ -z "$decided" ]]; then
    echo "env-profile.sh: the profile detector $PROFILE_DETECTOR did not answer (is python3 installed, and is hooks/env_profile.py beside this file?) — no profile is decided" >&2
    decider="$PROFILE_UNDETECTED_DECIDER"
  fi
  AGENTTOOLING_PROFILE="$decided"
  PROFILE_DECIDED_BY="$decider"
  export AGENTTOOLING_PROFILE
}

profile_name() { echo "$AGENTTOOLING_PROFILE"; }

profile_is_cloud() { [[ "$AGENTTOOLING_PROFILE" == "$PROFILE_CLOUD" ]]; }

profile_check() {
  case "$AGENTTOOLING_PROFILE" in
    "$PROFILE_LOCAL"|"$PROFILE_CLOUD") return 0 ;;
  esac
  if [[ "$PROFILE_DECIDED_BY" == "$PROFILE_UNDETECTED_DECIDER" ]]; then
    echo "no profile was decided: the detector $PROFILE_DETECTOR did not answer (is python3 installed, and is hooks/env_profile.py beside env-profile.sh?)"
    return 1
  fi
  echo "AGENTTOOLING_PROFILE='$AGENTTOOLING_PROFILE' is neither $PROFILE_LOCAL nor $PROFILE_CLOUD — unset it to detect the profile, or set one of the two"
  return 1
}

profile_describe() {
  case "$PROFILE_DECIDED_BY" in
    AGENTTOOLING_PROFILE) echo "$AGENTTOOLING_PROFILE (AGENTTOOLING_PROFILE=$AGENTTOOLING_PROFILE)" ;;
    CLAUDE_CODE_REMOTE)   echo "$AGENTTOOLING_PROFILE (CLAUDE_CODE_REMOTE=$PROFILE_REMOTE_ON)" ;;
    "$PROFILE_UNDETECTED_DECIDER") echo "(none) ($PROFILE_UNDETECTED_DECIDER: $PROFILE_DETECTOR did not answer)" ;;
    *)                   echo "$AGENTTOOLING_PROFILE (default: no AGENTTOOLING_PROFILE, and CLAUDE_CODE_REMOTE is not $PROFILE_REMOTE_ON)" ;;
  esac
}

layout_init() {
  LAYOUT_PRIMARY="$1"
  LAYOUT_WORKTREES_DIR="$2"
  LAYOUT_BASE="$3"
  LAYOUT_BRANCH_OPT="${4:-}"
  LAYOUT_LAUNCH_BRANCH="$(git -C "$LAYOUT_PRIMARY" branch --show-current 2>/dev/null)"
}

layout_launch_branch() { echo "$LAYOUT_LAUNCH_BRANCH"; }

feature_checkout() {
  if profile_is_cloud; then
    echo "$LAYOUT_PRIMARY"
  else
    echo "$LAYOUT_PRIMARY/$LAYOUT_WORKTREES_DIR/$1"
  fi
}

feature_branch() {
  if ! profile_is_cloud; then
    echo "$1"
    return 0
  fi
  if [[ -n "$LAYOUT_BRANCH_OPT" ]]; then
    echo "$LAYOUT_BRANCH_OPT"
    return 0
  fi
  if [[ -n "$LAYOUT_LAUNCH_BRANCH" && "$LAYOUT_LAUNCH_BRANCH" != "$LAYOUT_BASE" ]]; then
    echo "$LAYOUT_LAUNCH_BRANCH"
    return 0
  fi
  return 1
}

create_checkout() {
  local slug="$1" start_point="$2" branch
  if ! profile_is_cloud; then
    git -C "$LAYOUT_PRIMARY" worktree add -q "$(feature_checkout "$slug")" -b "$slug" "$start_point"
    return
  fi
  branch="$(feature_branch "$slug")" || return 1
  if [[ "$(git -C "$LAYOUT_PRIMARY" branch --show-current 2>/dev/null)" == "$branch" ]]; then
    return 0
  fi
  git -C "$LAYOUT_PRIMARY" checkout -q -b "$branch" "$start_point"
}

detect_profile
