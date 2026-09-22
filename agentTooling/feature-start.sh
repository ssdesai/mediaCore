#!/usr/bin/env bash
set -uo pipefail

# Start a feature: feature-start.sh [--self] <slug> [--method direct|plans|hand]
#   [--base <branch>] [--no-gate] [--pin] [--session <id>] [--open]
#
# The only sanctioned way to create a feature branch or worktree (LIFECYCLE.md). The
# rule, for slug S in a repo whose primary checkout is R:
#
#   slug      ^[a-z0-9]+(-[a-z0-9]+)*$     kebab-case, no slash, no owner prefix
#   branch    S
#   worktree  R/.worktrees/S               inside the primary checkout, kept out of git
#
# Inside rather than beside R because a session launched in R can then reach the worktree
# with no access outside its own folder. Features started before this layout keep their
# sibling R-S until they merge; feature-capture.sh and the capture tooling handle both.
#
# Everything cost capture needs is then derived from the slug — the branch to match, the
# worktree path, the transcript directory a session launched there is filed under — with
# nothing to configure and nothing an agent can drift from. In order, this script:
#
#   1. refuses a slug that fails the pattern, a branch or worktree that already exists,
#      and being run from a worktree's copy (the worktree's copy is the wrong copy);
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
#      longer records where it was created is kept, with one line saying so.
#      That is the whole of post-merge teardown. A worktree with uncommitted work is
#      left in place with one line saying so, an unmerged one is never touched, and
#      nothing is committed or pushed;
#   4. adds the worktree R/.worktrees/S on a new branch S off origin/<base> (default
#      main; `--base` records a stacked feature's base for the PR);
#   5. runs the repo's setup hook inside it — plans/worktree-setup.sh, or
#      self/worktree-setup.sh under --self — for the venv, npm install, dev port;
#   6. runs the repo's gate inside it and stops unless the verdict is green: a red base
#      is the implementer's context spent on someone else's failures (`--no-gate` skips);
#   7. writes the manifest from templates/plans/features/TEMPLATE.md with its fence
#      filled (branches [S], base, `from` now in UTC with a Z, `to` null, and no pin),
#      and a review-brief stub carrying @@TODO@@ that run-review.sh refuses to run until
#      it is replaced;
#   8. writes the ROUTING RECORD for the session that ran it, INSIDE that feature
#      directory — plans/features/S/routing.json, self/features/ under --self — through
#      analysis/routing.py, from that session's own transcript; unless --pin, since a
#      pinned session is this feature's and never also a router;
#   9. commits the feature directory, routing record and all, on S as `S: start`;
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
# no repo tracks. On a refusal after step 4 the worktree is left in place for inspection.
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
resolve_roots "${1:-}"
SELF_FLAG=()
if [[ "${1:-}" == "--self" ]]; then SELF_FLAG=(--self); shift; fi

usage() {
  echo "usage: feature-start.sh [--self] <slug> [--method direct|plans|hand] [--base <branch>] [--no-gate] [--pin] [--session <id>] [--open]" >&2
  exit "$USAGE_RC"
}
refuse() { echo "  refused  $*" >&2; exit "$REFUSED_RC"; }

SLUG="${1:-}"; [[ -n "$SLUG" ]] || usage; shift
METHOD="$DEFAULT_METHOD"; BASE="$DEFAULT_BASE"; RUN_GATE=1; PIN=0; SESSION_OPT=""; OPEN=0
while (( $# )); do
  # Every value-taking flag checks its arity first: `shift 2` with one argument left
  # returns non-zero WITHOUT shifting, and there is no `set -e` here to stop on it, so a
  # truncated flag would spin this loop forever instead of printing the usage.
  case "$1" in
    --method)  (( $# >= 2 )) || usage; METHOD="$2"; shift 2 ;;
    --base)    (( $# >= 2 )) || usage; BASE="$2"; shift 2 ;;
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
WORKTREE="$PRIMARY/$WORKTREES_DIR_NAME/$SLUG"
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

git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$SLUG" && refuse "branch '$SLUG' already exists"
[[ -e "$WORKTREE" ]] && refuse "$WORKTREE already exists"

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
# ── A stale primary ───────────────────────────────────────────────────────────
# See the header. Before the prune and the worktree, so a run that stops here has changed
# nothing but main.
if (( FETCHED )) && git -C "$PRIMARY" show-ref --verify --quiet "refs/remotes/$PRIMARY_UPSTREAM"; then
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
# prune_one <worktree path> <branch>
prune_one() {
  local wt="$1" branch="$2" label oldest created
  [[ -n "$wt" && -n "$branch" ]] || return 0
  case "$wt" in "$WORKTREES_ROOT"/*) ;; *) return 0 ;; esac
  git -C "$PRIMARY" merge-base --is-ancestor "$branch" "$PRUNE_MERGED_INTO" 2>/dev/null || return 0
  label="${wt#"$PRIMARY"/}"
  oldest="$(git -C "$PRIMARY" reflog show --format='%H %gs' "refs/heads/$branch" 2>/dev/null | tail -n 1)"
  case "${oldest#* }" in
    "$BRANCH_CREATED_REFLOG_PREFIX"*) created="${oldest%% *}" ;;
    *)
      echo "  kept      $label — an ancestor of $PRUNE_MERGED_INTO, but branch $branch's reflog no longer records where it was created, so it cannot be shown to have commits of its own"
      return 0 ;;
  esac
  # Silent, like any unmerged worktree: this is a feature being started right now.
  [[ "$(git -C "$PRIMARY" rev-parse "refs/heads/$branch")" != "$created" ]] || return 0
  # Uncommitted work in a merged worktree is work the merge did not carry. Say so and
  # leave it: the next start will offer to take it again once it is committed or dropped.
  if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
    echo "  kept      $label — merged into $PRUNE_MERGED_INTO but has uncommitted changes"
    return 0
  fi
  if git -C "$PRIMARY" worktree remove "$wt" >/dev/null 2>&1; then
    # $PRUNE_DELETE_FLAG is -D, not -d, and that is deliberate: the merge-base check above
    # has already proven this branch is an ancestor of $PRUNE_MERGED_INTO, so `-d`'s own
    # check is both redundant and the WRONG one — it judges "merged" against the branch's
    # upstream or the primary's HEAD, either of which lags origin/main whenever the PR
    # merged on the forge and nobody pulled, and it refuses there. That left the worktree
    # gone and the branch behind. A failure now is a real one (a branch checked out
    # somewhere else), so it still gets a line of its own rather than a claimed deletion.
    if git -C "$PRIMARY" branch "$PRUNE_DELETE_FLAG" "$branch" >/dev/null 2>&1; then
      echo "  pruned    $label and branch $branch (merged into $PRUNE_MERGED_INTO)"
    else
      echo "  pruned    $label; kept branch $branch — git branch $PRUNE_DELETE_FLAG refused it"
    fi
  else
    echo "  kept      $label — git worktree remove refused it"
  fi
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
git -C "$PRIMARY" worktree add -q "$WORKTREE" -b "$SLUG" "$START_POINT" || refuse "git worktree add failed"
echo "  branch    $SLUG off $START_POINT"
echo "  worktree  $WORKTREE"

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
if (( RUN_GATE )); then
  if [[ -x "$WT_REPO_DIR/$GATE_SCRIPT_LABEL" ]]; then
    if ! ( cd "$WT_REPO_DIR" && "$WT_REPO_DIR/$GATE_SCRIPT_LABEL" >/dev/null 2>&1 ); then
      refuse "$GATE_SCRIPT_LABEL reported its environment unusable; the worktree is left at $WORKTREE"
    fi
    verdict="$(awk '/^# VERDICT/{getline; print; exit}' "$WT_REPO_DIR/$GATE_REPORT_LABEL" 2>/dev/null)"
    if [[ "$verdict" != "all checks passed" ]]; then
      refuse "the gate is not green on $START_POINT — verdict: '${verdict:-no report}'. Fix the base first, or pass --no-gate; the worktree is left at $WORKTREE"
    fi
    echo "  gate      all checks passed"
  else
    echo "  gate      none ($GATE_SCRIPT_LABEL absent) — pass --no-gate to silence this"
  fi
else
  echo "  gate      skipped (--no-gate)"
fi

# ── Manifest and review stub ──────────────────────────────────────────────────
NOW="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
SESSION=""
if (( PIN )); then SESSION="$ROUTER_SESSION"; fi
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
if ! python3 -B "$WT_AT/analysis/manifest.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$SLUG" init \
    --method "$METHOD" --branch "$SLUG" --base "$BASE" --from "$NOW" --plan "$STEM" \
    ${session_args[@]+"${session_args[@]}"} >/dev/null; then
  refuse "could not write the manifest; the worktree is left at $WORKTREE"
fi
FEATURE_DIR="$WT_FEATURES/$SLUG"
mkdir -p "$FEATURE_DIR/review/incomplete"
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
echo "  manifest  ${FEATURE_DIR#"$WORKTREE"/}/README.md  (method $METHOD, from $NOW${SESSION:+, session $SESSION pinned})"
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
if (( PIN )); then
  echo "  routing   none (--pin: session ${SESSION:-(none)} is this feature's, never also a router)"
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
if (( OPEN )); then
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
