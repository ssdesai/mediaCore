#!/usr/bin/env bash
set -uo pipefail

# Capture a feature's cost: feature-capture.sh [--self] <slug> [--recapture] [--no-push]
#
# The cost record of a feature is written ON ITS BRANCH, BEFORE THE MERGE, and the merge
# is the freeze (LIFECYCLE.md; self/DESIGN-2026-09-16-lifecycle-restructure.md §3.2). The
# review pass runs this after `pr.sh` on a clean pass (run-review.sh), so the record rides
# the PR and merging it is the last step of a feature — there is no close to run. It is
# re-runnable by hand from the worktree after a rework that skipped a full review, and a
# second run replaces the first record. No model is involved.
#
# Which run this is follows from where it runs, never from a flag:
#
#   ON THE BRANCH — the checkout this copy lives in has <slug> checked out, which is the
#   feature's worktree R/.worktrees/<slug> (or a legacy sibling R-<slug>). In order:
#
#     1. refuses when anything but this feature's cost records is dirty in the checkout
#        (`stray_paths`, plan-runner-roots.sh): the commit below must be this run's records
#        and nothing else, and a stranger's work in progress is not this script's to
#        commit. Checked before anything is written, so a refusal leaves the checkout
#        exactly as it was. **Strict about siblings**: the annotation that may rewrite
#        another feature's record has not run yet, so a sibling's `report.md` dirty before
#        this run is a stranger's work like any other. feature-close.sh calls the same
#        reader, with the same admitted-siblings argument of none, before it opens a PR;
#     2. stamps session_window.to from EVIDENCE — `capture_planning.py
#        --last-branch-instant <slug>`, one second past the last instant of the sessions
#        the feature's `branches` and `session_window` select and of their subagents —
#        with `manifest.py set-window-to --replace`: before the merge the bound is
#        provisional and moves EITHER way, so a re-run after more work moves it later.
#        With no branch session the bound is this run's clock, announced in one line;
#     3. recovers what the CLI never priced, over this feature only
#        (`recover_attempts.py --for <slug>`) — reported, never fatal;
#     4. captures (`capture_planning.py <slug>`, with --recapture once a record exists on
#        the branch, since that record is provisional too) and reports (`report.py`), and
#        prints what planning.json claims. A capture that refuses rolls the stamp and the
#        recovered sidecars back, byte for byte, from a snapshot taken before either was
#        written, so the refusal can be acted on and the run repeated;
#     5. refreshes `sessions[].also_claimed_by` on every OTHER already-captured record in
#        this corpus from the claims ledger (`capture_planning.py --annotate-frozen`,
#        which opens no transcript and moves no figure) and re-reports each one it
#        changed, so a feature frozen before this one claimed the session they share can
#        finally say so;
#     6. refreshes THIS feature's own routing record (`routing.py --refresh-for <slug>`,
#        which reads `<slug>/routing.json` — there is no fence field) — silent when the
#        feature has none, and it never writes another feature's copy of the same
#        router's record;
#     7. warns — never refuses — about a delegate whose brief names <repo>/<slug> and that
#        neither route claims: asked AFTER the capture, when the ledger holds this
#        capture's own claims, so a delegate claimed through its parent is not listed;
#     8. prints the RESIDUE — the rate table's date and the corpus-wide sessions and
#        delegates no feature claims, routers excluded. About the corpus rather than this
#        feature, and never a refusal: this is where the retired weekly sweep's last step
#        went (self/DESIGN-2026-09-16-lifecycle-restructure.md §3.5);
#     9. re-runs the stray check — this time admitting the three ANNOTATION_FILES under
#        exactly the slugs step 5 returned, and nothing else — then commits the cost
#        records on the branch as `<slug>: cost records` (COST_FILES, the routing record
#        among them, the per-plan usage sidecars and any record step 5 annotated) and
#        pushes the branch with -u. Never main. The worktree is left in place: the next
#        feature-start.sh's prune removes it once the branch has merged.
#
#   AFTER THE MERGE — anywhere else, typically the primary checkout on main. The feature
#   has merged under the old flow and was never closed, or it is being repaired
#   (--recapture). It refuses a branch that is not merged into what is checked out, and
#   with no branch left at all (a forge with delete-on-merge) proceeds only on the
#   feature's manifest being tracked here and its `<slug>: start` commit being in this
#   history — both, never either. Steps 2–8 as above, except that the stamp fills a null
#   `to` and leaves a set one alone, and under --recapture is `--tighten`: a bound is
#   replaced only by an EARLIER one, and a refused widen (manifest.py's exit 3, and that
#   code alone) warns and carries on with the bound already published. It WRITES
#   LOCALLY, COMMITS NOTHING AND PUSHES NOTHING: a repair of a merged record goes through
#   a PR of its own, which the human opens.
#
# Every python here runs with -B: an analysis/__pycache__ left in the checkout is
# untracked dirt that step 1 of the next run would refuse as a stranger's work.
#
# Exit codes: 2 usage; 1 any refusal.

USAGE_RC=2
REFUSED_RC=1
# manifest.py set-window-to's exit code for the widen refusal and nothing else
# (WIDEN_REFUSED_EXIT there; bash cannot import it, so self/tests/feature-lifecycle.sh W6
# holds the two in step).
WIDEN_REFUSED_RC=3
# The harness's own records — COST_FILES (the routing record among them), the per-plan
# sidecars and the three ANNOTATION_FILES a sibling's annotation may carry — and the reader that tells
# them from a stranger's work in progress live in plan-runner-roots.sh, sourced below:
# `stray_labels`, `is_cost_usage_path`, `stray_paths`. feature-close.sh calls the same
# reader before it opens a PR, which is the point of their being there and not here.
# How far back the residue listings look. A week, the cadence the retired sweep ran at:
# far enough that a delegate spawned before the weekend is still named, near enough that
# the listing stays a list of things to act on rather than the corpus's whole history.
RESIDUE_LOOKBACK_DAYS=7
COST_COMMIT_SUFFIX=": cost records"
# The subject feature-start.sh gives a feature's first commit (LIFECYCLE.md → step 2):
# with both branch refs gone, the only thing left in history saying it was started here.
START_COMMIT_SUFFIX=": start"
ORIGIN_REMOTE="origin"
UTC_STAMP_FORMAT='+%Y-%m-%dT%H:%M:%SZ'
SNAPSHOT_TEMPLATE="feature-capture.XXXXXX"
CAPTURE_SCRIPT_NAME="feature-capture.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
SELF_FLAG=()
if [[ "${1:-}" == "--self" ]]; then SELF_FLAG=(--self); shift; fi

usage() {
  echo "usage: $CAPTURE_SCRIPT_NAME [--self] <slug> [--recapture] [--no-push]" >&2
  exit "$USAGE_RC"
}
refuse() { echo "  refused  $*" >&2; exit "$REFUSED_RC"; }

SLUG="${1:-}"; [[ -n "$SLUG" ]] || usage; shift
RECAPTURE=0; PUSH=1
while (( $# )); do
  case "$1" in
    --recapture) RECAPTURE=1; shift ;;
    --no-push)   PUSH=0; shift ;;
    *) usage ;;
  esac
done

# ── Where ─────────────────────────────────────────────────────────────────────
# CHECKOUT is the working tree this copy lives in — the feature's worktree before the
# merge, the primary after it — and PRIMARY the checkout its common git dir belongs to,
# whose name is the <repo> a delegate's brief carries. Every git call names CHECKOUT with
# -C: nothing here depends on the caller's cwd.
CHECKOUT="$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null)" || refuse "$REPO_DIR is not inside a git repository"
COMMON_GIT_DIR="$(git -C "$CHECKOUT" rev-parse --git-common-dir 2>/dev/null)" || refuse "cannot resolve the common git dir of $CHECKOUT"
case "$COMMON_GIT_DIR" in /*) ;; *) COMMON_GIT_DIR="$CHECKOUT/$COMMON_GIT_DIR" ;; esac
PRIMARY="$(cd "$(dirname "$COMMON_GIT_DIR")" && pwd -P)" || refuse "cannot resolve the primary checkout of $CHECKOUT"
REPO_NAME="$(basename "$PRIMARY")"
FEATURE_DIR="$FEATURES_DIR/$SLUG"
# FEATURE_REL, FEATURES_REL and STRAY_SLUG — the labels `git status` prints
# paths with, and what stray_paths below reads (plan-runner-roots.sh).
stray_labels "$SLUG" "$CHECKOUT"
MANIFEST="$FEATURE_DIR/README.md"
MANIFEST_REL="$FEATURE_REL/README.md"
PLANNING_JSON="$FEATURE_DIR/planning.json"
CURRENT_BRANCH="$(git -C "$CHECKOUT" branch --show-current)"
MANIFEST_PY=(python3 -B "$SCRIPT_DIR/analysis/manifest.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$SLUG")
CAPTURE_PY=(python3 -B "$SCRIPT_DIR/analysis/capture_planning.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"})
RERUN_HINT="$SCRIPT_DIR/$CAPTURE_SCRIPT_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$SLUG"

dirty_paths() { git -C "$CHECKOUT" status --porcelain --untracked-files=all; }

# ── Which run this is ─────────────────────────────────────────────────────────
ON_BRANCH=0
if [[ "$CURRENT_BRANCH" == "$SLUG" ]]; then
  if (( RECAPTURE )); then
    refuse "--recapture is the post-merge repair path; on '$SLUG' itself a plain run already replaces the record — run $RERUN_HINT"
  fi
  ON_BRANCH=1
  echo "  mode      on branch $SLUG in $CHECKOUT — the record is committed on the branch and rides the PR"
else
  # worktree_of <branch> — the checkout holding it, from git's own record, for the hint.
  worktree_of() {
    git -C "$CHECKOUT" worktree list --porcelain 2>/dev/null \
      | awk -v ref="branch refs/heads/$1" '/^worktree /{wt=substr($0,10)} $0==ref{print wt; exit}'
  }
  MERGE_REF=""
  if git -C "$CHECKOUT" show-ref --verify --quiet "refs/heads/$SLUG"; then
    MERGE_REF="$SLUG"
  elif git -C "$CHECKOUT" show-ref --verify --quiet "refs/remotes/$ORIGIN_REMOTE/$SLUG"; then
    MERGE_REF="$ORIGIN_REMOTE/$SLUG"
  fi
  if [[ -n "$MERGE_REF" ]]; then
    if ! git -C "$CHECKOUT" merge-base --is-ancestor "$MERGE_REF" HEAD; then
      wt="$(worktree_of "$SLUG")"
      refuse "'$SLUG' is not merged into ${CURRENT_BRANCH:-HEAD} — before the merge the record belongs on the branch: run ${wt:-<its worktree>}/${SCRIPT_DIR#"$CHECKOUT"/}/$CAPTURE_SCRIPT_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$SLUG"
    fi
    echo "  merged    $MERGE_REF is an ancestor of ${CURRENT_BRANCH:-HEAD}"
  elif git -C "$CHECKOUT" cat-file -e "HEAD:$MANIFEST_REL" 2>/dev/null \
      && [[ -n "$(git -C "$CHECKOUT" rev-list --max-count=1 --fixed-strings --grep="$SLUG$START_COMMIT_SUFFIX" HEAD 2>/dev/null)" ]]; then
    echo "  merged    no branch left; $MANIFEST_REL and '$SLUG$START_COMMIT_SUFFIX' are in ${CURRENT_BRANCH:-HEAD}"
  else
    refuse "no branch '$SLUG' locally or on $ORIGIN_REMOTE, and no merged manifest with its start commit — nothing to capture"
  fi
  echo "  mode      after the merge, in $CHECKOUT — writes locally, commits nothing, pushes nothing"
fi
[[ -f "$MANIFEST" ]] || refuse "no manifest at $MANIFEST — is that the right slug?"

# ── 1. Nothing but cost records may be dirty (on the branch) ──────────────────
if (( ON_BRANCH )); then
  # NO_SIBLINGS: the annotation (step 5) is what makes another feature's record this run's
  # own, and it has not run. A sibling's record dirty BEFORE this run is somebody else's,
  # and it is named here rather than left dirty on a branch this run is about to push.
  # The `if !` guards the assignment's own exit status, which is stray_paths' return code:
  # refuses on STRAY_UNJUDGED_RC (a label stray_labels should have set is missing) AND on
  # any other way the command substitution's subshell can die (plan-runner-roots.sh).
  if ! STRAY="$(stray_paths "$(dirty_paths)" "$NO_SIBLINGS")"; then
    refuse "the stray-records check could not run — the capture stopped before its commit; see stderr above"
  fi
  if [[ -n "$STRAY" ]]; then
    echo "  these dirty paths are not $SLUG's cost records:" >&2
    while IFS= read -r path; do echo "    $path" >&2; done <<<"$STRAY"
    refuse "commit or discard them first, then run $RERUN_HINT again — nothing was written"
  fi
fi

# The snapshot the refusal paths restore from: the manifest the stamp rewrites and every
# sidecar recovery may rewrite, copied before either runs. Restoring from it is exact
# whatever the files' git state, and needs no git command that touches the tree.
SNAPSHOT="$(mktemp -d "${TMPDIR:-/tmp}/$SNAPSHOT_TEMPLATE")" || refuse "cannot create a snapshot directory"
trap 'rm -rf "$SNAPSHOT"' EXIT
cp "$MANIFEST" "$SNAPSHOT/README.md"
SIDECARS=()
while IFS= read -r sidecar; do
  [[ -n "$sidecar" ]] || continue
  SIDECARS+=("${sidecar#"$FEATURE_DIR"/}")
  mkdir -p "$SNAPSHOT/sidecars/$(dirname "${sidecar#"$FEATURE_DIR"/}")"
  cp "$sidecar" "$SNAPSHOT/sidecars/${sidecar#"$FEATURE_DIR"/}"
done < <(find "$FEATURE_DIR" -name "*$USAGE_SIDECAR_SUFFIX" -type f 2>/dev/null)

rollback_stamp() {
  cmp -s "$SNAPSHOT/README.md" "$MANIFEST" && return 0
  cp "$SNAPSHOT/README.md" "$MANIFEST"
  echo "  window    rolled back the session_window.to stamp; $MANIFEST_REL is as it was"
}
rollback_recovery() {
  local rel restored=0
  for rel in ${SIDECARS[@]+"${SIDECARS[@]}"}; do
    if ! cmp -s "$SNAPSHOT/sidecars/$rel" "$FEATURE_DIR/$rel"; then
      cp "$SNAPSHOT/sidecars/$rel" "$FEATURE_DIR/$rel"
      restored=$(( restored + 1 ))
    fi
  done
  if (( restored )); then
    echo "  recover   rolled back the $restored recovered sidecar(s); the feature directory is as it was"
  fi
}

# ── 2. session_window.to, from evidence, before the capture ───────────────────
# The bound the capture's share split runs against. Stderr is dropped and an empty answer
# is the documented no-evidence case.
echo ""
echo "=== window ==="
EVIDENCE="$("${CAPTURE_PY[@]}" --last-branch-instant "$SLUG" 2>/dev/null)"
if [[ -n "$EVIDENCE" ]]; then
  echo "  window    evidence: last branch instant + 1s = $EVIDENCE"
else
  EVIDENCE="$(date -u "$UTC_STAMP_FORMAT")"
  echo "  window    no branch session — to stamped at capture time ($EVIDENCE)"
fi
STAMP_ARGS=()
if (( ON_BRANCH )); then
  STAMP_ARGS=(--replace)
elif (( RECAPTURE )); then
  STAMP_ARGS=(--tighten)
fi
STAMP_OUT="$("${MANIFEST_PY[@]}" set-window-to ${STAMP_ARGS[@]+"${STAMP_ARGS[@]}"} "$EVIDENCE" 2>&1)"
STAMP_RC=$?
if [[ -n "$STAMP_OUT" ]]; then echo "$STAMP_OUT"; fi
if (( STAMP_RC == WIDEN_REFUSED_RC )); then
  # Only --tighten produces it: the bound it declined to widen is the one already
  # published, and the capture is what the repair run came for.
  echo "  warn      session_window.to was left as it is — a bound is never widened"
elif (( STAMP_RC != 0 )); then
  rollback_stamp
  refuse "could not stamp session_window.to (set-window-to exited $STAMP_RC): ${STAMP_OUT:-no output} — the window would have stayed open on a feature this run was about to capture, so nothing was captured; fix the manifest's fence and run $RERUN_HINT again"
fi

# ── 3. Recover what the CLI never priced ──────────────────────────────────────
# Scoped with --for: this run speaks for this feature. Never fatal: a transcript that is
# gone is news for the report, not a reason to abandon the capture.
echo ""
echo "=== recover ==="
if ! python3 -B "$SCRIPT_DIR/analysis/recover_attempts.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} --for "$SLUG"; then
  echo "  warn      recovery reported a failure; continuing — the report below names any plan still unpriced"
fi

# ── 4. Capture, report, and what was claimed ──────────────────────────────────
echo ""
echo "=== capture ==="
CAPTURE_ARGS=()
if (( RECAPTURE )) || { (( ON_BRANCH )) && [[ -f "$PLANNING_JSON" ]]; }; then
  CAPTURE_ARGS=(--recapture)
fi
if ! "${CAPTURE_PY[@]}" "$SLUG" ${CAPTURE_ARGS[@]+"${CAPTURE_ARGS[@]}"}; then
  rollback_recovery
  rollback_stamp
  refuse "capture refused — planning.json was not written, and the stamp and any recovered sidecars are as this run found them; act on the refusal above and run $RERUN_HINT again"
fi

echo ""
echo "=== report ==="
if ! python3 -B "$SCRIPT_DIR/analysis/report.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$SLUG"; then
  refuse "report.py failed; planning.json is written but the report is not — run $RERUN_HINT again"
fi

echo ""
echo "=== what planning.json claims ==="
"${MANIFEST_PY[@]}" claimed || refuse "could not read what planning.json claims"

# ── 5. The frozen records this capture now shares a session with ──────────────
# A capture registers this feature's claims in the ledger; a feature frozen BEFORE it
# cannot say so about itself, and its report's shared-session footnote is derived from
# the field this refreshes. `--annotate-frozen` is a ledger read over this corpus — no
# transcript opened, no dollar, duration or `captured_at` touched — and prints the slug
# of each record it changed, which is then re-reported so the number a reader sees
# matches the record beside it. Never fatal: this feature's own capture has already
# succeeded, and another feature's annotation is not a reason to lose it.
echo ""
echo "=== annotate ==="
ANNOTATED=()
if ! ANNOTATED_OUT="$("${CAPTURE_PY[@]}" --annotate-frozen --except "$SLUG")"; then
  echo "  warn      could not refresh this corpus's shared-session annotations; every other record is as it was"
  ANNOTATED_OUT=""
fi
while IFS= read -r other; do
  [[ -n "$other" ]] || continue
  ANNOTATED+=("$other")
  echo "  annotate  $FEATURES_REL/$other/planning.json now names this feature among the claimants of a session it counts"
  if ! python3 -B "$SCRIPT_DIR/analysis/report.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$other"; then
    echo "  warn      report.py $other failed; its record is annotated and its report is not"
  fi
done <<<"$ANNOTATED_OUT"
if (( ${#ANNOTATED[@]} == 0 )); then
  echo "  annotate  no other record in this corpus changed"
fi

# ── 6. This feature's own routing record ──────────────────────────────────────
# Printed only when the feature has one; a feature started with no session id has none,
# and that is not news. It is inside the feature directory, so the commit below carries it
# with the rest of the cost records and no path of its own is added for it.
if ! REFRESHED="$(python3 -B "$SCRIPT_DIR/analysis/routing.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} --refresh-for "$SLUG")"; then
  echo "  warn      routing.py --refresh-for $SLUG failed; the records it names are as they were"
  REFRESHED=""
fi
while IFS= read -r record; do
  [[ -n "$record" ]] || continue
  echo "  router    refreshed ${record#"$CHECKOUT"/}"
done <<<"$REFRESHED"

# ── 7. Delegates this feature's brief names and no route claims ───────────────
# Asked after the capture, so a delegate claimed through its parent — now in the ledger —
# is not listed. A row is a row by its leading date; the agent id is its second column.
SINCE="$("${MANIFEST_PY[@]}" get session_window.from)"
SINCE="${SINCE%%T*}"
SINCE_ARGS=()
if [[ -n "$SINCE" ]]; then SINCE_ARGS=(--since "$SINCE"); fi
DELEGATES="$("${CAPTURE_PY[@]}" --list-subagents --unclaimed --for "$REPO_NAME/$SLUG" ${SINCE_ARGS[@]+"${SINCE_ARGS[@]}"} 2>/dev/null)"
PINNED_AGENTS="$("${MANIFEST_PY[@]}" get subagents)"
while IFS= read -r row; do
  case "$row" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ *) ;;
    *) continue ;;
  esac
  agent="$(awk '{print $2}' <<<"$row")"
  case "$PINNED_AGENTS" in *"\"$agent\""*) continue ;; esac
  echo "  warn      delegate $agent names $REPO_NAME/$SLUG and no route claims it — pin it in $MANIFEST_REL as \"subagents\": [\"$agent\"] and run $RERUN_HINT again"
done <<<"$DELEGATES"

# ── 8. The residue: what this repo's corpus accounts for nobody ───────────────
# What the retired weekly sweep printed (self/DESIGN-2026-09-16-lifecycle-restructure.md
# §3.5), moved to the one moment somebody is already reading cost output. Informational
# in the strict sense: it reports on the CORPUS, not on this feature, and nothing in it
# can refuse a capture that has already done its job — an unclaimed session is a question
# for a human, and a rate table nobody has re-checked is a reason to re-check it, not a
# reason to leave a feature uncaptured while its transcripts still exist.
#
# The rates line comes first because every dollar printed above is tokens times that
# table. The listings exclude routers by construction (`is_router_lines`): a router's
# spend is routing overhead, a category of its own, not an unclaimed remainder.
echo ""
echo "=== residue ==="
RATES_OUT="$(python3 -B -c "import sys; sys.path.insert(0, '$SCRIPT_DIR/analysis'); import pricing; print(pricing.RATES_VERIFIED, pricing.is_rates_stale())" 2>&1)"
echo "  rates     verified ${RATES_OUT%% *}"
if [[ "${RATES_OUT##* }" == "True" ]]; then
  echo "  WARN      rate table is stale; update RATES and RATES_VERIFIED in analysis/pricing.py"
fi
LOOKBACK_DATE="$(python3 -B -c 'import datetime as d, sys; print((d.datetime.now(d.timezone.utc) - d.timedelta(days=int(sys.argv[1]))).strftime("%Y-%m-%d"))' "$RESIDUE_LOOKBACK_DAYS")"
"${CAPTURE_PY[@]}" --list-sessions --unclaimed --since "$LOOKBACK_DATE"
"${CAPTURE_PY[@]}" --list-subagents --unclaimed --since "$LOOKBACK_DATE"

# ── 9. Commit and push the branch — or, after the merge, nothing ──────────────
echo ""
echo "=== commit ==="
if (( ! ON_BRANCH )); then
  echo "  commit    nothing committed and nothing pushed — the records are written in $CHECKOUT;"
  echo "            put them on a branch and open a PR for the repair"
  exit 0
fi
DIRTY="$(dirty_paths)"
if [[ -z "$DIRTY" ]]; then
  echo "  commit    nothing changed — no cost records to commit"
else
  # Now — and only now — the slugs step 5 annotated are admitted: their three records are
  # this run's own work, and the commit below names each of them. The `if !` guards the
  # assignment's own exit status (stray_paths' return code): refuses on STRAY_UNJUDGED_RC
  # AND on any other way the subshell can die (plan-runner-roots.sh).
  if ! STRAY="$(stray_paths "$DIRTY" "${ANNOTATED[*]:-}")"; then
    refuse "the stray-records check could not run — the capture stopped before its commit; see stderr above"
  fi
  if [[ -n "$STRAY" ]]; then
    echo "  these dirty paths are not $SLUG's cost records:" >&2
    while IFS= read -r path; do echo "    $path" >&2; done <<<"$STRAY"
    refuse "something wrote them during this run; commit or discard them, then run $RERUN_HINT again — the capture and report are written"
  fi
  # The feature's own directory covers its routing record too, which is inside it.
  ADD_PATHS=("$FEATURE_REL")
  # Each record step 5 annotated, named one by one rather than by adding the whole
  # features root: the commit carries this run's records and nothing that happened to be
  # sitting under another feature's directory.
  for annotated in ${ANNOTATED[@]+"${ANNOTATED[@]}"}; do
    ADD_PATHS+=("$FEATURES_REL/$annotated")
  done
  git -C "$CHECKOUT" add -- "${ADD_PATHS[@]}" || refuse "git add failed in $CHECKOUT"
  git -C "$CHECKOUT" commit -q -m "$SLUG$COST_COMMIT_SUFFIX" || refuse "git commit failed in $CHECKOUT"
  echo "  commit    $SLUG$COST_COMMIT_SUFFIX"
  git -C "$CHECKOUT" show --name-only --format= HEAD | sed 's/^/              /'
fi

if (( ! PUSH )); then
  echo "  push      skipped (--no-push) — $SLUG is ahead of $ORIGIN_REMOTE"
elif ! git -C "$CHECKOUT" remote get-url "$ORIGIN_REMOTE" >/dev/null 2>&1; then
  echo "  push      skipped — this repository has no $ORIGIN_REMOTE"
elif git -C "$CHECKOUT" push -q -u "$ORIGIN_REMOTE" "$SLUG"; then
  echo "  push      $SLUG -> $ORIGIN_REMOTE"
else
  refuse "could not push $SLUG; the cost commit is on the branch locally — push it by hand"
fi

echo ""
echo "$SLUG is captured on its branch. The numbers above ride the PR; merging it freezes them."
