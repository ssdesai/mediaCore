#!/usr/bin/env bash
set -uo pipefail

# Close a feature: feature-close.sh [--self] <slug> [--recapture] [--keep-worktree] [--no-push]
#
# The other half of feature-start.sh (LIFECYCLE.md), run by hand from the PRIMARY checkout
# after the feature's PR has merged and after every session that cost it has ended. No
# model is involved: this is bookkeeping and teardown, and every judgement it makes is a
# refusal. In order, this script:
#
#   1. refuses to run from a worktree's copy, with the primary on any branch but main, or
#      with the primary dirty — the cost commit below must be this run's files and nothing
#      else, and that is only checkable from a clean start;
#   2. fetches origin, refuses unless <slug> is an ancestor of origin/main ("not merged"),
#      and pulls main forward, so the manifest it reads is the merged one;
#   3. lists the unclaimed delegates whose briefs name this feature —
#      `capture_planning.py --list-subagents --unclaimed --for <repo>/<slug>`, which keeps
#      the rows whose brief names exactly that `(repo, slug)` pair, so a delegate briefed
#      for `<slug>-two` is not one of this feature's and a `<repo>/<slug>` too long for
#      the table's pin column is still one — and STOPS if any of them is not already
#      pinned: an unpinned delegate is cost the capture below would silently drop, and its
#      transcript is expiring. The unclaimed top-level sessions are printed for the human
#      and stop nothing — a session is claimed by the branch of the directory it was
#      launched in, so the list is context, not a verdict;
#   4. carries the worktree's trailing timing stamps home. Every runner pass stamps
#      `pass_end` from its EXIT trap, and run-review.sh stamps `pr_opened` — carrying the
#      PR URL that analysis/report.py's Time table reads — after the PR hook has already
#      committed and pushed, so those last lines exist only in the worktree and no branch
#      will ever carry them. timing.jsonl is append-only JSON lines: the lines the
#      primary's copy does not already hold are appended to it, deduped by exact line, so
#      a re-run, or a second close after a --keep-worktree one, never doubles them;
#   5. captures, and stops on a refusal (nothing matched, a frozen prior record) with the
#      manifest untouched and step 4's append rolled back, so the primary is exactly as
#      this run found it and the refusal can be acted on and the close re-run — a refusal
#      that left the carried lines behind made the primary dirty, which is what step 1
#      then refuses on, so the first refusal caused a second one that named a record the
#      human must not simply discard. The lines are still in the worktree; the re-run
#      carries them again;
#   6. writes the report — now over the complete timing record — then prints what
#      planning.json claims: id, how it was selected, where it was launched, cost, so the
#      number is read before it is quoted;
#   7. only now stamps session_window.to. After the capture, never before: a `to` of now
#      excludes nothing that exists now, and a capture that refused must leave the window
#      open for the next attempt;
#   8. commits exactly the cost files as `<slug>: cost records` and pushes main (--no-push
#      holds it back); anything else dirty is named and the run stops rather than sweeping
#      a stranger's work into a cost commit;
#   9. removes the worktree and the local branch, in that order (--keep-worktree keeps
#      both). The worktree's own timing.jsonl is restored first: step 4 put its trailing
#      lines on main, so the modification is now a duplicate of the record rather than the
#      only copy of it, and discarding it is what lets a plain `git worktree remove` —
#      which must go on refusing a modified file — succeed. A worktree holding anything
#      else is left in place with a warning. The remote branch is left to the forge's
#      delete-on-merge setting. Capture ran first by construction: a removed worktree is
#      still matched by the path derived from the slug, but the order is the guarantee
#      that its transcripts were read while the branch record was fresh.
#
# Every python here runs with -B: the interpreter must leave no analysis/__pycache__ in
# the primary, or step 8 would find it dirty and refuse.
#
# Exit codes: 2 usage; 1 any refusal.

USAGE_RC=2
REFUSED_RC=1
MAIN_BRANCH="main"
# The harness's own records, relative to the feature directory: everything the capture,
# the report, the window stamp and the runners' timing write there. It is what the cost
# commit may carry and what the teardown treats as its own to discard; anything else
# dirty, in the primary or in the worktree, is somebody's work in progress and this
# script neither commits nor deletes it.
COST_FILES="README.md planning.json report.md report.json timing.jsonl"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
SELF_FLAG=()
if [[ "${1:-}" == "--self" ]]; then SELF_FLAG=(--self); shift; fi

usage() {
  echo "usage: feature-close.sh [--self] <slug> [--recapture] [--keep-worktree] [--no-push]" >&2
  exit "$USAGE_RC"
}
refuse() { echo "  refused  $*" >&2; exit "$REFUSED_RC"; }

# stray_paths <`git status --porcelain` output>
#
# The dirty paths that are NOT this feature's cost records, one per line — empty output
# means everything dirty is a file this script or the harness wrote under the feature
# directory. Two callers with the same question: the cost commit, which refuses to sweep
# up a stranger's work, and the teardown, which decides whether a worktree's leftovers
# are the harness's own or somebody's.
stray_paths() {
  local line path name
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path="${line:3}"                       # `XY <path>`; nothing here is ever a rename
    name=""
    case "$path" in "$FEATURE_REL"/*) name="${path#"$FEATURE_REL"/}" ;; esac
    if [[ -z "$name" ]]; then echo "$path"; continue; fi
    case " $COST_FILES " in
      *" $name "*) ;;
      *) echo "$path" ;;
    esac
  done <<<"$1"
}

SLUG="${1:-}"; [[ -n "$SLUG" ]] || usage; shift
RECAPTURE=0; KEEP_WORKTREE=0; PUSH=1
while (( $# )); do
  case "$1" in
    --recapture)     RECAPTURE=1; shift ;;
    --keep-worktree) KEEP_WORKTREE=1; shift ;;
    --no-push)       PUSH=0; shift ;;
    *) usage ;;
  esac
done

# ── Where ─────────────────────────────────────────────────────────────────────
# The same resolution feature-start.sh does: REPO_DIR is this script's repo root in the
# two modes, the git toplevel above it is the primary checkout, and the worktree path is
# derived from the slug and nothing else.
PRIMARY="$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null)" || refuse "$REPO_DIR is not inside a git repository"
if [[ "$(git -C "$PRIMARY" rev-parse --git-dir)" != "$(git -C "$PRIMARY" rev-parse --git-common-dir)" ]]; then
  refuse "this copy is inside a worktree ($PRIMARY); run the primary checkout's feature-close.sh — it is $(dirname "$(git -C "$PRIMARY" rev-parse --git-common-dir)")/${SCRIPT_DIR#"$PRIMARY"/}"
fi
REL_REPO="${REPO_DIR#"$PRIMARY"}"; REL_REPO="${REL_REPO#/}"          # "" or agentTooling
WORKTREE="$PRIMARY-$SLUG"
FEATURE_DIR="$FEATURES_DIR/$SLUG"
FEATURE_REL="${REL_REPO:+$REL_REPO/}$FEATURES_LABEL/$SLUG"           # as `git status` prints it
MANIFEST="$FEATURE_DIR/README.md"
TIMING_REL="$FEATURE_REL/timing.jsonl"                               # same path in both trees
WT_TIMING="$WORKTREE/$TIMING_REL"
REPO_NAME="$(basename "$PRIMARY")"
MANIFEST_PY=(python3 -B "$SCRIPT_DIR/analysis/manifest.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$SLUG")
CAPTURE_PY=(python3 -B "$SCRIPT_DIR/analysis/capture_planning.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"})

# ── Refusals ──────────────────────────────────────────────────────────────────
CURRENT_BRANCH="$(git -C "$PRIMARY" branch --show-current)"
[[ "$CURRENT_BRANCH" == "$MAIN_BRANCH" ]] || refuse "the primary checkout is on '$CURRENT_BRANCH', not $MAIN_BRANCH; close a feature from $MAIN_BRANCH in $PRIMARY"
[[ -z "$(git -C "$PRIMARY" status --porcelain)" ]] || refuse "$PRIMARY is dirty; commit or discard its changes first, so the cost commit below is this feature's records and nothing else"

# ── Merged? ───────────────────────────────────────────────────────────────────
MAIN_REF="$MAIN_BRANCH"
HAS_ORIGIN=0
if git -C "$PRIMARY" remote get-url origin >/dev/null 2>&1; then
  HAS_ORIGIN=1
  git -C "$PRIMARY" fetch -q origin 2>/dev/null || echo "  warn      git fetch origin failed; reading the local $MAIN_BRANCH"
  if git -C "$PRIMARY" show-ref --verify --quiet "refs/remotes/origin/$MAIN_BRANCH"; then
    MAIN_REF="origin/$MAIN_BRANCH"
  fi
fi
if git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$SLUG"; then
  MERGE_REF="$SLUG"
elif git -C "$PRIMARY" show-ref --verify --quiet "refs/remotes/origin/$SLUG"; then
  MERGE_REF="origin/$SLUG"
else
  refuse "no branch '$SLUG' locally or on origin — nothing to close"
fi
if ! git -C "$PRIMARY" merge-base --is-ancestor "$MERGE_REF" "$MAIN_REF"; then
  refuse "'$SLUG' is not merged into $MAIN_REF — open its PR and merge it before closing"
fi
echo "  merged    $MERGE_REF is an ancestor of $MAIN_REF"
if (( HAS_ORIGIN )) && [[ "$MAIN_REF" == "origin/$MAIN_BRANCH" ]]; then
  git -C "$PRIMARY" pull -q --ff-only origin "$MAIN_BRANCH" \
    || refuse "git pull --ff-only failed; reconcile $MAIN_BRANCH in $PRIMARY by hand, then run this again"
fi
echo "  primary   $PRIMARY on $MAIN_BRANCH, clean and up to date"
# Only now: the manifest this run reads is the merged one. Before the pull the primary's
# copy of the feature directory is whatever main happened to hold, which for a feature
# started by feature-start.sh is nothing at all — its first commit is on the branch.
[[ -f "$MANIFEST" ]] || refuse "no manifest at $MANIFEST even though '$SLUG' is merged — is that the right slug?"

# ── Everything still unclaimed ────────────────────────────────────────────────
# The window's `from` is the only date worth scanning back to: nothing older can be this
# feature's, and a full scan of ~/.claude/projects is slow and noisy.
SINCE="$("${MANIFEST_PY[@]}" get session_window.from)"
SINCE="${SINCE%%T*}"
SINCE_ARGS=()
if [[ -n "$SINCE" ]]; then SINCE_ARGS=(--since "$SINCE"); fi

echo ""
echo "=== unclaimed delegates briefed for $REPO_NAME/$SLUG since ${SINCE:-the beginning} ==="
# --for does the naming test inside the tool, on the (repo, slug) pair each brief carries.
# Reading it off the printed table instead was wrong twice over: a delegate briefed for
# `<slug>-two` is a substring match and is not this feature's, and a `<repo>/<slug>`
# longer than the table's 26-character pin column never matched at all — a silent miss,
# and an unpinned delegate is never priced.
DELEGATES="$("${CAPTURE_PY[@]}" --list-subagents --unclaimed --for "$REPO_NAME/$SLUG" ${SINCE_ARGS[@]+"${SINCE_ARGS[@]}"} 2>&1)"
echo "$DELEGATES"
# Every row above is one of this feature's delegates, so a row not already pinned by it is
# cost the capture below would drop on the floor — a delegate is priced only by an explicit
# `subagents` pin. `get subagents` prints the pinned ids as a JSON array, so a quoted id is
# a membership test with no parsing. A row is a row by its leading date: the header, the
# closing summary and the nothing-found line are not, and neither is an error message.
PINNED_AGENTS="$("${MANIFEST_PY[@]}" get subagents)"
STRAY_AGENTS=""
while IFS= read -r row; do
  case "$row" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ *) ;;
    *) continue ;;
  esac
  agent="$(awk '{print $2}' <<<"$row")"
  case "$PINNED_AGENTS" in *"\"$agent\""*) continue ;; esac
  STRAY_AGENTS="$STRAY_AGENTS  $agent"$'\n'
done <<<"$DELEGATES"
if [[ -n "$STRAY_AGENTS" ]]; then
  echo ""
  echo "  these delegates name $REPO_NAME/$SLUG and no feature claims them:"
  printf '%s' "$STRAY_AGENTS"
  refuse "pin them in $FEATURE_REL/README.md as \"subagents\": [\"<agent-id>\", ...] and run this again — an unpinned delegate is never priced"
fi

echo ""
echo "=== unclaimed sessions since ${SINCE:-the beginning} (for your eyes; nothing here stops the close) ==="
"${CAPTURE_PY[@]}" --list-sessions --unclaimed ${SINCE_ARGS[@]+"${SINCE_ARGS[@]}"} 2>&1

# ── Carry the worktree's trailing timing stamps home ──────────────────────────
# The last lines of a feature's wall-clock record are written after the PR hook has
# already committed and pushed — `pr_opened` by run-review.sh, carrying the PR URL
# report.py's Time table reads, and `pass_end` from every runner's EXIT trap — so they
# live in the worktree and no branch will ever carry them. They are the record, not
# leftovers. timing.jsonl is append-only JSON lines, which is what makes carrying them
# safe: append the lines the primary's copy does not already hold, in order, matching on
# the whole line, so a re-run or a second close after a --keep-worktree one carries
# nothing twice. Before the capture, so the report below reads the complete record — and
# rolled back if that capture refuses, since the primary must be left exactly as this run
# found it or the next run refuses on the dirt this one made.
CARRIED=0
# The primary was verified clean above, so its copy is either HEAD's byte for byte or
# absent — which is what makes the rollback below a two-case affair and neither case a
# guess about what was there.
PRIMARY_TIMING_EXISTED=0
if [[ -f "$PRIMARY/$TIMING_REL" ]]; then PRIMARY_TIMING_EXISTED=1; fi
if [[ -f "$WT_TIMING" ]]; then
  while IFS= read -r timing_line; do
    [[ -n "$timing_line" ]] || continue
    if ! grep -qxF -- "$timing_line" "$PRIMARY/$TIMING_REL" 2>/dev/null; then
      printf '%s\n' "$timing_line" >> "$PRIMARY/$TIMING_REL"
      CARRIED=$(( CARRIED + 1 ))
    fi
  done < "$WT_TIMING"
  echo ""
  echo "  timing    carried $CARRIED trailing stamp(s) home from $TIMING_REL in the worktree"
fi

# rollback_carry — undo the append above, for a refusal path only. A refused close that
# left the primary dirty blocked its own re-run on the dirty-primary refusal, which named
# a file the human must not simply discard and did not say what had written it. Nothing is
# lost: every carried line is still in the worktree, and the next run carries it again.
# `git checkout --` here undoes this script's own append to a file it found identical to
# HEAD; when the primary had no copy at all, this script created it, so it is removed.
rollback_carry() {
  (( CARRIED )) || return 0
  if (( PRIMARY_TIMING_EXISTED )); then
    git -C "$PRIMARY" checkout -- "$TIMING_REL" 2>/dev/null
  else
    rm -f "$PRIMARY/$TIMING_REL"
  fi
  echo "  timing    rolled back the $CARRIED carried stamp(s); $TIMING_REL is as it was"
}

# ── Capture, report, and what was claimed ─────────────────────────────────────
echo ""
echo "=== capture ==="
CAPTURE_ARGS=()
if (( RECAPTURE )); then CAPTURE_ARGS=(--recapture); fi
if ! "${CAPTURE_PY[@]}" "$SLUG" ${CAPTURE_ARGS[@]+"${CAPTURE_ARGS[@]}"}; then
  rollback_carry
  CARRY_NOTE=""
  if (( CARRIED )); then
    CARRY_NOTE=", and the $CARRIED timing stamp(s) carried above were rolled back — the worktree still holds them and the next run carries them again"
  fi
  refuse "capture refused — no planning.json was written, session_window.to is still null$CARRY_NOTE; $PRIMARY is exactly as this run found it, so act on the refusal above and run this again"
fi

echo ""
echo "=== report ==="
if ! python3 -B "$SCRIPT_DIR/analysis/report.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$SLUG"; then
  refuse "report.py failed; planning.json is written but the report is not"
fi

echo ""
echo "=== what planning.json claims ==="
"${MANIFEST_PY[@]}" claimed || refuse "could not read what planning.json claims"

# ── Close the window ──────────────────────────────────────────────────────────
echo ""
if ! "${MANIFEST_PY[@]}" set-window-to; then
  refuse "could not stamp session_window.to in $MANIFEST"
fi

# ── Commit, push ──────────────────────────────────────────────────────────────
DIRTY="$(git -C "$PRIMARY" status --porcelain)"
if [[ -z "$DIRTY" ]]; then
  echo "  commit    nothing changed — no cost records to commit"
else
  STRAY="$(stray_paths "$DIRTY")"
  if [[ -n "$STRAY" ]]; then
    echo "  these dirty paths are not $SLUG's cost records:" >&2
    while IFS= read -r path; do echo "    $path" >&2; done <<<"$STRAY"
    refuse "commit or discard them, then run this again — the capture and the report are written and session_window.to is stamped, so the re-run picks up from the commit"
  fi
  # Every dirty path is one of this feature's records, so the feature directory stages
  # exactly them and nothing that is not already dirty.
  git -C "$PRIMARY" add -- "$FEATURE_REL" || refuse "git add failed in $PRIMARY"
  git -C "$PRIMARY" commit -q -m "$SLUG: cost records" || refuse "git commit failed in $PRIMARY"
  echo "  commit    $SLUG: cost records"
  git -C "$PRIMARY" show --name-only --format= HEAD | sed 's/^/              /'
fi

if (( ! PUSH )); then
  echo "  push      skipped (--no-push) — $MAIN_BRANCH is ahead of origin"
elif (( ! HAS_ORIGIN )); then
  echo "  push      skipped — this repository has no origin"
elif git -C "$PRIMARY" push -q origin "$MAIN_BRANCH"; then
  echo "  push      $MAIN_BRANCH -> origin"
else
  refuse "could not push $MAIN_BRANCH; the cost commit is local"
fi

# ── Teardown ──────────────────────────────────────────────────────────────────
# Advisory, not a refusal: the record is written and pushed by here, and a worktree that
# will not come away is a leftover to deal with, not a reason to call the close failed.
if (( KEEP_WORKTREE )); then
  echo "  worktree  kept at $WORKTREE (--keep-worktree), branch $SLUG kept"
else
  if [[ -d "$WORKTREE" ]]; then
    # The one file a green pass always leaves modified here is timing.jsonl, and its
    # trailing lines are on main as of the carry above — so the modification is a
    # duplicate now, and restoring the file is the difference between a plain
    # `git worktree remove` and one that has to be forced. This is the only ref-touching
    # git command in this script, it runs on the feature's own worktree, and it discards
    # nothing that is not already committed to main.
    if [[ -f "$WT_TIMING" ]]; then
      git -C "$WORKTREE" checkout -- "$TIMING_REL" 2>/dev/null
    fi
    # Anything still dirty is either the harness's other records — which the merged
    # branch makes safe to drop — or somebody's work, which keeps the worktree.
    WT_DIRTY="$(git -C "$WORKTREE" status --porcelain 2>/dev/null)"
    REMOVE_ARGS=()
    if [[ -n "$WT_DIRTY" && -z "$(stray_paths "$WT_DIRTY")" ]]; then REMOVE_ARGS=(--force); fi
    if git -C "$PRIMARY" worktree remove ${REMOVE_ARGS[@]+"${REMOVE_ARGS[@]}"} "$WORKTREE"; then
      echo "  worktree  removed $WORKTREE${REMOVE_ARGS[0]+ (discarding uncommitted records already carried home)}"
    else
      echo "  warn      $WORKTREE has uncommitted or untracked files that are not $SLUG's"
      echo "            records, and was left in place. Deal with them, then:"
      echo "            git -C $PRIMARY worktree remove $WORKTREE && git -C $PRIMARY branch -d $SLUG"
    fi
  else
    git -C "$PRIMARY" worktree prune
    echo "  worktree  $WORKTREE is already gone"
  fi
  if git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$SLUG"; then
    if git -C "$PRIMARY" branch -d "$SLUG" >/dev/null 2>&1; then
      echo "  branch    deleted $SLUG (the remote branch is the forge's, on its delete-on-merge setting)"
    else
      echo "  warn      could not delete branch $SLUG — it is still checked out somewhere, or not merged"
    fi
  fi
fi

echo ""
echo "$SLUG is closed. The numbers above are what this feature cost; quote them from"
echo "$FEATURE_REL/report.md, which is now on $MAIN_BRANCH."
