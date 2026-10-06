#!/usr/bin/env bash
set -uo pipefail

# Start a feature: feature-start.sh [--self] <slug> [--method direct|plans|hand]
#   [--base <branch>] [--branch <name>] [--no-gate] [--pin] [--session <id>] [--open]
#
# The only sanctioned way to create a feature branch or worktree (LIFECYCLE.md). The
# rule, for slug S in a repo whose primary checkout is R, under the LOCAL profile:
#
#   slug      ^[a-z0-9]+(-[a-z0-9]+)*$     kebab-case, no slash, no owner prefix
#   branch    S
#   worktree  R/.worktrees/S               inside the primary checkout, kept out of git
#
# **Where it runs is env-profile.sh's to decide, never this script's**
# (self/DESIGN-2026-10-05-cloud-execution.md §1). It prints one `profile` line naming the
# profile and the variable that decided it, records the profile in the manifest's fence,
# and asks the layout adapter env-profile.sh defines for the checkout and the branch —
# it never reads the profile variables itself (self/profile-confinement.sh fails if it
# does). Everything below describes the LOCAL layout, which is unchanged; the CLOUD one
# (design §2, §3), where a Claude Code container IS the worktree, differs only here:
#
#   - the checkout is R itself, on the session's assigned branch: `--branch <name>`, else
#     the branch R is on when that is not the base. On the base with neither, the start
#     refuses naming the flag; `--branch` names a NEW branch, which this script cuts off
#     origin/<base> with `git checkout -b` (agents never do — LIFECYCLE.md rule 2), and an
#     existing branch that is not checked out is refused. Locally `--branch` is refused:
#     the branch is the slug;
#   - before anything is written it refuses a second feature (a `<x>: start` commit not
#     on origin/<base>, or a tracked manifest whose branches[0] is this branch — a
#     container pushes one branch, so it holds one feature), a branch carrying commits
#     not on origin/<base> (somebody's work), and a dirty tree; then "the checkout
#     contains origin/<base>" replaces "the primary is on main": a checkout strictly
#     behind with no commits of its own is fast-forwarded and the run exits 3 with the
#     command to run again, exactly as a stale primary does locally;
#   - the start lock is R's own .git/feature-start.lock, carrying the slug, the branch and
#     the branch the start was LAUNCHED ON as well as the pid. A refused start leaves it;
#     a re-run of the same slug on that branch whose pid is gone RESUMES at the setup hook:
#     no clean-tree or own-commit refusal (the hand fix is exactly that), no new branch, an
#     uncommitted manifest and review stub kept, and nothing deleted — the start commit
#     only ever adds the feature directory, so a fix in the tree is never swept into it;
#   - the prune runs as everywhere, and finds no worktrees in a container.
#
# **Router or coordinator is derived, not configured** (design §3, in both profiles). The
# session running the start is the feature's COORDINATOR when the branch R was on when
# the start began — before any `checkout -b` — is the feature's branch: in the cloud,
# every session started on its assigned branch. Then no routing record is written and
# nothing is pinned, and `from` is that session's FIRST transcript instant
# (`manifest.py session-start`), truncated to the millisecond — never later than the
# session's first line, and the exact instant `set-window-from` accepts (issue #82;
# self/features/session-start-precision) — so the capture's branch route —
# which selects a session by its start — selects it; when the transcript cannot be read,
# `from` is the clock and one `warn` line names `set-window-from`. Locally R is on main
# and the branch is S, so the session is a router, exactly as described below.
#
# Inside rather than beside R because a session launched in R can then reach the worktree
# with no access outside its own folder. Features started before this layout keep their
# sibling R-S until they merge; feature-capture.sh and the capture tooling handle both.
#
# Everything cost capture needs is then derived from the slug — the branch to match, the
# worktree path, the transcript directory a session launched there is filed under — with
# nothing to configure and nothing an agent can drift from. In order, this script:
#
#   1. refuses a slug that fails the pattern, a branch or worktree that already exists —
#      unless the two are this slug's own ABANDONED HALF-START, which it takes over (see
#      "Taking over a half-start" below) — and being run from a worktree's copy (the
#      worktree's copy is the wrong copy);
#   2. makes sure the common git dir's info/exclude ignores /.worktrees/ — so the
#      primary's `git status` stays clean with the worktree inside it — then fetches
#      origin, and when the primary's main is BEHIND origin/main, fast-forwards it and
#      exits asking to be run again (see "A stale primary" below);
#   3. prunes the features that have merged: every worktree under R/.worktrees/ whose
#      branch has moved since it was created and is an ancestor of origin/main is
#      removed and its local branch deleted (`git branch -D` — ancestry against
#      origin/main is the check, and `-d` would re-decide it against the primary's own
#      HEAD, which lags whenever the PR merged on the forge and nobody pulled). "Has
#      moved" is what keeps a concurrent start's brand-new branch alive: until its
#      `S: start` commit lands it sits at its start point, an ancestor of origin/main
#      with nothing merged (see "Merged" at prune_one). A merged branch whose reflog no
#      longer records where it was created is kept, with one line saying so. The one
#      unmoved branch it does take is an abandoned half-start of any slug: still at its
#      creation commit, clean, and holding a start lock whose PID is gone (a live lock, or
#      none, is left alone — see "Taking over a half-start").
#      That is the whole of post-merge teardown. A worktree with uncommitted work is
#      left in place with one line saying so, an unmerged one is never touched, and
#      nothing is committed or pushed;
#   4. adds the worktree R/.worktrees/S on a new branch S off origin/<base> (default
#      main; `--base` records a stacked feature's base for the PR), and at once writes the
#      START LOCK, `pid=<this process>` and `started=<UTC>`, into that worktree's own admin
#      dir (`git rev-parse --absolute-git-dir` inside it, .git/worktrees/<name>/);
#   5. runs the repo's setup hook inside it — plans/worktree-setup.sh, or
#      self/worktree-setup.sh under --self — for the venv, npm install, dev port;
#   6. runs the repo's gate inside it, with GATE_RESUME=1 (a re-run on the same tree skips
#      the checks that already passed — design §8), and stops unless the verdict is green:
#      a red base is the implementer's context spent on someone else's failures
#      (`--no-gate` skips);
#   7. writes the manifest from templates/plans/features/TEMPLATE.md with its fence
#      filled (branches [S], base, the profile, `gate` — "green" when step 6 ran green,
#      "skipped" under --no-gate or with no gate script, design §7 — `from` now in UTC
#      with a Z, `to` null, and no pin),
#      and a review-brief stub carrying @@TODO@@ that run-review.sh refuses to run until
#      it is replaced;
#   8. writes the ROUTING RECORD for the session that ran it, INSIDE that feature
#      directory — plans/features/S/routing.json, self/features/ under --self — through
#      analysis/routing.py, from that session's own transcript; unless --pin, since a
#      pinned session is this feature's and never also a router;
#   9. commits the feature directory, routing record and all, on S as `S: start`, and
#      removes the start lock;
#  10. with `--open`, runs the repo's plans/open-session.sh (self/open-session.sh under
#      --self) with the worktree path as its only argument, which is how the coordinator
#      session is launched INSIDE the worktree;
#  11. prints where to coordinate from and the line every brief opens with.
#
# **This session is a router, and a router is never pinned.** One coordinator session per
# feature, launched in that feature's worktree, is the rule (LIFECYCLE.md rule 1); the
# session that runs this script opens several features and belongs to none of them, so
# pinning it bills one session's whole transcript to every feature it started. Its spend
# is routing overhead instead, reported per repo from the record step 8 writes
# (analysis/README.md → routing.py). `--pin` restores the old behaviour for the rare case
# where this really is the feature's own coordinator — and then the session is not a
# router, so no routing record is written: one owner per session, and the pin is the
# link. `--session <id>` names the session — for the routing record without `--pin`, and
# for the pin with it. `--no-pin` is accepted and does nothing, so a brief or a note
# written under the old default still runs.
#
# **A stale primary.** This script runs from the primary's copy of agentTooling but
# branches from origin/<base>, so a primary whose main lags origin/main runs OLD code that
# writes and commits into a branch carrying NEW code — on 2026-09-21 an old copy
# `git add`-ed a routing-record path the branch's routing.py no longer wrote, and the
# start commit failed half-way. So before anything is pruned or created, a primary behind
# origin/main is fast-forwarded to it and the run stops: the process still executing is
# the old code, and only a fresh run is the new. It prints the command to run again and
# exits $UPDATED_RC. The check is against origin/main whatever --base is, because main is
# what the primary tracks and so what this copy came from. A primary that is not on main,
# has diverged from origin/main, or has a local change in the fast-forward's way is
# refused, untouched. With no origin, a failed fetch, or no origin/main, nothing is checked.
#
# Otherwise the primary checkout's tracked tree is never touched: nothing here checks out,
# stashes or commits in it, so it need not be clean and nothing else running in it is
# disturbed. Its one other write outside the new worktree is the info/exclude entry, which
# no repo tracks.
#
# **Taking over a half-start.** A start that stops between steps 4 and 9 — a refusal from
# the hook or the gate, or an interrupt — leaves branch S at the commit it was created
# from and the worktree with no feature directory: a HALF-START. A refusal leaves it in
# place for inspection, and leaves the start lock too, with a `refused=<reason>` line
# appended, so the lock says which start abandoned it and why; an interrupt leaves the
# lock as written. Before this, a re-run refused the existing branch for good, and agents
# may not delete refs, so a flaky base gate stranded its slug until a human cleared it.
# Now a re-run of S takes its own half-start over — removes the worktree and the branch
# and starts afresh from the current base — only when ALL of these hold (assess_own_half_start):
#
#   - branch S exists and R/.worktrees/S is a worktree on it;
#   - S is still at the commit its reflog's `branch: Created from` entry records;
#   - the worktree is clean (untracked files count; ignored ones do not);
#   - the earlier start is provably dead: its lock names a PID `ps` no longer lists, or
#     there is no lock at all — the shape every start before the lock existed left.
#
# A lock naming a live PID is a concurrent start of the same slug and is refused, naming
# the PID. The check runs twice — at once, so a refusal comes before anything is fetched or
# pruned, and again just before the removal, after the fetch, so a concurrent start still
# between its `worktree add` and its lock write has had seconds to write it. The prune
# (step 3) reads the same lock with one difference: there a MISSING lock keeps the branch,
# since a start of another slug cannot tell a pre-lock half-start from a start caught
# between its `worktree add` and its lock write, and the prune never deletes what it
# cannot prove. The prune and this takeover are the only places a ref is deleted.
#
# Exit codes: 2 usage; 1 any refusal; 3 main was fast-forwarded — run the same command again.

USAGE_RC=2
REFUSED_RC=1
UPDATED_RC=3
SLUG_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'
KNOWN_METHODS="direct plans hand"
DEFAULT_METHOD="direct"
DEFAULT_BASE="main"
TODO_MARKER="@@TODO@@"
# The directory under the primary checkout that holds every feature worktree
# (LIFECYCLE.md). analysis/capture_planning.py holds the same name in a constant of its
# own; the two move together.
WORKTREES_DIR_NAME=".worktrees"
# The branch the primary checkout stays on (LIFECYCLE.md), and the remote ref it must not
# lag when a feature starts ("A stale primary" above).
PRIMARY_BRANCH="main"
PRIMARY_UPSTREAM="origin/$PRIMARY_BRANCH"
# The ref a worktree's branch must be an ancestor of to count as merged. `origin/main`
# and not the feature's own `--base`: a stacked feature's base is itself a branch that has
# to reach main before its stack does, so this is the one ref that means "merged" for
# every worktree under .worktrees/. With no such ref the prune does nothing at all.
PRUNE_MERGED_INTO="$PRIMARY_UPSTREAM"
# How the prune deletes a pruned worktree's local branch. `-D` because ancestry against
# $PRUNE_MERGED_INTO is proven before the delete is attempted; `-d` would re-decide
# "merged" against the branch's upstream or the primary's HEAD, which is a different and
# laggier question (see prune_one).
PRUNE_DELETE_FLAG="-D"
# The message git writes as a branch's first reflog entry when `git worktree add -b` (or
# `git branch`) creates it. The prune takes the oldest entry as the creation point only
# when it carries this prefix: once gc has expired the real first entry (gc.reflogExpire),
# the oldest one left is some later commit, and reading that as "created here" would keep
# a merged worktree without a word (see prune_one).
BRANCH_CREATED_REFLOG_PREFIX="branch: Created from"
# The start lock ("Taking over a half-start" in the header): its file name inside the new
# worktree's own admin dir — .git/worktrees/<name>/, where the worktree's `git status`
# never sees it and `git worktree remove` deletes it with the rest — and the `key=value`
# lines it holds. self/tests/start-takeover.sh reads and forges the pid line by these
# names.
START_LOCK_NAME="feature-start.lock"
START_LOCK_PID_KEY="pid"
START_LOCK_STARTED_KEY="started"
START_LOCK_REFUSED_KEY="refused"
# The cloud lock's extra lines (header, the cloud layout): which start it is, on which
# branch, and the branch it was launched on — what a resumed start is router or
# coordinator by. The local lock carries none of them and is byte-identical to before.
START_LOCK_SLUG_KEY="slug"
START_LOCK_BRANCH_KEY="branch"
START_LOCK_LAUNCHED_KEY="launched_on"
# The subject of the commit a start ends with: `<slug>: start`. A branch carrying one not
# on origin/<base> already holds a started feature (the cloud's one-feature rule).
START_SUBJECT_SUFFIX=": start"
# How many dirty paths the cloud's dirty-tree refusal names.
DIRTY_PATHS_NAMED=3
# The fence's `gate` key (self/DESIGN-2026-10-05-cloud-execution.md §7; manifest.py's
# KNOWN_GATE_RECORDS): the base gate ran here and was green, or no gate ran at all.
GATE_RECORD_GREEN="green"
GATE_RECORD_SKIPPED="skipped"
# The module that derives and writes the routing record, run from the new worktree's copy
# so the record lands in the worktree's corpus and rides the `S: start` commit, and the
# name it writes it under inside the feature directory (analysis/routing.py's
# RECORD_NAME; this script only prints it, and the two move together).
ROUTING_MODULE="analysis/routing.py"
ROUTING_RECORD_NAME="routing.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The command as typed, for the "run it again" line a stale primary ends on.
RERUN_CMD="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")$(printf ' %q' "$@")"
source "$SCRIPT_DIR/plan-runner-roots.sh"
# The detector and the layout adapter (header): the profile, and the checkout and branch
# a feature gets under it. Sourced, so its functions are the only way this script asks.
source "$SCRIPT_DIR/env-profile.sh"
resolve_roots "${1:-}"
SELF_FLAG=()
if [[ "${1:-}" == "--self" ]]; then SELF_FLAG=(--self); shift; fi

usage() {
  echo "usage: feature-start.sh [--self] <slug> [--method direct|plans|hand] [--base <branch>] [--branch <name>] [--no-gate] [--pin] [--session <id>] [--open]" >&2
  exit "$USAGE_RC"
}
# This run's start lock, once step 4 has written it; empty before that and after step 9.
START_LOCK=""
# A refusal while this run holds its lock leaves a half-start: the lock stays, recording
# the reason, so it names the start that abandoned it — a dead PID once this exits, which
# is exactly what lets the next start of this slug take it over.
refuse() {
  echo "  refused  $*" >&2
  if [[ -n "$START_LOCK" && -f "$START_LOCK" ]]; then
    printf '%s=%s\n' "$START_LOCK_REFUSED_KEY" "$*" >> "$START_LOCK" 2>/dev/null
    echo "           the half-start is left for inspection, its lock at $START_LOCK saying so;" >&2
    echo "           while it stays clean, re-running this start takes it over, and a later start of any slug prunes it unless it was cut from a stacked --base" >&2
  fi
  exit "$REFUSED_RC"
}

SLUG="${1:-}"; [[ -n "$SLUG" ]] || usage; shift
METHOD="$DEFAULT_METHOD"; BASE="$DEFAULT_BASE"; RUN_GATE=1; PIN=0; SESSION_OPT=""; OPEN=0
BRANCH_OPT=""
while (( $# )); do
  # Every value-taking flag checks its arity first: `shift 2` with one argument left
  # returns non-zero WITHOUT shifting, and there is no `set -e` here to stop on it, so a
  # truncated flag would spin this loop forever instead of printing the usage.
  case "$1" in
    --method)  (( $# >= 2 )) || usage; METHOD="$2"; shift 2 ;;
    --base)    (( $# >= 2 )) || usage; BASE="$2"; shift 2 ;;
    --branch)  (( $# >= 2 )) || usage; BRANCH_OPT="$2"; shift 2 ;;
    --no-gate) RUN_GATE=0; shift ;;
    --pin)     PIN=1; shift ;;
    # Accepted and ignored: not pinning is the default now, and a brief, a runbook or a
    # note written under the old one must not stop working on a flag that agrees with it.
    --no-pin)  shift ;;
    --session) (( $# >= 2 )) || usage; SESSION_OPT="$2"; shift 2 ;;
    --open)    OPEN=1; shift ;;
    *) usage ;;
  esac
done
[[ "$SLUG" =~ $SLUG_PATTERN ]] || refuse "slug '$SLUG' must match $SLUG_PATTERN — kebab-case, no slash, no prefix"
case " $KNOWN_METHODS " in *" $METHOD "*) ;; *) refuse "--method must be one of: $KNOWN_METHODS" ;; esac
[[ -n "$BASE" ]] || usage
if ! profile_why="$(profile_check)"; then refuse "$profile_why"; fi
echo "  profile   $(profile_describe)"
if [[ -n "$BRANCH_OPT" ]] && ! profile_is_cloud; then
  refuse "--branch is the cloud layout's (a container's assigned branch); under the $(profile_name) profile the feature's branch is its slug, '$SLUG' — drop --branch"
fi

# ── Where ─────────────────────────────────────────────────────────────────────
# REPO_DIR is this script's repo root in the two modes; the git toplevel above it is
# the primary checkout (the same directory in a standalone agentTooling clone, the
# consuming repo when vendored). Everything else is a path relative to that.
PRIMARY="$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null)" || refuse "$REPO_DIR is not inside a git repository"
if [[ "$(git -C "$PRIMARY" rev-parse --git-dir)" != "$(git -C "$PRIMARY" rev-parse --git-common-dir)" ]]; then
  refuse "this copy is inside a worktree ($PRIMARY); run the primary checkout's feature-start.sh — it is $(dirname "$(git -C "$PRIMARY" rev-parse --git-common-dir)")/${SCRIPT_DIR#"$PRIMARY"/}"
fi
REL_REPO="${REPO_DIR#"$PRIMARY"}"; REL_REPO="${REL_REPO#/}"          # "" or agentTooling
REL_AT="${SCRIPT_DIR#"$PRIMARY"}"; REL_AT="${REL_AT#/}"              # "" or agentTooling
# The feature's checkout, from the layout adapter: R/.worktrees/S locally, R itself in the
# cloud. Named WORKTREE throughout, as it always was; in the cloud it is the primary.
layout_init "$PRIMARY" "$WORKTREES_DIR_NAME" "$BASE" "$BRANCH_OPT"
WORKTREE="$(feature_checkout "$SLUG")"
# The branch R is on as the start begins, before any `checkout -b` — what decides router
# or coordinator (header). A resumed cloud start takes it from its lock instead, below.
LAUNCH_BRANCH="$(layout_launch_branch)"
WT_REPO_DIR="$WORKTREE${REL_REPO:+/$REL_REPO}"
WT_AT="$WORKTREE${REL_AT:+/$REL_AT}"
WT_FEATURES="$WT_REPO_DIR/$FEATURES_LABEL"
HOOK_LABEL="${GATE_SCRIPT_LABEL%/gate.sh}/worktree-setup.sh"
# The repo-owned hook --open runs. Seeded like worktree-setup.sh and resolved the same
# way, so plans/open-session.sh and self/open-session.sh are one rule.
OPEN_HOOK_LABEL="${GATE_SCRIPT_LABEL%/gate.sh}/open-session.sh"
WORKTREES_ROOT="$PRIMARY/$WORKTREES_DIR_NAME"
REPO_NAME="$(basename "$PRIMARY")"
# The session that ran this script. Without --pin it is the router and names the routing
# record; under --pin it is the manifest's pin and names no record — never both.
ROUTER_SESSION="${SESSION_OPT:-${CLAUDE_CODE_SESSION_ID:-}}"

# ── Half-starts: the readers the takeover and the prune share ─────────────────
# branch_creation <branch> — the commit <branch> was created at, from the oldest entry of
# its reflog, or nothing when that entry is not the creation record (no reflog, or gc has
# expired it). See "Merged" at prune_one for why the oldest entry and why the prefix.
branch_creation() {
  local oldest
  oldest="$(git -C "$PRIMARY" reflog show --format='%H %gs' "refs/heads/$1" 2>/dev/null | tail -n 1)"
  case "${oldest#* }" in
    "$BRANCH_CREATED_REFLOG_PREFIX"*) echo "${oldest%% *}" ;;
  esac
}

# start_lock_state <worktree> — reads that worktree's start lock into three globals:
#   LOCK_FILE   where the lock is, or would be
#   LOCK_STATE  live  — it names a PID `ps` still lists: a start running now
#               dead  — it names a PID `ps` no longer lists: a start that stopped
#               none  — no lock, or one with no readable PID
#   LOCK_PID    the PID it names, or empty
# `ps -p` rather than `kill -0`, which answers "not permitted" for another user's process
# and would read a live start as dead. A PID the OS has since reused reads as live — the
# safe direction: a refusal naming it, never a takeover of a running start.
start_lock_state() {
  local admin pid
  LOCK_FILE=""; LOCK_STATE="none"; LOCK_PID=""
  admin="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
  [[ -n "$admin" ]] || return 0
  LOCK_FILE="$admin/$START_LOCK_NAME"
  [[ -f "$LOCK_FILE" ]] || return 0
  pid="$(sed -n "s/^$START_LOCK_PID_KEY=//p" "$LOCK_FILE" 2>/dev/null | head -n 1)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  LOCK_PID="$pid"
  if ps -p "$pid" >/dev/null 2>&1; then LOCK_STATE="live"; else LOCK_STATE="dead"; fi
}

# drop_half_or_merged <worktree> <branch> — removes the worktree, then deletes the branch
# with $PRUNE_DELETE_FLAG. 0 both went; 1 `git worktree remove` refused (nothing changed);
# 2 the worktree went and `git branch` refused the branch. The one place a ref is deleted:
# the prune and the takeover both call it, each only after proving the branch holds no work.
drop_half_or_merged() {
  git -C "$PRIMARY" worktree remove "$1" >/dev/null 2>&1 || return 1
  git -C "$PRIMARY" branch "$PRUNE_DELETE_FLAG" "$2" >/dev/null 2>&1 || return 2
  return 0
}

# assess_own_half_start — 0 when this slug's existing branch and worktree are an abandoned
# half-start this run may take over (the header's four conditions); otherwise 1, with the
# refusal in HALF_START_WHY. Leaves start_lock_state's globals set for the caller's message.
assess_own_half_start() {
  local created
  HALF_START_WHY=""
  if ! git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$SLUG"; then
    HALF_START_WHY="$WORKTREE already exists"
    return 1
  fi
  if [[ ! -e "$WORKTREE" ]]; then
    HALF_START_WHY="branch '$SLUG' already exists"
    return 1
  fi
  if [[ "$(git -C "$WORKTREE" rev-parse --show-toplevel 2>/dev/null)" != "$WORKTREE" \
      || "$(git -C "$WORKTREE" branch --show-current 2>/dev/null)" != "$SLUG" ]]; then
    HALF_START_WHY="branch '$SLUG' already exists, and $WORKTREE is not a worktree on it"
    return 1
  fi
  created="$(branch_creation "$SLUG")"
  if [[ -z "$created" ]]; then
    HALF_START_WHY="branch '$SLUG' already exists, and its reflog no longer records where it was created, so it cannot be shown to hold no work"
    return 1
  fi
  if [[ "$(git -C "$PRIMARY" rev-parse "refs/heads/$SLUG")" != "$created" ]]; then
    HALF_START_WHY="branch '$SLUG' already exists and has commits of its own — a started feature, not an abandoned start"
    return 1
  fi
  if [[ -n "$(git -C "$WORKTREE" status --porcelain 2>/dev/null)" ]]; then
    HALF_START_WHY="branch '$SLUG' already exists: an unfinished start whose worktree $WORKTREE has uncommitted changes, which are somebody's work, so it is not taken over"
    return 1
  fi
  start_lock_state "$WORKTREE"
  if [[ "$LOCK_STATE" == live ]]; then
    HALF_START_WHY="a start of '$SLUG' is still running (pid $LOCK_PID, per $LOCK_FILE) — let it finish; if pid $LOCK_PID is not a feature-start.sh (a reused pid), a human removes that lock"
    return 1
  fi
  return 0
}

# lock_value <file> <key> — one `key=value` line of a start lock, the first one.
lock_value() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

# Checked here, before anything is fetched or pruned, so every refusal costs nothing; and
# again at the takeover itself, below the stale-primary check (header). Local only: the
# takeover is of a WORKTREE and its branch S, which the cloud layout never makes.
TAKEOVER=0
if ! profile_is_cloud; then
  if git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$SLUG" || [[ -e "$WORKTREE" ]]; then
    assess_own_half_start || refuse "$HALF_START_WHY"
    TAKEOVER=1
  fi
fi

# ── The cloud layout: the branch, and a start to resume (header) ──────────────
# Before anything is fetched, like the takeover check above. FEATURE_BRANCH is what the
# manifest's branches[0] will say: the slug locally, the assigned branch in the cloud.
FEATURE_BRANCH="$SLUG"
RESUME=0
CLOUD_LOCK=""
if profile_is_cloud; then
  CLOUD_LOCK="$(git -C "$PRIMARY" rev-parse --absolute-git-dir 2>/dev/null)/$START_LOCK_NAME"
  if [[ -f "$CLOUD_LOCK" ]]; then
    lock_pid="$(lock_value "$CLOUD_LOCK" "$START_LOCK_PID_KEY")"
    lock_slug="$(lock_value "$CLOUD_LOCK" "$START_LOCK_SLUG_KEY")"
    lock_branch="$(lock_value "$CLOUD_LOCK" "$START_LOCK_BRANCH_KEY")"
    lock_launched="$(lock_value "$CLOUD_LOCK" "$START_LOCK_LAUNCHED_KEY")"
    lock_refused="$(lock_value "$CLOUD_LOCK" "$START_LOCK_REFUSED_KEY")"
    if [[ "$lock_pid" =~ ^[0-9]+$ ]] && ps -p "$lock_pid" >/dev/null 2>&1; then
      refuse "a start of '${lock_slug:-?}' is still running in $PRIMARY (pid $lock_pid, per $CLOUD_LOCK) — let it finish; if pid $lock_pid is not a feature-start.sh (a reused pid), a human removes that lock"
    fi
    if [[ "$lock_slug" != "$SLUG" ]]; then
      refuse "this checkout holds an unfinished start of '${lock_slug:-?}' on '${lock_branch:-?}'${lock_refused:+ (refused: $lock_refused)} — a container holds one feature: re-run that start, not a new one"
    fi
    if [[ "$LAUNCH_BRANCH" != "$lock_branch" ]]; then
      refuse "the unfinished start of '$SLUG' was on branch '$lock_branch', and this checkout is on '${LAUNCH_BRANCH:-a detached HEAD}' — check out '$lock_branch' and run this again"
    fi
    if [[ -n "$BRANCH_OPT" && "$BRANCH_OPT" != "$lock_branch" ]]; then
      refuse "the unfinished start of '$SLUG' is on branch '$lock_branch', not --branch '$BRANCH_OPT' — re-run it without --branch, or with --branch $lock_branch"
    fi
    RESUME=1
    FEATURE_BRANCH="$lock_branch"
    LAUNCH_BRANCH="${lock_launched:-$lock_branch}"
  else
    FEATURE_BRANCH="$(feature_branch "$SLUG")" \
      || refuse "in the cloud the feature runs on the session's assigned branch, and $PRIMARY is on '${LAUNCH_BRANCH:-a detached HEAD}', the base — name the branch with --branch <name> (the start creates it off origin/$BASE)"
    git check-ref-format --branch "$FEATURE_BRANCH" >/dev/null 2>&1 \
      || refuse "'$FEATURE_BRANCH' is not a valid branch name"
    if [[ "$FEATURE_BRANCH" != "$LAUNCH_BRANCH" ]] \
        && git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$FEATURE_BRANCH"; then
      refuse "--branch '$FEATURE_BRANCH' already exists and is not checked out — the start creates the feature's branch, or uses the one this session is on; it does not switch to another"
    fi
  fi
fi

# ── Keep the worktrees directory out of git ───────────────────────────────────
# The worktree sits inside the primary checkout, so without an ignore entry the primary's
# `git status` lists `.worktrees/` as untracked, and a post-merge capture or any other
# tool reading the primary's status would see it as work. The entry goes in the COMMON git dir's
# info/exclude: per clone, exactly as the worktree is, and nothing any repo tracks
# changes, so a consuming repo has nothing to commit or hand-merge. Idempotent: appended
# only when no line already equals it, and an unterminated last line is closed first so
# an existing entry is never extended. Before `git worktree add`, so the primary is never
# dirty, not even for the length of this run.
COMMON_GIT_DIR="$(cd "$PRIMARY" && cd "$(git rev-parse --git-common-dir)" && pwd)" \
  || refuse "cannot resolve the common git dir of $PRIMARY"
EXCLUDE_FILE="$COMMON_GIT_DIR/info/exclude"
EXCLUDE_ENTRY="/$WORKTREES_DIR_NAME/"
if ! grep -qxF -- "$EXCLUDE_ENTRY" "$EXCLUDE_FILE" 2>/dev/null; then
  mkdir -p "$(dirname "$EXCLUDE_FILE")" || refuse "cannot create $(dirname "$EXCLUDE_FILE")"
  # $(…) strips a trailing newline, so this is non-empty exactly when the last byte is not one.
  if [[ -s "$EXCLUDE_FILE" && -n "$(tail -c 1 "$EXCLUDE_FILE")" ]]; then
    printf '\n' >> "$EXCLUDE_FILE" || refuse "cannot write $EXCLUDE_FILE"
  fi
  printf '%s\n' "$EXCLUDE_ENTRY" >> "$EXCLUDE_FILE" || refuse "cannot write $EXCLUDE_FILE"
  echo "  ignore    $EXCLUDE_ENTRY added to $EXCLUDE_FILE"
fi

# ── Branch and worktree ───────────────────────────────────────────────────────
FETCHED=0
if git -C "$PRIMARY" remote get-url origin >/dev/null 2>&1; then
  if git -C "$PRIMARY" fetch -q origin 2>/dev/null; then
    FETCHED=1
  else
    echo "  warn  git fetch origin failed; branching from the local $BASE"
  fi
fi
# ── The cloud checkout: one feature, nobody's work, and origin/<base> in it ───
# See the header's cloud layout. Before the prune, the branch and the lock, so a refusal
# here has written nothing; the stale-checkout fast-forward last, so it only ever moves a
# clean branch with no commits of its own.
if profile_is_cloud; then
  if git -C "$PRIMARY" show-ref --verify --quiet "refs/remotes/origin/$BASE"; then
    CLOUD_UPSTREAM="origin/$BASE"
  elif git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$BASE"; then
    CLOUD_UPSTREAM="$BASE"
  else
    refuse "base branch '$BASE' exists neither as origin/$BASE nor locally"
  fi
  # A second feature: a start commit this branch carries past the base, or a tracked
  # manifest that names this branch as its own.
  started=""
  while IFS= read -r subject; do
    case "$subject" in
      *"$START_SUBJECT_SUFFIX")
        candidate="${subject%"$START_SUBJECT_SUFFIX"}"
        if [[ "$candidate" =~ $SLUG_PATTERN ]]; then started="$candidate"; break; fi ;;
    esac
  done < <(git -C "$PRIMARY" log --format=%s "$CLOUD_UPSTREAM..HEAD" 2>/dev/null)
  if [[ -z "$started" ]]; then
    while IFS= read -r manifest_rel; do
      case "$manifest_rel" in "$FEATURES_LABEL"/*/README.md) ;; *) continue ;; esac
      other="${manifest_rel#"$FEATURES_LABEL"/}"; other="${other%/README.md}"
      [[ "$other" != */* ]] || continue
      if [[ "$(manifest_branch "$REPO_DIR/$manifest_rel" "")" == "$FEATURE_BRANCH" ]]; then
        started="$other"; break
      fi
    done < <(git -C "$REPO_DIR" ls-files -- "$FEATURES_LABEL" 2>/dev/null)
  fi
  if [[ -n "$started" ]]; then
    refuse "branch '$FEATURE_BRANCH' already carries the feature '$started' — a container pushes one branch, so it holds one feature: finish '$started' here, and start '$SLUG' in a session of its own"
  fi
  if (( ! RESUME )); then
    own="$(git -C "$PRIMARY" rev-list --count "$CLOUD_UPSTREAM..HEAD" 2>/dev/null)"
    if [[ "${own:-0}" != 0 ]]; then
      refuse "'${LAUNCH_BRANCH:-HEAD}' carries $own commit(s) not on $CLOUD_UPSTREAM, newest '$(git -C "$PRIMARY" log -1 --format=%s 2>/dev/null)' — somebody's work; a feature starts from $CLOUD_UPSTREAM in a checkout with nothing of its own"
    fi
    dirty="$(git -C "$PRIMARY" status --porcelain 2>/dev/null | head -n "$DIRTY_PATHS_NAMED" | cut -c4- | tr '\n' ' ')"
    if [[ -n "$dirty" ]]; then
      refuse "$PRIMARY has uncommitted changes (${dirty% }) — somebody's work; commit or remove them, then run this again"
    fi
  fi
  head_sha="$(git -C "$PRIMARY" rev-parse HEAD)"
  upstream_sha="$(git -C "$PRIMARY" rev-parse "$CLOUD_UPSTREAM")"
  if ! git -C "$PRIMARY" merge-base --is-ancestor "$upstream_sha" "$head_sha"; then
    git -C "$PRIMARY" merge-base --is-ancestor "$head_sha" "$upstream_sha" \
      || refuse "'${LAUNCH_BRANCH:-HEAD}' in $PRIMARY has diverged from $CLOUD_UPSTREAM; reconcile it by hand, then run this again"
    git -C "$PRIMARY" merge -q --ff-only "$CLOUD_UPSTREAM" \
      || refuse "could not fast-forward '${LAUNCH_BRANCH:-HEAD}' in $PRIMARY to $CLOUD_UPSTREAM (git's reason is above); nothing was started"
    echo "  updated   ${LAUNCH_BRANCH:-HEAD} ${head_sha:0:8}..${upstream_sha:0:8} in $PRIMARY — it was behind $CLOUD_UPSTREAM"
    echo "            This run may be the old copy of feature-start.sh; nothing was started. Run it again:"
    echo "              $RERUN_CMD"
    exit "$UPDATED_RC"
  fi
fi

# ── A stale primary ───────────────────────────────────────────────────────────
# See the header. Before the prune and the worktree, so a run that stops here has changed
# nothing but main. Local only: in the cloud the primary is on the assigned branch, and
# the block above is this check.
if ! profile_is_cloud && (( FETCHED )) && git -C "$PRIMARY" show-ref --verify --quiet "refs/remotes/$PRIMARY_UPSTREAM"; then
  primary_head="$(git -C "$PRIMARY" rev-parse HEAD)"
  upstream_head="$(git -C "$PRIMARY" rev-parse "$PRIMARY_UPSTREAM")"
  if [[ "$primary_head" != "$upstream_head" ]] \
      && ! git -C "$PRIMARY" merge-base --is-ancestor "$upstream_head" "$primary_head"; then
    primary_branch="$(git -C "$PRIMARY" branch --show-current)"
    [[ "$primary_branch" == "$PRIMARY_BRANCH" ]] \
      || refuse "the primary checkout $PRIMARY is on '${primary_branch:-a detached HEAD}', not $PRIMARY_BRANCH, and is behind $PRIMARY_UPSTREAM — this copy of feature-start.sh may be stale. Put the primary back on $PRIMARY_BRANCH and run it again"
    git -C "$PRIMARY" merge-base --is-ancestor "$primary_head" "$upstream_head" \
      || refuse "$PRIMARY_BRANCH in $PRIMARY has diverged from $PRIMARY_UPSTREAM; reconcile it by hand, then run this again"
    git -C "$PRIMARY" merge -q --ff-only "$PRIMARY_UPSTREAM" \
      || refuse "could not fast-forward $PRIMARY_BRANCH in $PRIMARY to $PRIMARY_UPSTREAM (git's reason is above); nothing was started"
    echo "  updated   $PRIMARY_BRANCH ${primary_head:0:8}..${upstream_head:0:8} in $PRIMARY — it was behind $PRIMARY_UPSTREAM"
    echo "            This run was the old copy of feature-start.sh; nothing was started. Run it again:"
    echo "              $RERUN_CMD"
    exit "$UPDATED_RC"
  fi
fi
# ── Take over this slug's own half-start ──────────────────────────────────────
# After the stale-primary check, so a run that stops there has removed nothing; before the
# prune, so the prune never reports this slug's half-start as some other start's. The
# assessment is repeated: seconds have passed since the first, and a concurrent start of
# this slug caught before its lock write has written it by now (header).
if (( TAKEOVER )); then
  assess_own_half_start || refuse "$HALF_START_WHY"
  if [[ "$LOCK_STATE" == dead ]]; then
    takeover_why="its start (pid $LOCK_PID) is gone"
  else
    takeover_why="it has no start lock, so no start is running it"
  fi
  drop_half_or_merged "$WORKTREE" "$SLUG"
  case $? in
    0) ;;
    2) refuse "took the half-start's worktree $WORKTREE away, but git branch $PRUNE_DELETE_FLAG refused branch '$SLUG'" ;;
    *) refuse "git worktree remove refused $WORKTREE, so the half-start of '$SLUG' could not be taken over" ;;
  esac
  echo "  takeover  took over the abandoned start of $SLUG — branch unmoved since its creation, worktree clean, and $takeover_why; starting it afresh"
fi
# ── Prune the features that have merged ───────────────────────────────────────
# The whole of post-merge teardown, done here rather than by a close step, because the
# next start is the first moment anyone is looking and the fetch above has just refreshed
# the evidence. Only worktrees under R/.worktrees/ are candidates — never the primary,
# never a checkout somewhere else — and only when the branch has MERGED, below. Nothing
# is committed and nothing is pushed.
#
# **Merged** is two facts, not one: the branch is an ancestor of $PRUNE_MERGED_INTO, AND
# it has moved since it was created. Ancestry alone is true of every branch that has no
# commits of its own — which is every feature another session's start has just made with
# `git worktree add -b`, from then until its `S: start` commit lands after the hook and
# the gate. Two starts at once used to delete each other's new worktrees that way
# (2026-09-22). Where a branch was created is git's own record of it: the oldest entry in
# the branch's reflog, which `git worktree add -b` writes and `git branch -D` deletes with
# the branch, so a reused slug starts a record of its own. A branch still at that commit
# has merged nothing. A branch whose oldest entry is not the creation record
# ($BRANCH_CREATED_REFLOG_PREFIX) — no reflog, or one gc has expired past its start — is
# kept with a line saying so, since the prune never deletes what it cannot prove.
#
# **An abandoned half-start** is the one unmoved branch it takes: still at its creation
# commit AND holding a start lock whose PID is gone (start_lock_state → dead) — a start of
# some slug that was refused or interrupted after its `worktree add` (header, "Taking over
# a half-start"). A live lock is a start running now, and so is — for the length of one
# write — a missing lock, so both stay silent, as before.
#
# prune_one <worktree path> <branch>
prune_one() {
  local wt="$1" branch="$2" label created reason
  [[ -n "$wt" && -n "$branch" ]] || return 0
  case "$wt" in "$WORKTREES_ROOT"/*) ;; *) return 0 ;; esac
  git -C "$PRIMARY" merge-base --is-ancestor "$branch" "$PRUNE_MERGED_INTO" 2>/dev/null || return 0
  label="${wt#"$PRIMARY"/}"
  created="$(branch_creation "$branch")"
  if [[ -z "$created" ]]; then
    echo "  kept      $label — an ancestor of $PRUNE_MERGED_INTO, but branch $branch's reflog no longer records where it was created, so it cannot be shown to have commits of its own"
    return 0
  fi
  reason="merged into $PRUNE_MERGED_INTO"
  if [[ "$(git -C "$PRIMARY" rev-parse "refs/heads/$branch")" == "$created" ]]; then
    # Silent, like any unmerged worktree, unless its start is provably dead: otherwise this
    # is a feature being started right now.
    start_lock_state "$wt"
    [[ "$LOCK_STATE" == dead ]] || return 0
    reason="an abandoned start, unmoved since its creation, whose start (pid $LOCK_PID) is gone"
  fi
  # Uncommitted work in a merged worktree is work the merge did not carry, and in a
  # half-start it is somebody's inspection. Say so and leave it: the next start will offer
  # to take it again once it is committed or dropped.
  if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
    echo "  kept      $label — $reason, but has uncommitted changes"
    return 0
  fi
  # $PRUNE_DELETE_FLAG is -D, not -d, and that is deliberate: the merge-base check above
  # has already proven this branch is an ancestor of $PRUNE_MERGED_INTO, so `-d`'s own
  # check is both redundant and the WRONG one — it judges "merged" against the branch's
  # upstream or the primary's HEAD, either of which lags origin/main whenever the PR
  # merged on the forge and nobody pulled, and it refuses there. That left the worktree
  # gone and the branch behind. A failure now is a real one (a branch checked out
  # somewhere else), so it still gets a line of its own rather than a claimed deletion.
  drop_half_or_merged "$wt" "$branch"
  case $? in
    0) echo "  pruned    $label and branch $branch ($reason)" ;;
    2) echo "  pruned    $label; kept branch $branch — git branch $PRUNE_DELETE_FLAG refused it" ;;
    *) echo "  kept      $label — git worktree remove refused it" ;;
  esac
}
if git -C "$PRIMARY" show-ref --verify --quiet "refs/remotes/$PRUNE_MERGED_INTO"; then
  # `git worktree list --porcelain` prints one blank-line-separated block per worktree:
  # `worktree <path>`, `HEAD <sha>`, then `branch refs/heads/<name>` unless it is
  # detached. Read it pairwise — bash 3.2 has no associative array to collect it in — and
  # flush the last block after the loop, since the final one may carry no trailing blank.
  prune_wt=""; prune_branch=""
  while IFS= read -r prune_line; do
    case "$prune_line" in
      "worktree "*)          prune_one "$prune_wt" "$prune_branch"; prune_wt="${prune_line#worktree }"; prune_branch="" ;;
      "branch refs/heads/"*) prune_branch="${prune_line#branch refs/heads/}" ;;
    esac
  done < <(git -C "$PRIMARY" worktree list --porcelain 2>/dev/null)
  prune_one "$prune_wt" "$prune_branch"
fi

if git -C "$PRIMARY" show-ref --verify --quiet "refs/remotes/origin/$BASE"; then
  START_POINT="origin/$BASE"
elif git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$BASE"; then
  START_POINT="$BASE"
else
  refuse "base branch '$BASE' exists neither as origin/$BASE nor locally"
fi
if ! profile_is_cloud; then
  create_checkout "$SLUG" "$START_POINT" || refuse "git worktree add failed"
  # The start lock, at once: from here to the `S: start` commit this run is a half-start,
  # and the lock is what tells a later start — of this slug or any — whether it is still
  # running (header, "Taking over a half-start").
  wt_admin="$(git -C "$WORKTREE" rev-parse --absolute-git-dir 2>/dev/null)"
  [[ -n "$wt_admin" ]] || refuse "cannot resolve the admin dir of the new worktree $WORKTREE; it is left in place without a start lock"
  if ! printf '%s=%s\n%s=%s\n' "$START_LOCK_PID_KEY" "$$" "$START_LOCK_STARTED_KEY" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      > "$wt_admin/$START_LOCK_NAME"; then
    refuse "cannot write the start lock $wt_admin/$START_LOCK_NAME; the worktree is left at $WORKTREE"
  fi
  START_LOCK="$wt_admin/$START_LOCK_NAME"
  echo "  branch    $SLUG off $START_POINT"
  echo "  worktree  $WORKTREE"
else
  # The cloud: the container is the worktree (header). A resumed start is already on its
  # branch; a fresh one is either on it already (the assigned branch) or cuts it now.
  if (( RESUME )); then
    echo "  resume    an earlier start of $SLUG on $FEATURE_BRANCH stopped${lock_refused:+ (refused: $lock_refused)} and its pid ${lock_pid:-?} is gone — resuming at the setup hook; nothing is deleted"
    echo "  branch    $FEATURE_BRANCH, as that start left it"
  elif [[ "$FEATURE_BRANCH" == "$LAUNCH_BRANCH" ]]; then
    echo "  branch    $FEATURE_BRANCH — the branch this session is on, at $START_POINT"
  else
    create_checkout "$SLUG" "$START_POINT" || refuse "git checkout -b $FEATURE_BRANCH $START_POINT failed in $PRIMARY"
    echo "  branch    $FEATURE_BRANCH off $START_POINT"
  fi
  # The lock (header): written whole, a resumed start's included, so it names THIS pid;
  # launched_on is what a later resume reads router or coordinator from.
  if ! printf '%s=%s\n%s=%s\n%s=%s\n%s=%s\n%s=%s\n' \
      "$START_LOCK_PID_KEY" "$$" "$START_LOCK_STARTED_KEY" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      "$START_LOCK_SLUG_KEY" "$SLUG" "$START_LOCK_BRANCH_KEY" "$FEATURE_BRANCH" \
      "$START_LOCK_LAUNCHED_KEY" "$LAUNCH_BRANCH" > "$CLOUD_LOCK"; then
    refuse "cannot write the start lock $CLOUD_LOCK; $PRIMARY is left on $FEATURE_BRANCH"
  fi
  START_LOCK="$CLOUD_LOCK"
  echo "  checkout  $WORKTREE — in the cloud the container is the worktree"
fi

# ── Hook, then gate, both inside the new worktree ─────────────────────────────
if [[ -x "$WT_REPO_DIR/$HOOK_LABEL" ]]; then
  if ( cd "$WORKTREE" && "$WT_REPO_DIR/$HOOK_LABEL" ); then
    echo "  hook      $HOOK_LABEL ran"
  else
    refuse "$HOOK_LABEL exited non-zero; the worktree is left at $WORKTREE for inspection"
  fi
else
  echo "  hook      none ($HOOK_LABEL absent or not executable)"
fi
# The fence's `gate` key (design §7): green only when the gate ran here and was; skipped
# otherwise — --no-gate, or no gate script to run — so a feature started on an unverified
# base says so in its record. The gate runs under GATE_RESUME (design §8): a re-run of a
# refused start on the same tree skips the checks that already passed.
GATE_RECORD="$GATE_RECORD_SKIPPED"
if (( RUN_GATE )); then
  if [[ -x "$WT_REPO_DIR/$GATE_SCRIPT_LABEL" ]]; then
    if ! ( cd "$WT_REPO_DIR" && GATE_RESUME="$GATE_RESUME_ON" "$WT_REPO_DIR/$GATE_SCRIPT_LABEL" >/dev/null 2>&1 ); then
      refuse "$GATE_SCRIPT_LABEL reported its environment unusable; the worktree is left at $WORKTREE"
    fi
    verdict="$(awk '/^# VERDICT/{getline; print; exit}' "$WT_REPO_DIR/$GATE_REPORT_LABEL" 2>/dev/null)"
    if [[ "$verdict" != "all checks passed" ]]; then
      refuse "the gate is not green on $START_POINT — verdict: '${verdict:-no report}'. Fix the base first, or pass --no-gate; the worktree is left at $WORKTREE"
    fi
    GATE_RECORD="$GATE_RECORD_GREEN"
    echo "  gate      all checks passed"
  else
    echo "  gate      none ($GATE_SCRIPT_LABEL absent; recorded as $GATE_RECORD_SKIPPED) — pass --no-gate to silence this"
  fi
else
  echo "  gate      skipped (--no-gate)"
fi

# ── Manifest and review stub ──────────────────────────────────────────────────
NOW="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
SESSION=""
if (( PIN )); then SESSION="$ROUTER_SESSION"; fi
# Router or coordinator (header): launched on the feature's own branch is the coordinator.
COORDINATOR=0
if [[ -n "$LAUNCH_BRANCH" && "$LAUNCH_BRANCH" == "$FEATURE_BRANCH" ]]; then COORDINATOR=1; fi
# The window's `from`: the clock, unless this session is the coordinator — then its own
# first transcript instant, since the capture's branch route selects a session by its
# start and this one began before the feature existed (header; manifest.py
# session-start, which prints it truncated to the millisecond and is written here as
# printed). One warning, naming the remedy, when that cannot be read.
WINDOW_FROM="$NOW"
FROM_NOTE=""
if (( COORDINATOR )); then
  first_instant=""
  if [[ -n "$ROUTER_SESSION" ]]; then
    first_instant="$(python3 -B "$WT_AT/analysis/manifest.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$SLUG" \
      session-start "$ROUTER_SESSION" 2>/dev/null)"
  fi
  if [[ -n "$first_instant" ]]; then
    WINDOW_FROM="$first_instant"
    FROM_NOTE=", session $ROUTER_SESSION's first instant"
  else
    if [[ -n "$ROUTER_SESSION" ]]; then
      from_why="no transcript of session $ROUTER_SESSION was found"
    else
      from_why="no session id is set (\$CLAUDE_CODE_SESSION_ID, --session)"
    fi
    echo "  warn      this session is the coordinator, but $from_why; from is the clock, $NOW — if the capture leaves the session's head unclaimed, move it back with: python3 $WT_AT/analysis/manifest.py ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$SLUG set-window-from <its first instant> --session <id>"
  fi
fi
# One rule, both modes: a new feature's stub is always 01 (self/PROJECT_FACTS.md,
# AGENT_PLANS.md → "Plan file format"). This corpus used to number its plans as one
# sequence across every feature instead, read off the corpus with `find | sed | sort -n`;
# two features started from the same base both saw the same highest number and both got
# it, twice, on 2026-09-17 — the sequence assumed only one feature would ever be
# mid-start. Numbering is per feature from here on, exactly as a consuming repo already
# did.
NN="01"
STEM="$NN-review-opus"
session_args=()
if [[ -n "$SESSION" ]]; then session_args=(--session "$SESSION"); fi
# -B: the interpreter must leave no analysis/__pycache__ behind in the new worktree.
# The first commit on the branch is the manifest and nothing else, and an untracked
# byte-cache directory would be swept into the next `git add -A` (or, in a repo whose
# .gitignore predates it, committed) as part of the feature.
FEATURE_DIR="$WT_FEATURES/$SLUG"
# A resumed cloud start keeps a manifest and a stub an earlier run already wrote (header:
# nothing is deleted); every other start writes both into a directory that is new.
if (( RESUME )) && [[ -f "$FEATURE_DIR/README.md" ]]; then
  WINDOW_FROM="$(python3 -B "$WT_AT/analysis/manifest.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$SLUG" get session_window.from 2>/dev/null)"
  FROM_NOTE=", kept from the earlier start"
elif ! python3 -B "$WT_AT/analysis/manifest.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$SLUG" init \
    --method "$METHOD" --branch "$FEATURE_BRANCH" --base "$BASE" --from "$WINDOW_FROM" \
    --profile "$(profile_name)" --gate "$GATE_RECORD" --plan "$STEM" \
    ${session_args[@]+"${session_args[@]}"} >/dev/null; then
  refuse "could not write the manifest; the worktree is left at $WORKTREE"
fi
mkdir -p "$FEATURE_DIR/review/incomplete"
if [[ ! -e "$FEATURE_DIR/review/incomplete/$STEM.md" ]]; then
cat > "$FEATURE_DIR/review/incomplete/$STEM.md" <<STUB
# $NN — review: $SLUG

$TODO_MARKER — write this brief BEFORE the build, from the spec, never from the builder's
report: what the feature was supposed to do, the diff to read, the contracts to hold it
to, and that "no findings" is a legitimate verdict (AGENT_PLANS.md → "Review plans").
run-review.sh refuses to run a brief that still contains the marker above.

## What the feature was supposed to do

## The diff

Base is \`$BASE\`. \`git diff $BASE...HEAD --stat\`, then the full diff.

## Contracts to hold it to

## Verdict
STUB
fi
echo "  manifest  ${FEATURE_DIR#"$WORKTREE"/}/README.md  (method $METHOD, from $WINDOW_FROM$FROM_NOTE${SESSION:+, session $SESSION pinned})"
echo "  review    ${FEATURE_DIR#"$WORKTREE"/}/review/incomplete/$STEM.md  (stub — $TODO_MARKER)"

# ── The routing record ────────────────────────────────────────────────────────
# Written for THIS session — the router — INSIDE the feature directory the commit below
# already adds, so the router-to-feature link is in git before the transcript it is
# derived from can expire, and no two features ever write one path
# (self/DESIGN-2026-09-18-ledger-and-routing.md §1; it took a path of its own, and a
# `git add` of its own, until then). Never a refusal: a transcript that has not been
# flushed, or has aged out, yields a record with this slug and no figures plus one
# warning, and the start goes on.
# -B, for the reason the manifest call gives: no analysis/__pycache__ in the new worktree.
#
# **Not under --pin.** One owner per session: a pin claims the session for this feature
# outright, so it is this feature's coordinator and not a router, and a record for it
# would put its cost into the Routing table AND into this feature's frozen total — both
# sides of the `--all` fraction (self/features/shell-write-rewrite, part 2). The pin is
# the link. analysis/routing.py's `split_pinned` skips any such record already on disk.
#
# **Nor for the coordinator** (header; design §3): a session launched on the feature's own
# branch — every cloud session on its assigned branch — is claimed by that branch under
# LIFECYCLE.md rule 1, with no pin and nothing to route.
if (( PIN )); then
  echo "  routing   none (--pin: session ${SESSION:-(none)} is this feature's, never also a router)"
elif (( COORDINATOR )); then
  echo "  routing   none (this session was launched on $FEATURE_BRANCH, the feature's branch: it is the feature's coordinator, claimed by that branch with no pin)"
elif [[ -n "$ROUTER_SESSION" ]]; then
  if python3 -B "$WT_AT/$ROUTING_MODULE" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} \
      --session "$ROUTER_SESSION" --slug "$SLUG" --primary "$PRIMARY" >/dev/null; then
    echo "  routing   ${FEATURE_DIR#"$WORKTREE"/}/$ROUTING_RECORD_NAME  (router $ROUTER_SESSION, not pinned)"
  else
    echo "  warn      could not write the routing record for session $ROUTER_SESSION"
  fi
else
  echo "  routing   none (no session id in \$CLAUDE_CODE_SESSION_ID and no --session)"
fi

( cd "$WORKTREE" && git add "${FEATURE_DIR#"$WORKTREE"/}" \
    && git commit -q -m "$SLUG: start" ) \
  || refuse "could not commit the feature directory in $WORKTREE"
echo "  commit    $SLUG: start"
# No longer a half-start: the branch has moved, which is what every reader checks first.
rm -f "$START_LOCK"
START_LOCK=""

# ── Open the coordinator session inside the worktree ──────────────────────────
# The repo owns how a session is opened — a terminal, a tab, an editor — so this runs
# plans/open-session.sh (self/open-session.sh under --self) and judges nothing but its
# exit code. Advisory: a hook that fails leaves a started feature, not a refused start.
if (( OPEN )); then
  if [[ -x "$WT_REPO_DIR/$OPEN_HOOK_LABEL" ]]; then
    if "$WT_REPO_DIR/$OPEN_HOOK_LABEL" "$WORKTREE"; then
      echo "  open      $OPEN_HOOK_LABEL ran for $WORKTREE"
    else
      echo "  warn      $OPEN_HOOK_LABEL exited non-zero; open the session by hand"
    fi
  else
    echo "  warn      $OPEN_HOOK_LABEL is absent or not executable; open the session by hand"
  fi
fi

# ── Next ──────────────────────────────────────────────────────────────────────
echo ""
echo "Next, in this order:"
echo "  1. Replace $TODO_MARKER in review/incomplete/$STEM.md with the review brief, from the spec."
# One place, not two. A session is billed to the branch of the directory it was launched
# in (LIFECYCLE.md, rule 1), so a coordinator launched in the worktree is claimed by
# branch $SLUG and needs no pin — and this session, which started the feature, stays a
# router with no claim on it.
if profile_is_cloud && (( COORDINATOR )); then
  echo "  2. Coordinate from this session: it is on $FEATURE_BRANCH, the feature's branch, so it is"
  echo "     the coordinator, claimed by that branch with no pin."
elif profile_is_cloud; then
  echo "  2. This session was launched on ${LAUNCH_BRANCH:-a detached HEAD}, not $FEATURE_BRANCH, so it is this feature's"
  echo "     router. A container has no other session to coordinate from: if this one builds the"
  echo "     feature, pin it — python3 $WT_AT/analysis/manifest.py ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$SLUG pin-session ${ROUTER_SESSION:-<id>}"
elif (( OPEN )); then
  echo "  2. Coordinate in the session --open just launched, in $WORKTREE."
else
  echo "  2. Coordinate from inside the worktree, where the feature is claimed by branch $SLUG"
  echo "     with no pin. Launch a session there — or re-run this with --open, which runs"
  echo "     $OPEN_HOOK_LABEL for you:"
  echo "       $WORKTREE"
fi
if [[ -n "$SESSION" ]]; then
  echo "     --pin also pinned session $SESSION in the manifest, so a session in the primary"
  echo "     checkout is claimed too, and every delegate it spawns must be pinned in"
  echo "     \"subagents\" while its transcript exists."
fi
echo "  3. Every delegate brief opens with:  feature: $REPO_NAME/$SLUG"
# The review pass only records the round's verdict and stops; feature-close.sh is what
# opens the PR and captures the cost on the branch now (LIFECYCLE.md → steps 5 and 6),
# and the next start prunes this worktree once the branch has merged.
echo "  4. Review: run-review.sh ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$SLUG records the verdict and stops. On a"
echo "     clean verdict, run feature-close.sh ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$SLUG from the worktree — it opens"
echo "     the PR, captures the cost on the branch, and requests the merge last."
echo "     Merge the PR — that is the last step; nothing runs after it."
