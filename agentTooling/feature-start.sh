#!/usr/bin/env bash
set -uo pipefail

# Start a feature: feature-start.sh [--self] <slug> [--method direct|plans|hand]
#   [--base <branch>] [--no-gate] [--no-pin] [--session <id>]
#
# The only sanctioned way to create a feature branch or worktree (LIFECYCLE.md). The
# rule, for slug S in a repo whose primary checkout is R:
#
#   slug      ^[a-z0-9]+(-[a-z0-9]+)*$     kebab-case, no slash, no owner prefix
#   branch    S
#   worktree  R-S                          a sibling directory of the primary checkout
#
# Everything cost capture needs is then derived from the slug — the branch to match, the
# worktree path, the transcript directory a session launched there is filed under — with
# nothing to configure and nothing an agent can drift from. In order, this script:
#
#   1. refuses a slug that fails the pattern, a branch or worktree that already exists,
#      and being run from a worktree's copy (the worktree's copy is the wrong copy);
#   2. fetches origin and adds the worktree R-S on a new branch S off origin/<base>
#      (default main; `--base` records a stacked feature's base for the PR);
#   3. runs the repo's setup hook inside it — plans/worktree-setup.sh, or
#      self/worktree-setup.sh under --self — for the venv, npm install, dev port;
#   4. runs the repo's gate inside it and stops unless the verdict is green: a red base
#      is the implementer's context spent on someone else's failures (`--no-gate` skips);
#   5. writes the manifest from templates/plans/features/TEMPLATE.md with its fence
#      filled (branches [S], base, `from` now in UTC with a Z, `to` null, the running
#      session pinned from $CLAUDE_CODE_SESSION_ID so a planning session that began on
#      main is claimed by id), and a review-brief stub carrying @@TODO@@ that
#      run-review.sh refuses to run until it is replaced;
#   6. commits the feature directory on S as `S: start`;
#   7. prints where to launch the coordinator session and the line every brief opens with.
#
# The primary checkout is never touched: nothing here checks out, stashes or commits in
# it, so it need not be clean and nothing else running in it is disturbed. On a refusal
# after step 2 the worktree is left in place for inspection.
#
# Exit codes: 2 usage; 1 any refusal.

USAGE_RC=2
REFUSED_RC=1
SLUG_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'
KNOWN_METHODS="direct plans hand"
DEFAULT_METHOD="direct"
DEFAULT_BASE="main"
TODO_MARKER="@@TODO@@"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
SELF_FLAG=()
if [[ "${1:-}" == "--self" ]]; then SELF_FLAG=(--self); shift; fi

usage() {
  echo "usage: feature-start.sh [--self] <slug> [--method direct|plans|hand] [--base <branch>] [--no-gate] [--no-pin] [--session <id>]" >&2
  exit "$USAGE_RC"
}
refuse() { echo "  refused  $*" >&2; exit "$REFUSED_RC"; }

SLUG="${1:-}"; [[ -n "$SLUG" ]] || usage; shift
METHOD="$DEFAULT_METHOD"; BASE="$DEFAULT_BASE"; RUN_GATE=1; PIN=1; SESSION_OPT=""
while (( $# )); do
  # Every value-taking flag checks its arity first: `shift 2` with one argument left
  # returns non-zero WITHOUT shifting, and there is no `set -e` here to stop on it, so a
  # truncated flag would spin this loop forever instead of printing the usage.
  case "$1" in
    --method)  (( $# >= 2 )) || usage; METHOD="$2"; shift 2 ;;
    --base)    (( $# >= 2 )) || usage; BASE="$2"; shift 2 ;;
    --no-gate) RUN_GATE=0; shift ;;
    --no-pin)  PIN=0; shift ;;
    --session) (( $# >= 2 )) || usage; SESSION_OPT="$2"; shift 2 ;;
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
WORKTREE="$PRIMARY-$SLUG"
WT_REPO_DIR="$WORKTREE${REL_REPO:+/$REL_REPO}"
WT_AT="$WORKTREE${REL_AT:+/$REL_AT}"
WT_FEATURES="$WT_REPO_DIR/$FEATURES_LABEL"
HOOK_LABEL="${GATE_SCRIPT_LABEL%/gate.sh}/worktree-setup.sh"
REPO_NAME="$(basename "$PRIMARY")"

git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$SLUG" && refuse "branch '$SLUG' already exists"
[[ -e "$WORKTREE" ]] && refuse "$WORKTREE already exists"

# ── Branch and worktree ───────────────────────────────────────────────────────
if git -C "$PRIMARY" remote get-url origin >/dev/null 2>&1; then
  git -C "$PRIMARY" fetch -q origin 2>/dev/null || echo "  warn  git fetch origin failed; branching from the local $BASE"
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
if (( PIN )); then SESSION="${SESSION_OPT:-${CLAUDE_CODE_SESSION_ID:-}}"; fi
if (( SELF_MODE )); then
  # The self corpus numbers plans as one sequence (self/PROJECT_FACTS.md); a consuming
  # repo numbers per feature from 01.
  last_nn="$(find "$WT_FEATURES" -name '[0-9][0-9]-*.md' 2>/dev/null | sed 's|.*/||; s|^\([0-9][0-9]\).*|\1|' | sort -n | tail -1)"
  # 10#: the sequence is zero-padded, and bash reads a leading zero as octal — `08` and
  # `09` are then "value too great for base" and the manifest never gets written.
  NN="$(printf '%02d' $(( 10#${last_nn:-0} + 1 )))"
else
  NN="01"
fi
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

( cd "$WORKTREE" && git add "${FEATURE_DIR#"$WORKTREE"/}" && git commit -q -m "$SLUG: start" ) \
  || refuse "could not commit the feature directory in $WORKTREE"
echo "  commit    $SLUG: start"

# ── Next ──────────────────────────────────────────────────────────────────────
echo ""
echo "Next, in this order:"
echo "  1. Replace $TODO_MARKER in review/incomplete/$STEM.md with the review brief, from the spec."
echo "  2. Launch the coordinator session INSIDE the worktree, not here:"
echo "       cd $WORKTREE && claude"
echo "     A session is billed to the branch of the directory it was launched in."
echo "  3. Every delegate brief opens with:  feature: $REPO_NAME/$SLUG"
echo "  4. After the PR merges, from the primary checkout:  feature-close.sh ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} $SLUG"
