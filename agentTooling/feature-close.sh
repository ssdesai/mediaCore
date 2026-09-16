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
#      transcript is expiring. A delegate this manifest already pins is not in that list
#      (the pin IS the claim), so the "Pin each in …" advice appears only when something
#      is left to pin; where nothing is, this prints one `pinned` line counting what the
#      manifest holds, because "no unclaimed delegates" alone reads as "this feature had
#      none" for a feature whose whole build was one. The unclaimed top-level sessions are
#      printed for the human and stop nothing — a session is claimed by the branch of the
#      directory it was launched in, so the list is context, not a verdict;
#   4. carries the worktree's trailing timing stamps home. Every runner pass stamps
#      `pass_end` from its EXIT trap, and run-review.sh stamps `pr_opened` — carrying the
#      PR URL that analysis/report.py's Time table reads — after the PR hook has already
#      committed and pushed, so those last lines exist only in the worktree and no branch
#      will ever carry them. timing.jsonl is append-only JSON lines: the lines the
#      primary's copy does not already hold are appended to it, deduped by exact line, so
#      a re-run, or a second close after a --keep-worktree one, never doubles them;
#   5. recovers what the CLI never priced, over THIS feature only
#      (`analysis/recover_attempts.py --for <slug>`). An attempt whose stream carried no
#      `result` event has a null total_cost_usd forever — a killed run, or a run that
#      exited 0 while its stream lost the event — and recover_attempts.py can price it
#      from the session transcript. It ran only in the weekly sweep before, so a feature
#      closed the day it merged committed the zero and the transcript then aged out. It
#      runs BEFORE the capture so the report below reads the recovered figures, and its
#      failures are reported and never fatal: a plan whose transcript is gone is named
#      here and again in the report, which is news to act on, not a reason to abandon a
#      close whose PR has already merged. The sidecars it rewrites are the harness's own
#      records (COST_FILES / is_cost_usage_path above), so the commit carries them;
#   6. stamps session_window.to from EVIDENCE, and before the capture. The evidence is
#      `capture_planning.py --last-branch-instant <slug>`: one second past the last
#      instant of the sessions this feature's `branches` and `session_window` select and
#      of their subagents, pins deliberately not consulted. Before the capture because the
#      capture's share split divides a multiply-claimed session by the windows its
#      claimants hold — stamping afterwards freezes this feature's own record against a
#      window that is still open, and a `to` of now hands it an equal share of the
#      coordinator for every hour since its work actually stopped. With no branch session
#      the bound falls back to this run's clock, as it always did, and says so in one
#      line. Under --recapture the stamp is `--tighten`: a bound already written is
#      replaced only by an EARLIER one, which is the repair path for every `to` this
#      script stamped at close time before, and never widened — a wider bound re-admits
#      sessions a neighbouring window may already have chained onto. That widen refusal,
#      identified by manifest.py's exit code for it and by nothing else, warns and
#      continues: the bound it declined to widen is the one already published. EVERY other
#      stamp failure is fatal — a fence with no `to` key, a bound that will not parse, a
#      tighten that would empty the window — because carrying on would capture, commit,
#      push and delete the branch of a feature whose window is still open, which is the
#      permanent double-count. The refusal quotes what set-window-to printed and rolls
#      step 4's append and step 5's sidecars back, exactly as step 7's does;
#   7. captures, and stops on a refusal (nothing matched, a frozen prior record) with
#      step 6's stamp, step 4's append AND step 5's recovered sidecars all rolled back,
#      so the primary is exactly as this run found it and the refusal can be acted on and
#      the close re-run — a refusal that left any of them behind made the primary dirty,
#      which is what step 1 then refuses on, so the first refusal caused a second one that
#      named a record the human must not simply discard. Nothing is lost: the timing lines
#      are still in the worktree, the recovered dollars are still derivable from the
#      transcripts, and the evidence is still in the transcripts too, so the re-run does
#      all three again;
#   8. writes the report — now over the complete timing record and the recovered costs —
#      then prints what planning.json claims: id, how it was selected, where it was
#      launched, cost, so the number is read before it is quoted;
#   9. commits exactly the cost files as `<slug>: cost records` and pushes main (--no-push
#      holds it back); anything else dirty is named and the run stops rather than sweeping
#      a stranger's work into a cost commit;
#  10. removes the worktree and the local branch, in that order (--keep-worktree keeps
#      both). The worktree is whichever one holds the branch — R/.worktrees/<slug>, or
#      the sibling R-<slug> a feature started before that layout still has — so a legacy
#      feature closes with no flag (step 4's carry reads the same one). The worktree's
#      own timing.jsonl is restored first: step 4 put its trailing
#      lines on main, so the modification is now a duplicate of the record rather than the
#      only copy of it, and discarding it is what lets a plain `git worktree remove` —
#      which must go on refusing a modified file — succeed. A worktree holding anything
#      else is left in place with a warning. The remote branch is left to the forge's
#      delete-on-merge setting. Capture ran first by construction: a removed worktree is
#      still matched by the path derived from the slug, but the order is the guarantee
#      that its transcripts were read while the branch record was fresh.
#
# Every python here runs with -B: the interpreter must leave no analysis/__pycache__ in
# the primary, or step 9 would find it dirty and refuse.
#
# Exit codes: 2 usage; 1 any refusal.

USAGE_RC=2
REFUSED_RC=1
MAIN_BRANCH="main"
# The directory under the primary checkout that holds every feature worktree
# (LIFECYCLE.md); feature-start.sh and analysis/capture_planning.py each hold the same
# name in one constant of their own, and the three move together.
WORKTREES_DIR_NAME=".worktrees"
# The harness's own records, relative to the feature directory: everything the capture,
# the report, the window stamp and the runners' timing write there. It is what the cost
# commit may carry and what the teardown treats as its own to discard; anything else
# dirty, in the primary or in the worktree, is somebody's work in progress and this
# script neither commits nor deletes it.
COST_FILES="README.md planning.json report.md report.json timing.jsonl"
# The same list, for the per-plan cost sidecars, which are not flat names: a usage.json
# sits at <queue>/<state>/<stem>.usage.json under the feature directory, and one level
# deeper again for an archived batch. The recovery step below rewrites them in place, so
# without this the cost commit would refuse its own run's output as a stranger's work.
#
# These are the runner's own two sets, not a guess: QUEUE is set to exactly one of the
# three by run-plans.sh, run-verify.sh and run-review.sh, and the four state directories
# are what finalize_plan routes a plan between (plan-runner-lib.sh, resolve_feature's
# comment, spells the layout out). analysis/report.py holds the same two sets as
# QUEUE_DIRS and STATE_DIRS, and its find_queue_segment reads the layout from the other
# end — up from the sidecar to the nearest state directory, whose parent must be a queue
# — which is why the archived-batch level is safe to allow below the state directory but
# nothing is allowed above the queue.
#
# Matching on the names, rather than on any path ending in .usage.json, is what makes the
# refusal mean something: this script's whole contract is that it does not sweep up a
# stranger's work, and a .usage.json somewhere else under the feature directory has never
# been anything the harness wrote. Every one of the 574 sidecars in the four corpora
# today is <queue>/<state>/<stem>.usage.json exactly.
COST_USAGE_QUEUES="auto verify review"
COST_USAGE_STATES="incomplete inprogress complete failed"

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
# is_cost_usage_path <feature-relative path>
#
# Whether a path is one of the per-plan cost sidecars above: <queue>/<state>/… ending in
# .usage.json, with <queue> and <state> from the runner's own two sets. What follows the
# state directory is left unconstrained, so an archived batch's extra branch-named level
# still matches — the same rule find_queue_segment applies walking the other way.
is_cost_usage_path() {
  local name="$1" queue rest state
  case "$name" in *.usage.json) ;; *) return 1 ;; esac
  case "$name" in */*/*) ;; *) return 1 ;; esac      # needs a queue AND a state above it
  queue="${name%%/*}"
  rest="${name#*/}"
  state="${rest%%/*}"
  case " $COST_USAGE_QUEUES " in *" $queue "*) ;; *) return 1 ;; esac
  case " $COST_USAGE_STATES " in *" $state "*) ;; *) return 1 ;; esac
  return 0
}

stray_paths() {
  local line path name
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path="${line:3}"                       # `XY <path>`; nothing here is ever a rename
    name=""
    case "$path" in "$FEATURE_REL"/*) name="${path#"$FEATURE_REL"/}" ;; esac
    if [[ -z "$name" ]]; then echo "$path"; continue; fi
    case " $COST_FILES " in
      *" $name "*) continue ;;
    esac
    if is_cost_usage_path "$name"; then continue; fi
    echo "$path"
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
# two modes, and the git toplevel above it is the primary checkout. The worktree is found
# below, after the refusal that needs only these.
PRIMARY="$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null)" || refuse "$REPO_DIR is not inside a git repository"
if [[ "$(git -C "$PRIMARY" rev-parse --git-dir)" != "$(git -C "$PRIMARY" rev-parse --git-common-dir)" ]]; then
  refuse "this copy is inside a worktree ($PRIMARY); run the primary checkout's feature-close.sh — it is $(dirname "$(git -C "$PRIMARY" rev-parse --git-common-dir)")/${SCRIPT_DIR#"$PRIMARY"/}"
fi
REL_REPO="${REPO_DIR#"$PRIMARY"}"; REL_REPO="${REL_REPO#/}"          # "" or agentTooling
# Where this feature's worktree is. git is the record of that — the worktree holding
# refs/heads/<slug> — and asking it finds the legacy sibling R-<slug> of a feature started
# before worktrees moved inside the primary as readily as R/.worktrees/<slug>, with no
# flag and no guess. With no worktree holding the branch (removed by hand, or the branch
# already deleted) the path is derived instead: the nested one if it exists, else the
# legacy one if that does, else the nested one, for the teardown's "already gone" line.
NESTED_WORKTREE="$PRIMARY/$WORKTREES_DIR_NAME/$SLUG"
LEGACY_WORKTREE="$PRIMARY-$SLUG"
WORKTREE="$(git -C "$PRIMARY" worktree list --porcelain 2>/dev/null \
  | awk -v ref="branch refs/heads/$SLUG" '/^worktree /{wt=substr($0,10)} $0==ref{print wt; exit}')"
if [[ -z "$WORKTREE" ]]; then
  if [[ -d "$NESTED_WORKTREE" ]]; then
    WORKTREE="$NESTED_WORKTREE"
  elif [[ -d "$LEGACY_WORKTREE" ]]; then
    WORKTREE="$LEGACY_WORKTREE"
  else
    WORKTREE="$NESTED_WORKTREE"
  fi
fi
FEATURE_DIR="$FEATURES_DIR/$SLUG"
FEATURE_REL="${REL_REPO:+$REL_REPO/}$FEATURES_LABEL/$SLUG"           # as `git status` prints it
MANIFEST="$FEATURE_DIR/README.md"
MANIFEST_REL="$FEATURE_REL/README.md"                                # as `git cat-file <ref>:<path>` addresses it
# The subject feature-start.sh gives a feature's first commit (LIFECYCLE.md → step 2).
# Once both branch refs are gone this is the only thing left in history that says this
# feature was ever started in this checkout.
START_COMMIT_SUBJECT="$SLUG: start"
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
# closed_feature_on_main — the ancestry the branch refusal exists to check, read
# without a branch: this feature's manifest is tracked on $MAIN_REF, and its
# `<slug>: start` commit is in $MAIN_REF's history (which is what "is an ancestor of"
# means, so finding it there IS the check). Both, never either: a manifest alone could
# have been copied in by hand, and a matching subject alone could be somebody's commit
# message.
#
# Only --recapture consults it. A successful close deletes the local branch by design
# and a forge with delete-on-merge takes the remote one, so the repair path for an
# already-closed feature worked only while the remote branch happened to survive — which
# it did for all nine affected features by luck, not design (../self/BACKLOG.md). The
# non-recapture path is unchanged: there is nothing to repair there, and no reason to
# relax a refusal that catches a typo'd slug.
closed_feature_on_main() {
  git -C "$PRIMARY" cat-file -e "$MAIN_REF:$MANIFEST_REL" 2>/dev/null || return 1
  [[ -n "$(git -C "$PRIMARY" rev-list --max-count=1 --fixed-strings \
             --grep="$START_COMMIT_SUBJECT" "$MAIN_REF" 2>/dev/null)" ]]
}

MERGE_REF=""
if git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$SLUG"; then
  MERGE_REF="$SLUG"
elif git -C "$PRIMARY" show-ref --verify --quiet "refs/remotes/origin/$SLUG"; then
  MERGE_REF="origin/$SLUG"
fi
if [[ -n "$MERGE_REF" ]]; then
  if ! git -C "$PRIMARY" merge-base --is-ancestor "$MERGE_REF" "$MAIN_REF"; then
    refuse "'$SLUG' is not merged into $MAIN_REF — open its PR and merge it before closing"
  fi
  echo "  merged    $MERGE_REF is an ancestor of $MAIN_REF"
elif (( RECAPTURE )) && closed_feature_on_main; then
  echo "  merged    no branch left; $MANIFEST_REL and '$START_COMMIT_SUBJECT' are on $MAIN_REF"
else
  refuse "no branch '$SLUG' locally or on origin — nothing to close"
fi
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
# Nothing left to pin. Say what IS pinned instead of nothing: the list above has just
# printed "no unclaimed subagent transcripts briefed for …", and on its own that reads
# as "this feature had no delegates" for a feature whose whole build was one. Counting
# the quoted ids in the JSON array needs no parser — an agent id contains no quote.
PINNED_COUNT="$(tr ',' '\n' <<<"$PINNED_AGENTS" | grep -c '"')"
if (( PINNED_COUNT > 0 )); then
  echo "  pinned    $PINNED_COUNT delegate(s) already pinned in the manifest"
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

# ── Recover what the CLI never priced ─────────────────────────────────────────
# An attempt whose stream carried no `result` event has `total_cost_usd: null` forever —
# the CLI never learned the figure. recover_attempts.py prices it from the session
# transcript instead, and its sidecar records WHY it was unpriced (`result_event`,
# plan-runner-lib.sh). Two things bring an attempt here: a killed run, and a run that
# exited 0 while its stream lost the event — the second is what recorded three merged
# reviews at $0, and the close is the only moment that catches it, because the weekly
# sweep may not run before the transcript ages out of ~/.claude/projects/.
#
# Scoped with --for: this close speaks for this feature, and a whole-tree walk here would
# rewrite sidecars in features nobody asked about — which the commit below would then
# either sweep up or refuse on. Never fatal, always reported: the PR has merged, and a
# transcript that is gone is news for the report, not a reason to abandon the close.
# Before the capture, so the report reads the recovered figures; rolled back if that
# capture refuses, for the same reason the carry above is.
echo ""
echo "=== recover ==="
if ! python3 -B "$SCRIPT_DIR/analysis/recover_attempts.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} --for "$SLUG"; then
  echo "  warn      recovery reported a failure; continuing — the report below names any plan still unpriced"
fi
# The primary was verified clean above, so any usage.json dirty under the feature
# directory now is one this step rewrote. That is what makes the rollback exact rather
# than a guess, and recovery only ever rewrites files that already existed, so
# `git checkout --` puts every one of them back.
# `cut -c4-` is the pipeline twin of stray_paths' `${line:3}` — porcelain is `XY <path>`.
# Deliberately not a `case` inside this command substitution: bash 3.2 mis-parses the
# unbalanced `)` of a case pattern there, and the error goes to stderr while the
# assignment quietly succeeds. `|| true` because grep exits 1 on no match, which is the
# ordinary outcome and not a failure.
RECOVERED_PATHS="$(git -C "$PRIMARY" status --porcelain -- "$FEATURE_REL" 2>/dev/null \
  | cut -c4- | grep '\.usage\.json$' || true)"

# rollback_recovery — undo the rewrite above, for a refusal path only, exactly as
# rollback_carry undoes the timing append. Nothing is lost: every recovered figure is
# derived from a session transcript that is still there, and the re-run derives it again.
rollback_recovery() {
  [[ -n "$RECOVERED_PATHS" ]] || return 0
  local recovered_count=0
  while IFS= read -r recovered_path; do
    [[ -n "$recovered_path" ]] || continue
    git -C "$PRIMARY" checkout -- "$recovered_path" 2>/dev/null
    recovered_count=$(( recovered_count + 1 ))
  done <<<"$RECOVERED_PATHS"
  echo "  recover   rolled back the $recovered_count recovered sidecar(s); the feature directory is as it was"
}

# ── Close the window, from evidence, BEFORE the capture ───────────────────────
# The bound the capture is about to split a shared session by. Reading it off the
# transcripts rather than off the wall clock is what stops four features started from one
# coordinator from all closing at the same instant, their windows nesting inside each
# other while each draws an equal share of that coordinator for hours after its own work
# stopped (../self/BACKLOG.md, the entry this closes). The CLI writes nothing, opens no
# ledger and runs no git command — --recapture reaches here with the branch long deleted.
#
# Stderr is dropped and an empty answer is the documented no-evidence case, so a feature
# with no branch session falls back to this run's clock exactly as before — announced,
# because a bound taken from the clock and one taken from evidence mean different things
# and nothing else in the output distinguishes them.
echo ""
echo "=== window ==="
EVIDENCE="$("${CAPTURE_PY[@]}" --last-branch-instant "$SLUG" 2>/dev/null)"
if [[ -n "$EVIDENCE" ]]; then
  echo "  window    evidence: last branch instant + 1s = $EVIDENCE"
else
  EVIDENCE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "  window    no branch session — to stamped at close time ($EVIDENCE)"
fi
# --tighten only under --recapture. A plain close stamps a null bound and leaves a set one
# alone, which is what it has always done; the repair path is the one that may move a
# bound, and only ever inwards. The WIDEN refusal, and only that one, is not this close's
# business to fail on: the bound it declined to widen is the one already published, the
# capture below is what the repair run came for, and stopping would leave the feature with
# no way forward but a hand edit. Every other refusal IS fatal — set-window-to also
# refuses a fence with no `to` key at all, a bound that will not parse as an instant, and
# a tighten that would empty the window, and each of those leaves the window OPEN on a
# feature this run is about to capture, commit, push and delete the branch of. That is the
# permanent double-count AGENT_PLANS.md warns about, so the run stops and says what
# set-window-to actually printed rather than naming a widen that never happened.
#
# Matched on the exit code, which manifest.py gives the widen refusal alone
# (WIDEN_REFUSED_EXIT). Not on the message, and not on "non-zero": argparse exits 2 on a
# usage error — a flag this script passed wrongly — and reading that as a declined widen
# would close the feature with an open window and no clue why.
WIDEN_REFUSED_RC=3
TIGHTEN_ARGS=()
if (( RECAPTURE )); then TIGHTEN_ARGS=(--tighten); fi
# Captured rather than streamed, so the refusal below can quote it; echoed either way, so
# the ordinary `old -> new` and `already set` lines still reach the human.
STAMP_OUT="$("${MANIFEST_PY[@]}" set-window-to ${TIGHTEN_ARGS[@]+"${TIGHTEN_ARGS[@]}"} "$EVIDENCE" 2>&1)"
STAMP_RC=$?
if [[ -n "$STAMP_OUT" ]]; then echo "$STAMP_OUT"; fi
if (( STAMP_RC == WIDEN_REFUSED_RC )); then
  echo "  warn      session_window.to was left as it is — a bound is never widened"
elif (( STAMP_RC != 0 )); then
  # Before the capture, so nothing of this run's is on disk but the carry and the
  # recovery — rolled back here exactly as the capture refusal rolls them back. The stamp
  # itself needs no rollback: set-window-to writes the file only on a path that exits 0.
  rollback_carry
  rollback_recovery
  refuse "could not stamp session_window.to (set-window-to exited $STAMP_RC): ${STAMP_OUT:-no output} — the window would have stayed open on a feature this run was about to close, so nothing was captured; fix the manifest's fence and run this again"
fi
# The primary was verified clean above and nothing before this step touches the manifest,
# so a dirty manifest here is this stamp and nothing else. That is what makes the rollback
# exact rather than a guess about what the file held.
STAMPED=0
if [[ -n "$(git -C "$PRIMARY" status --porcelain -- "$MANIFEST_REL")" ]]; then STAMPED=1; fi

# rollback_stamp — undo the stamp above, for a refusal path only, exactly as
# rollback_carry undoes the timing append and rollback_recovery the recovered sidecars.
# Nothing is lost: the evidence is derived from transcripts that are still there, and the
# re-run derives it again. `git checkout --` restores a tracked file this script modified
# in a checkout it proved clean at entry.
rollback_stamp() {
  (( STAMPED )) || return 0
  git -C "$PRIMARY" checkout -- "$MANIFEST_REL" 2>/dev/null
  echo "  window    rolled back the session_window.to stamp; $MANIFEST_REL is as it was"
}

# ── Capture, report, and what was claimed ─────────────────────────────────────
echo ""
echo "=== capture ==="
CAPTURE_ARGS=()
if (( RECAPTURE )); then CAPTURE_ARGS=(--recapture); fi
if ! "${CAPTURE_PY[@]}" "$SLUG" ${CAPTURE_ARGS[@]+"${CAPTURE_ARGS[@]}"}; then
  rollback_carry
  rollback_recovery
  rollback_stamp
  CARRY_NOTE=""
  if (( CARRIED )); then
    CARRY_NOTE=", and the $CARRIED timing stamp(s) carried above were rolled back — the worktree still holds them and the next run carries them again"
  fi
  STAMP_NOTE="session_window.to is as this run found it"
  if (( STAMPED )); then
    STAMP_NOTE="the session_window.to stamped above was rolled back — the evidence is still in the transcripts and the next run derives it again"
  fi
  refuse "capture refused — no planning.json was written and $STAMP_NOTE$CARRY_NOTE; $PRIMARY is exactly as this run found it, so act on the refusal above and run this again"
fi

echo ""
echo "=== report ==="
if ! python3 -B "$SCRIPT_DIR/analysis/report.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$SLUG"; then
  refuse "report.py failed; planning.json is written but the report is not"
fi

echo ""
echo "=== what planning.json claims ==="
"${MANIFEST_PY[@]}" claimed || refuse "could not read what planning.json claims"

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
