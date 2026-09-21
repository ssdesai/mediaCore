#!/usr/bin/env bash
set -uo pipefail

# Close a feature: feature-close.sh [--self] <slug> [--no-push]
#
# The only way out of a feature, and the counterpart of feature-start.sh: the two scripts
# bracket a feature and nothing between them opens a PR or freezes a record
# (LIFECYCLE.md → step 6; self/DESIGN-2026-09-17-close-and-review-rounds.md §5). Run from
# the feature's worktree, on its branch, by the coordinator or by run-batch.sh. No model
# is involved.
#
# A feature is a sequence of ROUNDS — build → gate → verify → review — and a round ends in
# the review's verdict. An escalated round stops at the review: the rework is routed like a
# build, the next review brief is queued, and the review runs again as round N+1. This
# script refuses everything else, so a tree no clean review has judged cannot be closed.
#
# In order, and the order is the point:
#
#   1. REFUSE unless this is the tree a clean review judged (five refusals below, each
#      naming what to do). Checked before anything is written, so a refusal leaves the
#      worktree exactly as it was — in particular before a PR is opened, rather than
#      after.
#   2. PR. The body is the review's report as the executor wrote it, followed by the
#      Rounds table analysis/report.py renders (--rounds-md; absent or failing, the body
#      is the report alone and one line says so). Then the repo-owned pr.sh — which
#      pushes and opens, or says already open, or skips where there is no forge — and the
#      `pr_opened` stamp with its rc and url.
#   3. CAPTURE. feature-capture.sh, which stamps `session_window.to`, captures, reports,
#      commits `<slug>: cost records` on the branch (the `pr_opened` stamp rides that
#      commit) and pushes. Advisory as it is everywhere: a refusal is printed with the
#      command that re-runs it and never unwinds the PR.
#   4. MERGE REQUEST, last: `pr.sh --merge-request <slug>` (template-version 4), which
#      asks the forge to merge only under PR_AUTO_MERGE and only now that the capture has
#      pushed. That ordering is the whole of the PR_AUTO_MERGE race this replaces: the
#      request used to be issued by pr.sh, before the cost commit existed. A refused
#      capture therefore skips it — nothing asks for a merge that would land without the
#      record.
#   5. Print the PR url and that merging it is the last step.
#
# Re-runnable: a second run finds the PR already open and the capture replacing its own
# record, and ends at the same place.
#
# Exit codes: 2 usage; 1 a refusal, or a capture that refused (the PR is open, the record
# is not committed, and the merge was not requested).

USAGE_RC=2
REFUSED_RC=1
# The subjects the harness itself may add after the sha a review judged. Anything else is
# a change nobody reviewed, and a fix after the review is a new round.
COST_COMMIT_SUFFIX=": cost records"
PR_COMMIT_SUFFIX=": PR"
# The version of pr.sh that has the --merge-request entry point. An older seeded copy is
# told about once and the request is skipped; sync-plans.sh --check reports the drift.
PR_MERGE_REQUEST_FLAG="--merge-request"
PR_MERGE_REQUEST_VERSION=4
PR_VERSION_LINE_RE='^# template-version:[[:space:]]*\([0-9][0-9]*\).*'
CAPTURE_SCRIPT_NAME="feature-capture.sh"
CLOSE_SCRIPT_NAME="feature-close.sh"
REVIEW_RUNNER_NAME="run-review.sh"
REPORT_PY_ROUNDS_FLAG="--rounds-md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
SELF_FLAG=()
if [[ "${1:-}" == "--self" ]]; then SELF_FLAG=(--self); shift; fi

usage() {
  echo "usage: $CLOSE_SCRIPT_NAME [--self] <slug> [--no-push]" >&2
  exit "$USAGE_RC"
}
refuse() { echo "  refused  $*" >&2; exit "$REFUSED_RC"; }

FEATURE_SLUG="${1:-}"; [[ -n "$FEATURE_SLUG" ]] || usage; shift
PUSH_FLAG=()
while (( $# )); do
  case "$1" in
    --no-push) PUSH_FLAG=(--no-push); shift ;;
    *) usage ;;
  esac
done

# Every path comes from this copy's own location, never from the caller's cwd — the same
# rule feature-capture.sh follows. pr.sh's contract says its cwd is the repo root, so this
# script moves there once, here, and every git call still names it with -C.
CHECKOUT="$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null)" \
  || refuse "$REPO_DIR is not inside a git repository"
cd "$REPO_DIR" || refuse "cannot enter $REPO_DIR"
FEATURE_DIR="$FEATURES_DIR/$FEATURE_SLUG"
FEATURE_LABEL="$FEATURES_LABEL/$FEATURE_SLUG"
MANIFEST="$FEATURE_DIR/README.md"
CURRENT_BRANCH="$(git -C "$CHECKOUT" branch --show-current)"
CAPTURE_SCRIPT="$SCRIPT_DIR/$CAPTURE_SCRIPT_NAME"
CAPTURE_HINT="$CAPTURE_SCRIPT ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG"
RERUN_HINT="$SCRIPT_DIR/$CLOSE_SCRIPT_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG"

# ── 1. Refuse anything but the tree a clean review judged ─────────────────────

[[ -f "$MANIFEST" ]] || refuse "no manifest at $FEATURE_LABEL/README.md — is that the right slug?"

# On the branch, in its worktree. The post-merge repair path is feature-capture.sh from the
# primary, and it stays there: that run writes locally and commits nothing, so forwarding
# to it would look like a close that worked.
if [[ "$CURRENT_BRANCH" != "$FEATURE_SLUG" ]]; then
  refuse "this checkout is on '${CURRENT_BRANCH:-a detached HEAD}', not on '$FEATURE_SLUG' — run this from the feature's worktree, on its branch. After the merge there is nothing to close: to capture or repair a merged record, run '$CAPTURE_HINT [--recapture]' from the primary checkout"
fi

REVIEW_PLAN="$(latest_review_plan "$FEATURE_SLUG")"
if [[ -z "$REVIEW_PLAN" ]]; then
  refuse "no review has finished for '$FEATURE_SLUG' — a feature is closed by its review's verdict, so queue a brief in $FEATURE_LABEL/review/incomplete/ and run '$SCRIPT_DIR/$REVIEW_RUNNER_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG'"
fi
VERDICT="$(review_plan_end "$FEATURE_SLUG" "$REVIEW_PLAN" verdict)"
JUDGED_HEAD="$(review_plan_end "$FEATURE_SLUG" "$REVIEW_PLAN" head)"
# The round that judged this tree, from the stamp the review itself wrote. The count is
# only the fallback, for a timing.jsonl written before every line carried its round: a
# review whose budget cap fired after it wrote its report stays in review/failed/ and so
# counts toward no round (plan-runner-roots.sh → "Rounds"), which would have the close
# stamp `pr_opened` and print its own banner one round low.
ROUND="$(review_plan_end "$FEATURE_SLUG" "$REVIEW_PLAN" round)"
case "$ROUND" in
  ''|*[!0-9]*) ROUND="$(completed_review_count "$FEATURE_SLUG")" ;;
esac
if (( ROUND < 1 )); then ROUND=1; fi
ESCALATIONS_FILE="$FEATURE_DIR/$ESCALATIONS_DIR_NAME/$REVIEW_PLAN.md"
ESCALATIONS_LABEL="$FEATURE_LABEL/$ESCALATIONS_DIR_NAME/$REVIEW_PLAN.md"

if [[ "$VERDICT" != "$VERDICT_CLEAN" ]]; then
  if [[ -f "$ESCALATIONS_FILE" ]]; then
    refuse "the latest review ($REVIEW_PLAN) came back '${VERDICT:-no verdict recorded}' — nothing after an escalated review runs. The rework is round $((ROUND + 1)): brief it from $ESCALATIONS_LABEL, queue the re-review in $FEATURE_LABEL/review/incomplete/, run '$SCRIPT_DIR/$REVIEW_RUNNER_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG' again, and close the round that comes back clean"
  fi
  refuse "the latest review ($REVIEW_PLAN) recorded '${VERDICT:-no verdict}' rather than '$VERDICT_CLEAN' — only a clean round can be closed. Re-run '$SCRIPT_DIR/$REVIEW_RUNNER_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG' and close the round it judges clean"
fi

# The tree being closed must be the tree that was judged. A commit after the stamped head
# is allowed only when it is one of the harness's own — the previous run's cost records,
# or this script's commit of the stamps the review pass left behind. Anything else is a
# change no review has read, and it is a new round rather than a footnote on this one.
HEAD_SHA="$(git -C "$CHECKOUT" rev-parse HEAD 2>/dev/null)"
if [[ -z "$JUDGED_HEAD" ]]; then
  refuse "the latest review ($REVIEW_PLAN) recorded no head — its verdict cannot be tied to a tree, so re-run '$SCRIPT_DIR/$REVIEW_RUNNER_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG' to judge this one"
fi
if [[ "$JUDGED_HEAD" != "$HEAD_SHA" ]]; then
  if ! git -C "$CHECKOUT" merge-base --is-ancestor "$JUDGED_HEAD" HEAD 2>/dev/null; then
    refuse "the sha the latest review judged ($(git -C "$CHECKOUT" rev-parse --short "$JUDGED_HEAD" 2>/dev/null || echo "$JUDGED_HEAD")) is not in this branch's history — run '$SCRIPT_DIR/$REVIEW_RUNNER_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG' on the tree you mean to close"
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    sha="${line%% *}"
    subject="${line#* }"
    case "$subject" in
      "$FEATURE_SLUG$COST_COMMIT_SUFFIX"|"$FEATURE_SLUG$PR_COMMIT_SUFFIX") continue ;;
    esac
    refuse "$(git -C "$CHECKOUT" rev-parse --short "$sha") '$subject' landed after the review judged this feature, and no review has read it — that is round $((ROUND + 1)), not a footnote on round $ROUND: queue the next review brief and run '$SCRIPT_DIR/$REVIEW_RUNNER_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG' again"
  done <<<"$(git -C "$CHECKOUT" log --format='%H %s' "$JUDGED_HEAD..HEAD" 2>/dev/null)"
fi

# Nothing but the harness's own records may be dirty, and the check comes BEFORE the PR
# rather than after it — which is the whole reason it is here. It is the CAPTURE's reader,
# from plan-runner-roots.sh: exactly the paths step 3 would refuse, refused now, so a
# half-written file inside the feature directory cannot pass here and be refused after the
# PR is open. No sibling slug is admitted, because this script annotates nothing.
stray_labels "$FEATURE_SLUG" "$CHECKOUT"
# The `if !` guards the assignment's own exit status, which is stray_paths' return code:
# refuses on STRAY_UNJUDGED_RC (a label stray_labels should have set is missing) AND on
# any other way the command substitution's subshell can die (plan-runner-roots.sh) — the
# fail-open bug this check exists to close.
if ! STRAY="$(stray_paths "$(git -C "$CHECKOUT" status --porcelain --untracked-files=all)" "$NO_SIBLINGS")"; then
  refuse "the stray-records check could not run — nothing was written and no PR was opened; see stderr above"
fi
if [[ -n "$STRAY" ]]; then
  echo "  these dirty paths are not $FEATURE_SLUG's cost records:" >&2
  while IFS= read -r path; do [[ -n "$path" ]] && echo "    $path" >&2; done <<<"$STRAY"
  refuse "commit or discard them first, then run $RERUN_HINT again — nothing was written, and no PR was opened"
fi

echo "  round     $ROUND of '$FEATURE_SLUG' came back $VERDICT_CLEAN ($REVIEW_PLAN); closing the tree it judged"

# Every stamp this script writes belongs to the round that closed, not to a round that
# has not started (plan-runner-roots.sh → "Rounds").
TIMING_ROUND="$ROUND"

# ── 2. The PR ─────────────────────────────────────────────────────────────────
# The pass's own closing stamps — the plan_end the verdict rides and pass_end — are
# written by the review runner AFTER its commit, so they are still dirty here. Committing
# them now is what keeps pr.sh's own fallback commit the no-op it is meant to be, and
# keeps its old subject out of a history the next close run has to read.
if [[ -n "$(git -C "$CHECKOUT" status --porcelain)" ]]; then
  if git -C "$CHECKOUT" add -A && git -C "$CHECKOUT" commit -q -m "$FEATURE_SLUG$PR_COMMIT_SUFFIX"; then
    echo "  commit    $(git -C "$CHECKOUT" rev-parse --short HEAD) '$FEATURE_SLUG$PR_COMMIT_SUFFIX' — the review pass's closing stamps"
  else
    echo "  warn      could not commit the review pass's closing stamps; pr.sh will commit them under its own subject"
  fi
fi

# The PR body: the review's report, then the Rounds table. One renderer — report.py's —
# rather than a second account of the same rows.
PR_BODY="$(mktemp "${TMPDIR:-/tmp}/feature-close.XXXXXX")"
trap 'rm -f "$PR_BODY"' EXIT
if [[ -f "$REVIEW_REPORT" ]]; then
  cat "$REVIEW_REPORT" > "$PR_BODY"
else
  echo "Reviewed by the agentTooling review pass for \`$FEATURE_SLUG\`. No review report was written." > "$PR_BODY"
fi
ROUNDS_MD="$(python3 -B "$SCRIPT_DIR/analysis/report.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$FEATURE_SLUG" "$REPORT_PY_ROUNDS_FLAG" 2>/dev/null)"
ROUNDS_RC=$?
if (( ROUNDS_RC == 0 )) && [[ -n "$ROUNDS_MD" ]]; then
  printf '\n%s\n' "$ROUNDS_MD" >> "$PR_BODY"
else
  echo "  note      analysis/report.py $REPORT_PY_ROUNDS_FLAG gave nothing — the PR body is the review's report alone"
fi

PR_LABEL="${PR_SCRIPT#"$REPO_DIR"/}"
PR_RC=0
PR_URL=""
if [[ ! -x "$PR_SCRIPT" ]]; then
  echo "  skip      no PR hook at $PR_LABEL (run sync-plans.sh to seed one) — no PR opened"
else
  echo "  pr        $PR_LABEL"
  # The base this feature was cut from, which pr.sh opens the PR against; read here, once,
  # so the repo-owned hook never parses markdown.
  feature_base="$(manifest_field "$MANIFEST" base)"
  if [[ -n "$feature_base" ]]; then export FEATURE_BASE="$feature_base"; fi
  # Through tee so the url pr.sh prints can be stamped: the link is the one thing worth
  # keeping from its output.
  pr_log="$(mktemp "${TMPDIR:-/tmp}/feature-close-pr.XXXXXX")"
  "$PR_SCRIPT" "$FEATURE_SLUG" "$PR_BODY" | tee "$pr_log"
  PR_RC=${PIPESTATUS[0]}
  PR_URL="$(grep -oE 'https?://[^[:space:]]+' "$pr_log" | tail -1)"
  rm -f "$pr_log"
  if (( PR_RC != 0 )); then
    echo "  warn      $PR_LABEL exited $PR_RC — open the PR by hand; the capture below still runs, the record being the feature's and not the PR's"
  fi
fi
stamp_timing pr_opened rc="$PR_RC" url="$PR_URL"

# ── 3. The capture, on the branch ─────────────────────────────────────────────
CAPTURE_RC=0
if [[ ! -x "$CAPTURE_SCRIPT" ]]; then
  echo "  skip      no $CAPTURE_SCRIPT_NAME beside this script — the cost was not captured"
  CAPTURE_RC="$REFUSED_RC"
else
  echo ""
  echo "=== capture ($CAPTURE_SCRIPT_NAME) ==="
  "$CAPTURE_SCRIPT" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$FEATURE_SLUG" ${PUSH_FLAG[@]+"${PUSH_FLAG[@]}"}
  CAPTURE_RC=$?
  if (( CAPTURE_RC != 0 )); then
    echo "  warn      capture exited $CAPTURE_RC — the PR is open and the review stands; once its refusal above is dealt with, re-run: $RERUN_HINT"
  fi
fi

# ── 4. The merge request, last ────────────────────────────────────────────────
if (( CAPTURE_RC != 0 )); then
  echo "  skip      the merge was NOT requested: the cost record is not committed or pushed yet, and asking the forge to merge before it is is the race this ordering exists to close"
elif [[ -x "$PR_SCRIPT" ]]; then
  pr_version="$(sed -n "s/$PR_VERSION_LINE_RE/\\1/p" "$PR_SCRIPT" 2>/dev/null | head -n 1)"
  if [[ -z "$pr_version" ]] || (( pr_version < PR_MERGE_REQUEST_VERSION )); then
    echo "  skip      $PR_LABEL is template-version ${pr_version:-0}, older than $PR_MERGE_REQUEST_VERSION — it has no $PR_MERGE_REQUEST_FLAG entry point, so no merge was requested (sync-plans.sh --check reports the drift)"
  else
    "$PR_SCRIPT" "$PR_MERGE_REQUEST_FLAG" "$FEATURE_SLUG"
  fi
fi

# ── 5. Where it ends ──────────────────────────────────────────────────────────
echo ""
if [[ -n "$PR_URL" ]]; then
  echo "  pr        $PR_URL"
fi
echo "  next      merge the PR — nothing runs after it. The next feature-start.sh prunes this worktree and its branch."
if (( CAPTURE_RC != 0 )); then exit "$REFUSED_RC"; fi
exit 0
