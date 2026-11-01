#!/usr/bin/env bash
set -uo pipefail

# The SessionStart hook: what every session in a repo using agentTooling runs first.
#
#   session-start.sh [--self]
#
# `hooks/wire-settings.py` wires this script, and only this script, as the repo's
# `SessionStart` command — `${CLAUDE_PROJECT_DIR}/agentTooling/session-start.sh` in a
# consuming repo, the guarded `--self` spelling in agentTooling's own tracked settings. It
# is agentTooling's, so a change here reaches every consuming repo on its next
# `subtree pull`, with no re-seeding: the repo's own part is a script this one CALLS, the
# shape feature-start.sh has with plans/worktree-setup.sh and feature-close.sh with
# plans/pr.sh.
#
# Two halves, in this order:
#
#   1. ORIENTATION, every profile (agentTooling's own): two or three lines naming the
#      profile and what decided it, the branch this checkout is on, and the one command
#      that comes next — `feature-start.sh <slug>` where no feature is started on this
#      branch, the feature and its close where one is. Under `cloud` it says outright that
#      the start runs HERE, on this branch, and creates or pushes no other: a session told
#      to stay on its assigned branch is already running the standard flow, and must not
#      read LIFECYCLE.md's local layout as a conflict (it did — the reason this exists).
#      On the base or a detached HEAD in the cloud it adds the restart case: a session
#      continuing a feature started on another branch is in a container the platform
#      restarted on the base, and a fresh session on that branch is the fix. One detached
#      shape is cured differently: HEAD exactly at a started feature's origin/<branch>,
#      the local branch absent or behind (a cached clone the platform re-checked-out
#      detached; a fresh session reproduces it). There the one line printed instead names
#      attach-branch.sh, which re-attaches it moving nothing (plan-runner-roots.sh's
#      attachable_branches; self/features/detached-at-branch-tip-attach/).
#   2. THE REPO'S SETUP, cloud only: the consuming repo's seeded `plans/cloud-setup.sh`,
#      when there is one — services a fresh container lacks (Postgres, a role). Its exit
#      code is this script's, so a failed setup is not hidden behind the orientation. A
#      `--self` checkout has no plans/ and runs nothing here. A slow step the repo's
#      script starts in the background (its `setup_in_background`, template-version 3)
#      outlives this hook; feature-start.sh waits for it with `plans/cloud-setup.sh
#      --wait` before its gate (self/features/hand-start-friction/).
#
# Constraints, since a SessionStart hook runs on every start — a new session, a resume, a
# compaction — and its stdout lands in the session's context each time:
#
#   - READ-ONLY. It changes no ref, no file, no setting. The fast-forwards and refusals
#     are feature-start.sh's; this only says which command to run.
#   - FAST: git and a manifest read, no network, no fetch.
#   - SHORT: a handful of lines, each prefixed `agentTooling`, so its source is plain.
#   - The profile comes from env-profile.sh's functions; this file spells no profile
#     variable (self/profile-confinement.sh).
#
# Depends on: env-profile.sh (profile_is_cloud, profile_describe) and plan-runner-roots.sh
# (resolve_roots — REPO_DIR, FEATURES_DIR, FEATURES_LABEL, SELF_ARG — and
# started_features_on over manifest_branch, the one reader of a feature's branch). A
# feature "is started on this branch" exactly when a TRACKED manifest's `branches[0]` is
# the branch — the same reading feature-start.sh's cloud one-feature refusal makes, and
# update.sh's cloud fallback.

# Every line this prints starts with it
LINE_PREFIX="agentTooling  "
# The branch a local primary checkout stays on, and a feature's default base
# (feature-start.sh's PRIMARY_BRANCH and DEFAULT_BASE; the three move together)
BASE_BRANCH="main"
# The repo's own cloud step, relative to the consuming repo's root
REPO_CLOUD_SETUP_REL="plans/cloud-setup.sh"
# How a manifest is named inside a feature directory
MANIFEST_NAME="README.md"
# The docs a line points at, relative to agentTooling's own directory
LIFECYCLE_DOC="LIFECYCLE.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
source "$SCRIPT_DIR/env-profile.sh"
resolve_roots "${1:-}"

say() { echo "$LINE_PREFIX$1"; }

# The commands as a session types them from the repo root (its working directory).
if (( SELF_MODE )); then
  TOOL_PREFIX="./"
  DOC_PREFIX=""
else
  TOOL_PREFIX="./agentTooling/"
  DOC_PREFIX="agentTooling/"
fi
START_CMD="${TOOL_PREFIX}feature-start.sh ${SELF_ARG}<slug>"
# The cloud restart case (self/features/cloud-off-branch-remedy/): a reclaimed container
# comes back cloned on the base, not on the feature's branch. One fixed line, no manifest
# scan — naming every started branch would cost a manifest read per feature on every start.
CONTINUING_LINE="if you are continuing a feature already started on another branch, this container is not on it: the platform restarted it on $BASE_BRANCH. A fresh session launched on that branch is the fix — never check it out, and never commit or push $BASE_BRANCH yourself (${DOC_PREFIX}$LIFECYCLE_DOC)"

if ! profile_check >/dev/null; then
  say "$(profile_check) — feature-start.sh will refuse until it is fixed"
  exit 0
fi

BRANCH="$(git -C "$REPO_DIR" branch --show-current 2>/dev/null)"

# started_feature <branch> — the first slug whose tracked manifest names <branch> as its
# branches[0], or nothing: plan-runner-roots.sh's started_features_on, the one reader
# update.sh's cloud fallback uses too.
started_feature() {
  started_features_on "$REPO_DIR" "$FEATURES_LABEL" "$1" | head -n 1
}

say "profile $(profile_describe); branch ${BRANCH:-(detached HEAD)}"

STARTED="$(started_feature "$BRANCH")"
if [[ -n "$STARTED" ]]; then
  say "feature '$STARTED' is started on this branch ($FEATURES_LABEL/$STARTED/$MANIFEST_NAME): build it here, and close it with ${TOOL_PREFIX}feature-close.sh ${SELF_ARG}$STARTED (${DOC_PREFIX}$LIFECYCLE_DOC)"
elif profile_is_cloud; then
  # The cached-clone shape (self/features/detached-at-branch-tip-attach/): detached exactly
  # at a started feature's origin/<branch>, its local ref absent or behind. Neither a start
  # nor a fresh session is the remedy there; attach-branch.sh is, and it moves nothing.
  ATTACH=""
  [[ -n "$BRANCH" ]] || ATTACH="$(attachable_branches "$REPO_DIR" "$FEATURES_LABEL" | head -n 1)"
  if [[ -n "$ATTACH" ]]; then
    say "HEAD is detached at origin/$ATTACH, the tip of feature '$(started_feature "$ATTACH")''s branch: the platform re-checked-out a cached clone, and a fresh session will not cure it. Re-attach with ${TOOL_PREFIX}attach-branch.sh ${SELF_ARG}$ATTACH — it moves nothing — then build here; never git checkout -B or a plain git checkout $ATTACH (${DOC_PREFIX}$LIFECYCLE_DOC)"
  elif [[ -z "$BRANCH" || "$BRANCH" == "$BASE_BRANCH" ]]; then
    say "this container is one feature's checkout. Start it with $START_CMD --branch <name>: the start cuts <name> off origin/$BASE_BRANCH — never create a branch yourself (${DOC_PREFIX}$LIFECYCLE_DOC)"
    say "$CONTINUING_LINE"
  else
    say "this container is one feature's checkout, on '$BRANCH'. Start it with $START_CMD, run here: the feature's branch IS '$BRANCH' — no worktree, and no other branch created or pushed. Do not check out $BASE_BRANCH or make a branch per slug; that is the local layout (${DOC_PREFIX}$LIFECYCLE_DOC)"
  fi
elif [[ "$BRANCH" == "$BASE_BRANCH" ]]; then
  say "the primary checkout. Start a feature with $START_CMD: it makes branch <slug> and the worktree .worktrees/<slug>, and the feature is built there, not here (${DOC_PREFIX}$LIFECYCLE_DOC)"
else
  say "no started feature names '${BRANCH:-this checkout}'. Features start from the primary checkout on $BASE_BRANCH with $START_CMD (${DOC_PREFIX}$LIFECYCLE_DOC)"
fi

# ── The repo's own cloud step ─────────────────────────────────────────────────
if ! profile_is_cloud || (( SELF_MODE )); then
  exit 0
fi
REPO_CLOUD_SETUP="$REPO_DIR/$REPO_CLOUD_SETUP_REL"
if [[ ! -f "$REPO_CLOUD_SETUP" ]]; then
  say "no $REPO_CLOUD_SETUP_REL — run ./agentTooling/sync-plans.sh to seed it"
  exit 0
fi
bash "$REPO_CLOUD_SETUP"
