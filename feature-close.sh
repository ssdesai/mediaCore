#!/usr/bin/env bash
set -uo pipefail

# Close a feature: feature-close.sh [--self] <slug> [--no-push] [--allow-unclaimed "<reason>"]
#
# The only way out of a feature, and the counterpart of feature-start.sh: the two scripts
# bracket a feature and nothing between them opens a PR or freezes a record
# (LIFECYCLE.md → step 6; self/DESIGN-2026-09-17-close-and-review-rounds.md §5). Run from
# the feature's checkout, on its branch — the manifest's `branches[0]`, which is the slug
# for a local feature and the assigned `claude/…` branch in a cloud container
# (self/DESIGN-2026-10-05-cloud-execution.md §2) — by the coordinator or by run-batch.sh.
# No model is involved.
#
# A feature is a sequence of ROUNDS — build → gate → verify → review — and a round ends in
# the review's verdict. An escalated round stops at the review: the rework is routed like a
# build, the next review brief is queued, and the review runs again as round N+1. This
# script refuses everything else, so a tree no clean review has judged cannot be closed.
#
# In order, and the order is the point:
#
#   1. REFUSE unless this is the tree a clean review judged (five refusals below, each
#      naming what to do), and refuse a feature whose unpinned router built it (the
#      sixth, naming `manifest.py pin-session` and the transcript line that made it a
#      builder). Building is work in the worktree — a `cwd` there, or a write — other
#      than the router's own writes to the feature's review/ and manifest README.md
#      (LIFECYCLE steps 3 and 5). Checked before anything is written, so a
#      refusal leaves the worktree exactly as it was — in particular before a PR is
#      opened, rather than after.
#      Also refused, in the same place: a feature whose diff against its base touches the
#      hook (plan-runner-roots.sh's audit_paths) with no security audit that came back clean
#      on the head the review judged (LIFECYCLE.md → "The security audit");
#      a feature README whose prose still matches
#      templates/plans/features/TEMPLATE.md (manifest.py check-prose names the sections);
#      and a build no session or delegate claims while something WAS met in its window
#      (capture_planning.py --claim-check, exit 5), each id printed with its pin command —
#      unless --allow-unclaimed "<reason>" was given, whose reason manifest.py
#      allow-unclaimed records in the fence (self/features/delegate-cost-claims).
#   2. PR. The body is the review's report as the executor wrote it, followed by the
#      Rounds table analysis/report.py renders (--rounds-md; absent or failing, the body
#      is the report alone and one line says so). Then the repo-owned pr.sh, with
#      FEATURE_BASE and FORGE_SCRIPT exported — which pushes and opens (from
#      template-version 5 through forge.sh, `gh api` REST only), or, finding the PR an
#      earlier round's close opened, replaces its body with this one (from
#      template-version 7, forge.sh pr-edit; older copies only said "already open" and
#      left round 1's body), or skips where there is no forge CLI at all, and exits
#      non-zero when the forge refused — the refresh included, in which case the PR IS
#      open and pr.sh printed its url — and the `pr_opened` stamp with its rc and url.
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
# Re-runnable: a second run finds the PR already open — pr.sh at 7 rewrites its body from
# this run's report — and the capture merging into its record, carrying forward the rows it
# cannot reach, and ends at the same place.
#
# Exit codes: 2 usage; 1 a refusal, or a capture that refused (the PR is open, the record
# is not committed, and the merge was not requested).

USAGE_RC=2
REFUSED_RC=1
# Every git call below, and plan-runner-roots.sh's that this script runs, reads history with
# replace refs off: `git push` sends the real objects, so a local `refs/replace/<sha>` that
# shows a stand-in commit to log, diff and show would have the close judge one commit and
# push another (self/features/close-after-filing/, security audit round 3, B3). Grafts the
# same (round 4, B06): `.git/info/grafts` rewrites a commit's parents for every reader and
# for no push, so a cyclic graft could give an unreviewed commit a fabricated parent that
# differs from it in one file alone. Exported before the first git call, so the subshells
# and sourced functions inherit both. A shallow clone is tolerated: its boundary only
# removes parents, and a parentless commit fails commit_changes_only's one-parent rule.
export GIT_NO_REPLACE_OBJECTS=1
GRAFTS_OFF_FILE="/dev/null"
export GIT_GRAFT_FILE="$GRAFTS_OFF_FILE"
# The subjects the harness itself may add after the sha a review judged. Anything else is
# a change nobody reviewed, and a fix after the review is a new round.
COST_COMMIT_SUFFIX=": cost records"
PR_COMMIT_SUFFIX=": PR"
# The owner's brief and the conformance check (the section after the audit's): the helper
# beside this script, the subject of the start commit that carried the owner brief, and the
# committed copy of the review's report the acceptance table is read from (run-review.sh's
# ARCHIVED_REPORT_NAME, the same string)
CONFORMANCE_SCRIPT_NAME="conformance.py"
START_COMMIT_SUFFIX=": start"
ARCHIVED_REPORT_NAME="review-report.md"
# run-review.sh's commit of the round's own stamps (its STAMPS_COMMIT_SUFFIX), accepted
# only when it touches the feature's timing.jsonl and nothing else: the subject alone
# would admit an unreviewed change written under it.
STAMPS_COMMIT_SUFFIX=": review stamps"
# The coordinator's commit of a clean round's non-blocking findings to the repo's BACKLOG
# (resolve_roots' BACKLOG_LABEL; LIFECYCLE.md → "The security audit";
# self/features/close-after-filing/). Accepted only when it has one parent and its whole
# change is that one file, left a regular non-executable file: the BACKLOG is read by
# people, never executed, and is no audit path, so filing there changes nothing a review
# or an audit judged. Every other path under this subject, and the BACKLOG under any other
# subject, is a new round like any other commit.
BACKLOG_COMMIT_SUFFIX=": backlog"
# The git mode of a regular non-executable file: what the one file a stamps or backlog
# commit touches must be left as (commit_changes_only)
REGULAR_FILE_MODE="100644"
# `git rev-list --parents -n 1` of a commit with exactly one parent: its sha and that parent
SINGLE_PARENT_WORDS=2
# Ends a name list read through `$(…)`, whose strip of trailing newlines would otherwise
# fold a name like `<path><LF>` into `<path>` (commit_changes_only)
NAME_LIST_SENTINEL="."
# run-review.sh's commit of a round's own output (its PASS_COMMIT_ROUND_PREFIX): the only
# commit an audit report counts from (the security audit, below)
AUDIT_ROUND_COMMIT_INFIX=": review round "
# The version of pr.sh that has the --merge-request entry point. An older seeded copy is
# told about once and the request is skipped; sync-plans.sh --check reports the drift.
PR_MERGE_REQUEST_FLAG="--merge-request"
PR_MERGE_REQUEST_VERSION=4
PR_VERSION_LINE_RE='^# template-version:[[:space:]]*\([0-9][0-9]*\).*'
CAPTURE_SCRIPT_NAME="feature-capture.sh"
CLOSE_SCRIPT_NAME="feature-close.sh"
# The forge adapter (forge.sh, beside this script), exported to pr.sh as FORGE_SCRIPT.
FORGE_SCRIPT_NAME="forge.sh"
# Where pr.sh's stdout carries the PR url: lines beginning `  pr ` (every template version
# prints it there), and the url itself on such a line.
PR_URL_LINE_RE='^  pr '
PR_URL_RE='https?://[^[:space:]]+'
REVIEW_RUNNER_NAME="run-review.sh"
REPORT_PY_ROUNDS_FLAG="--rounds-md"
# routing.py's entry point that names a router which built this feature unpinned. It
# prints nothing, or one line: the session id, a tab, and the evidence — the first
# transcript line that made the session a builder (`cwd <path>` or `<Tool> <path>`).
UNPINNED_BUILDER_FLAG="--unpinned-builder"
# manifest.py's subcommand that lists the README prose sections still matching the template.
CHECK_PROSE_COMMAND="check-prose"
# capture_planning.py's read-only question before the PR — would the capture claim any
# session or delegate for the build? — and the one exit code that means "nothing claimed,
# something met" (CLAIM_CHECK_UNCLAIMED_EXIT there; bash cannot import it, so
# self/tests/feature-lifecycle.sh UB holds the two in step). Any other non-zero code is a
# check that could not run, refused like every other check here.
CLAIM_CHECK_FLAG="--claim-check"
CLAIM_CHECK_UNCLAIMED_RC=5
# The close's own flag that lets an unclaimed build through, and manifest.py's subcommand
# that records the reason it was given in the fence.
ALLOW_UNCLAIMED_FLAG="--allow-unclaimed"
ALLOW_UNCLAIMED_COMMAND="allow-unclaimed"
BUILDER_FIELD_SEPARATOR=$'\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
SELF_FLAG=()
if [[ "${1:-}" == "--self" ]]; then SELF_FLAG=(--self); shift; fi

usage() {
  echo "usage: $CLOSE_SCRIPT_NAME [--self] <slug> [--no-push] [$ALLOW_UNCLAIMED_FLAG \"<reason>\"]" >&2
  exit "$USAGE_RC"
}
refuse() { echo "  refused  $*" >&2; exit "$REFUSED_RC"; }

# commit_changes_only <sha> <path> — true when <sha> has exactly one parent, its whole
# change against it is <path>, nothing else, and <path> is left a regular non-executable
# file. One parent, because a merge's combined diff hides what either side brought in;
# renames off, so a rename shows both of its names; submodules never ignored, so a gitlink
# beside <path> is listed whatever .gitmodules or diff.ignoreSubmodules say (security audit
# round 2 of self/features/close-after-filing/, B2); the names read NUL-separated, with a
# sentinel after them so a name ending in a newline is compared as it is (round 1, B1); and
# the mode, so the file is neither deleted nor made a link or an executable (round 2, C24).
# Reads CHECKOUT, set below before any caller.
commit_changes_only() {
  local sha="$1" path="$2" parents listed mode
  parents="$(git -C "$CHECKOUT" rev-list --parents -n 1 "$sha" 2>/dev/null | wc -w | tr -d '[:space:]')"
  [[ "$parents" == "$SINGLE_PARENT_WORDS" ]] || return 1
  listed="$(git -C "$CHECKOUT" diff --no-renames --ignore-submodules=none --name-only -z "$sha^" "$sha" 2>/dev/null | tr '\0' '\n'; printf '%s' "$NAME_LIST_SENTINEL")"
  [[ "$listed" == "$path"$'\n'"$NAME_LIST_SENTINEL" ]] || return 1
  mode="$(git -C "$CHECKOUT" ls-tree "$sha" -- "$path" 2>/dev/null | awk '{ print $1; exit }')"
  [[ "$mode" == "$REGULAR_FILE_MODE" ]]
}

FEATURE_SLUG="${1:-}"; [[ -n "$FEATURE_SLUG" ]] || usage; shift
PUSH_FLAG=()
ALLOW_UNCLAIMED_REASON=""
while (( $# )); do
  case "$1" in
    --no-push) PUSH_FLAG=(--no-push); shift ;;
    "$ALLOW_UNCLAIMED_FLAG")
      (( $# >= 2 )) || usage
      ALLOW_UNCLAIMED_REASON="$2"
      [[ -n "${ALLOW_UNCLAIMED_REASON//[[:space:]]/}" ]] || usage
      shift 2 ;;
    *) usage ;;
  esac
done
refuse_orchestrator_session "${CLAUDE_CODE_SESSION_ID:-}"   # an orchestrator builds nothing

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

# On the branch, in its checkout. The branch is the manifest's `branches[0]` — the slug for
# a local feature, the assigned `claude/…` branch in a cloud container — never derived from
# the slug (manifest_branch, plan-runner-roots.sh). The post-merge repair path is
# feature-capture.sh from the primary, and it stays there: that run writes locally and
# commits nothing, so forwarding to it would look like a close that worked.
FEATURE_BRANCH="$(manifest_branch "$MANIFEST" "$FEATURE_SLUG")"
if [[ "$CURRENT_BRANCH" != "$FEATURE_BRANCH" ]]; then
  refuse "this checkout is on '${CURRENT_BRANCH:-a detached HEAD}', not on '$FEATURE_BRANCH', the branch $FEATURE_LABEL/README.md names — run this from the feature's checkout, on that branch. After the merge there is nothing to close: to capture or repair a merged record, run '$CAPTURE_HINT [--recapture]' from the primary checkout"
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
# the review runner's commit of its round's stamps (timing.jsonl alone), or this script's
# commit of any stamps the review pass left behind — or the coordinator's filing of the
# round's non-blocking findings (`<slug>: backlog`, the BACKLOG file alone). Anything else
# is a change no review has read, and it is a new round rather than a footnote on this one.
HEAD_SHA="$(git -C "$CHECKOUT" rev-parse HEAD 2>/dev/null)"
# The path labels both this check (FEATURE_REL, for the stamps commit) and the stray
# check below read.
stray_labels "$FEATURE_SLUG" "$CHECKOUT"
# The BACKLOG as a status line names it: behind the same prefix as FEATURE_REL
# (`agentTooling/` where the self layout is vendored, nothing otherwise).
BACKLOG_REL="${FEATURE_REL%"$FEATURES_LABEL/$FEATURE_SLUG"}$BACKLOG_LABEL"
BACKLOG_HINT="a non-blocking finding is filed after a clean review as its own commit touching only $BACKLOG_REL, under the subject '$FEATURE_SLUG$BACKLOG_COMMIT_SUFFIX'"
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
      "$FEATURE_SLUG$COST_COMMIT_SUFFIX"|"$FEATURE_SLUG$PR_COMMIT_SUFFIX")
        # Only cost records may ride those subjects (security audit round 1, F1): a subject is
        # a string anyone can type, so a commit under it that touches anything outside the
        # features directory is a change no review has read. The features directory, not
        # this feature's alone: the capture re-captures the siblings a shared session is
        # split with, and commits their records with this one's.
        # Submodules never ignored, as in commit_changes_only (close-after-filing audit round 2).
        harness_files="$(git -C "$CHECKOUT" show --no-renames --ignore-submodules=none --name-only -z --format= "$sha" 2>/dev/null | tr '\0' '\n')"
        # Nor may they carry audit evidence (round 2, N8): an audit plan, an audit report or
        # an `audit_end` line is written by a review round and its stamps, never by these.
        records_only=1
        while IFS= read -r harness_file; do
          [[ "$harness_file" == "${FEATURE_REL%/*}/"* ]] || records_only=0
          [[ "$harness_file" == */review/*/*"$AUDIT_STEM_INFIX"* || "$harness_file" == */"$AUDIT_REPORT_NAME" ]] && records_only=0
          # Nor the owner's request or its conformance evidence: written by the start and a review round
          [[ "$harness_file" == */review/*/*"$CONFORMANCE_STEM_INFIX"* || "$harness_file" == */"$CONFORMANCE_REPORT_NAME" || "$harness_file" == */"$OWNER_BRIEF_NAME" ]] && records_only=0
        done <<<"$harness_files"
        if git -C "$CHECKOUT" show --format= "$sha" -- '*timing.jsonl' 2>/dev/null | grep -q "^+.*\"event\": *\"$AUDIT_END_EVENT\""; then
          records_only=0
        fi
        if [[ -n "$harness_files" ]] && (( records_only )); then continue; fi
        ;;
      "$FEATURE_SLUG$STAMPS_COMMIT_SUFFIX")
        commit_changes_only "$sha" "$FEATURE_REL/timing.jsonl" && continue
        ;;
      "$FEATURE_SLUG$BACKLOG_COMMIT_SUFFIX")
        commit_changes_only "$sha" "$BACKLOG_REL" && continue
        ;;
    esac
    refuse "$(git -C "$CHECKOUT" rev-parse --short "$sha") '$subject' landed after the review judged this feature, and no review has read it — that is round $((ROUND + 1)), not a footnote on round $ROUND: queue the next review brief and run '$SCRIPT_DIR/$REVIEW_RUNNER_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG' again. Only the harness's own commits may follow the judged head, and $BACKLOG_HINT"
  done <<<"$(git -C "$CHECKOUT" log --format='%H %s' "$JUDGED_HEAD..HEAD" 2>/dev/null)"
fi

# A hook change is closed only behind a clean security audit (LIFECYCLE.md → "The security
# audit"; self/features/hook-role-hardening/). The diff against the base decides whether
# one is owed — plan-runner-roots.sh's audit_paths — and the audit must have come back
# clean on the very head the review judged: run-review.sh stamps both from one pass, so an
# audit from an earlier round, or one the review did not run beside, is no audit of this
# tree. Fail closed: a diff that cannot be read has not shown it touches no hook.
#
# Hardened by security audit round 1 (self/features/hook-role-hardening/NOTES.md):
#   F1  nothing after the judged head may touch an audit path, whatever its subject;
#   F7  the manifest's `base` is the one the review judged (a dirty README cannot move it),
#       and a feature whose base...HEAD diff is EMPTY is refused — every feature's diff
#       carries at least its own directory, so an empty one is a base that hides it;
#   F4  a clean audit is evidence, not a stamp: the committed audit report at the judged
#       head opens `Verdict: clean`, it was last written by a `<slug>: review round N`
#       commit that is the judged head or its ancestor, and its plan is the pinned model;
#   and, after all of those (audit-blocking-classes), a clean report's `## Findings` holds
#       only rows classed non-blocking — audit_report_unclassed, fail closed.
if ! POST_JUDGED_HOOK="$(audit_paths_in_range "$CHECKOUT" "$JUDGED_HEAD..HEAD")"; then
  refuse "cannot diff the judged head $JUDGED_HEAD..HEAD — nothing was written and no PR was opened"
fi
if [[ -n "$POST_JUDGED_HOOK" ]]; then
  refuse "$(tr '\n' ' ' <<<"$POST_JUDGED_HOOK")changed after the review judged this feature, and no review or security audit has read it — that is round $((ROUND + 1)): queue the next review brief and run '$SCRIPT_DIR/$REVIEW_RUNNER_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG' again; nothing was written and no PR was opened"
fi
AUDIT_BASE="$(manifest_field "$MANIFEST" base)"
JUDGED_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/feature-close-manifest.XXXXXX")"
git -C "$CHECKOUT" show "$JUDGED_HEAD:$FEATURE_REL/README.md" > "$JUDGED_MANIFEST" 2>/dev/null
JUDGED_BASE="$(manifest_field "$JUDGED_MANIFEST" base)"
rm -f "$JUDGED_MANIFEST"
if [[ "$AUDIT_BASE" != "$JUDGED_BASE" ]]; then
  refuse "$FEATURE_LABEL/README.md names base '${AUDIT_BASE:-none}', but at the head the review judged it named '${JUDGED_BASE:-none}' — the base decides what the review and the audit read, so it cannot move after them; put it back and run $RERUN_HINT again — nothing was written and no PR was opened"
fi
AUDIT_DIFF_BASE="$(audit_diff_base "$CHECKOUT" "${AUDIT_BASE:-main}")"
if ! AUDIT_ALL_FILES="$(git -C "$CHECKOUT" diff --no-renames --name-only "$AUDIT_DIFF_BASE...HEAD" 2>/dev/null)" \
   || ! AUDIT_TOUCHED="$(audit_paths_touched "$CHECKOUT" "$AUDIT_DIFF_BASE")"; then
  refuse "cannot diff $AUDIT_DIFF_BASE...HEAD to tell whether this feature changes the hook — nothing was written and no PR was opened"
fi
if [[ -z "$AUDIT_ALL_FILES" ]]; then
  refuse "$AUDIT_DIFF_BASE...HEAD is empty, yet every feature's diff carries its own $FEATURE_LABEL/ — the manifest's base '${AUDIT_BASE:-main}' hides this feature's changes; nothing was written and no PR was opened"
fi
JUDGED_LINKS="$(audit_symlinks_at "$CHECKOUT" "$JUDGED_HEAD")"
if [[ -n "$JUDGED_LINKS" ]]; then
  refuse "$(tr '\n' ' ' <<<"$JUDGED_LINKS")is a symlink at an audit path in the tree the review judged — the hook is reviewed and audited as files, never through a link; nothing was written and no PR was opened"
fi
if [[ -n "$AUDIT_TOUCHED" ]]; then
  # Everything below is read from git, not the working tree (round 2, N8): the audit plan
  # that completed in the judged head's tree, and the audit_end line in the stamps commit
  # run-review.sh made right after it.
  AUDIT_PLAN=""
  while IFS= read -r audit_path; do
    audit_stem="$(basename "${audit_path%.md}")"
    is_audit_stem "$audit_stem" || continue
    if [[ -z "$AUDIT_PLAN" ]] || (( 10#${audit_stem%%-*} > 10#${AUDIT_PLAN%%-*} )); then AUDIT_PLAN="$audit_stem"; fi
  done < <(git -C "$CHECKOUT" ls-tree --name-only "$JUDGED_HEAD" -- "$FEATURE_REL/review/complete/" 2>/dev/null)
  AUDIT_FILES="$(tr '\n' ' ' <<<"$AUDIT_TOUCHED")"
  AUDIT_RERUN="queue the next review brief and run '$SCRIPT_DIR/$REVIEW_RUNNER_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG', which queues the audit beside it"
  if [[ -z "$AUDIT_PLAN" ]]; then
    refuse "this feature changes the hook (${AUDIT_FILES% }) and no security audit has run — $AUDIT_RERUN; nothing was written and no PR was opened"
  fi
  STAMPS_SHA="$(git -C "$CHECKOUT" log --reverse --format='%H %s' "$JUDGED_HEAD..HEAD" 2>/dev/null \
    | awk -v s="$FEATURE_SLUG$STAMPS_COMMIT_SUFFIX" 'substr($0, index($0, " ") + 1) == s { print $1; exit }')"
  AUDIT_VERDICT=""; AUDIT_HEAD=""
  if [[ -n "$STAMPS_SHA" ]]; then
    AUDIT_STAMP="$(git -C "$CHECKOUT" show "$STAMPS_SHA:$FEATURE_REL/timing.jsonl" 2>/dev/null \
      | jq -c --arg e "$AUDIT_END_EVENT" --arg p "$AUDIT_PLAN" 'select(.event == $e and .plan == $p)' 2>/dev/null | tail -1)"
    AUDIT_VERDICT="$(jq -r '.verdict // empty' <<<"$AUDIT_STAMP" 2>/dev/null)"
    AUDIT_HEAD="$(jq -r '.head // empty' <<<"$AUDIT_STAMP" 2>/dev/null)"
  fi
  if [[ "$AUDIT_VERDICT" != "$VERDICT_CLEAN" ]]; then
    refuse "this feature changes the hook (${AUDIT_FILES% }) and its security audit ($AUDIT_PLAN) came back '${AUDIT_VERDICT:-no verdict recorded}' — the rework is round $((ROUND + 1)): brief it from $FEATURE_LABEL/$ESCALATIONS_DIR_NAME/$AUDIT_PLAN.md, then $AUDIT_RERUN; nothing was written and no PR was opened"
  fi
  if [[ "$AUDIT_HEAD" != "$JUDGED_HEAD" ]]; then
    refuse "this feature changes the hook (${AUDIT_FILES% }) and its clean security audit ($AUDIT_PLAN) judged ${AUDIT_HEAD:-no head}, not the head the review judged ($JUDGED_HEAD) — $AUDIT_RERUN; nothing was written and no PR was opened"
  fi
  if [[ "$AUDIT_PLAN" != *"$AUDIT_STEM_INFIX$AUDIT_DEFAULT_MODEL" ]]; then
    refuse "this feature changes the hook (${AUDIT_FILES% }) and its security audit $AUDIT_PLAN ran on a model other than the pinned $AUDIT_DEFAULT_MODEL — $AUDIT_RERUN; nothing was written and no PR was opened"
  fi
  AUDIT_REPORT_REL="$FEATURE_REL/$AUDIT_REPORT_NAME"
  AUDIT_REPORT_AT_HEAD="$(mktemp "${TMPDIR:-/tmp}/feature-close-audit.XXXXXX")"
  git -C "$CHECKOUT" show "$JUDGED_HEAD:$AUDIT_REPORT_REL" > "$AUDIT_REPORT_AT_HEAD" 2>/dev/null || rm -f "$AUDIT_REPORT_AT_HEAD"
  AUDIT_REPORT_VERDICT="$(report_verdict "$AUDIT_REPORT_AT_HEAD")"
  AUDIT_REPORT_UNCLASSED="$(audit_report_unclassed "$AUDIT_REPORT_AT_HEAD")"
  rm -f "$AUDIT_REPORT_AT_HEAD"
  AUDIT_REPORT_COMMIT="$(git -C "$CHECKOUT" log -1 --format='%H %s' "$JUDGED_HEAD" -- "$AUDIT_REPORT_REL" 2>/dev/null)"
  AUDIT_REPORT_SUBJECT="${AUDIT_REPORT_COMMIT#* }"
  if [[ "$AUDIT_REPORT_VERDICT" != "$VERDICT_CLEAN" || ! "$AUDIT_REPORT_SUBJECT" =~ ^"$FEATURE_SLUG$AUDIT_ROUND_COMMIT_INFIX"[0-9]+$ ]]; then
    refuse "this feature changes the hook (${AUDIT_FILES% }) and the head the review judged carries no audit report a review round committed with '$VERDICT_PREFIX $VERDICT_CLEAN' ($AUDIT_REPORT_REL: '${AUDIT_REPORT_VERDICT}', last written by '${AUDIT_REPORT_SUBJECT:-no commit}') — a stamp alone is not an audit: $AUDIT_RERUN; nothing was written and no PR was opened"
  fi
  AUDIT_PLAN_AT_HEAD="$(mktemp "${TMPDIR:-/tmp}/feature-close-plan.XXXXXX")"
  git -C "$CHECKOUT" show "$JUDGED_HEAD:$FEATURE_REL/review/complete/$AUDIT_PLAN.md" > "$AUDIT_PLAN_AT_HEAD" 2>/dev/null
  if ! audit_plan_matches_template "$SCRIPT_DIR/$AUDIT_TEMPLATE_REL" "$AUDIT_PLAN_AT_HEAD" "$FEATURE_SLUG"; then
    rm -f "$AUDIT_PLAN_AT_HEAD"
    refuse "this feature changes the hook (${AUDIT_FILES% }) and the audit plan $AUDIT_PLAN that completed at the judged head is not $AUDIT_TEMPLATE_REL as run-review.sh renders it — a hand-written brief is no audit: $AUDIT_RERUN; nothing was written and no PR was opened"
  fi
  rm -f "$AUDIT_PLAN_AT_HEAD"
  if [[ -n "$AUDIT_REPORT_UNCLASSED" ]]; then
    refuse "this feature changes the hook (${AUDIT_FILES% }) and its clean security audit report ($AUDIT_REPORT_REL) holds findings that are not all classed non-blocking: $(tr '\n' ';' <<<"$AUDIT_REPORT_UNCLASSED") — under '$VERDICT_PREFIX $VERDICT_CLEAN' every finding must be classed non-blocking ($AUDIT_TEMPLATE_REL); the rework is round $((ROUND + 1)), briefed from the audit report, then $AUDIT_RERUN; nothing was written and no PR was opened"
  fi
  echo "  audit     the hook changed (${AUDIT_FILES% }); security audit $AUDIT_PLAN came back $VERDICT_CLEAN on the head the review judged"
fi

# The owner's brief and the conformance check (LIFECYCLE.md → "The owner's brief and the
# conformance check"; self/features/brief-conformance-checks/, R10-R12). Only a feature whose
# judged tree carries OWNER_BRIEF.md owes any of it; without one the close is what it was,
# plus a note (the rollout, R15). Everything is read from git at the judged head — never the
# working tree, which the review's own fixes or anyone's edits may have changed since — and
# every refusal comes before anything is written or a PR is opened, naming the row or the
# disagreement. The deviations section never blocks here: pr.sh marks the PR for it (R12).
OWNER_BRIEF_REL="$FEATURE_REL/$OWNER_BRIEF_NAME"
CONFORMANCE_SCRIPT="$SCRIPT_DIR/$CONFORMANCE_SCRIPT_NAME"
CONFORMANCE_REPORT_REL="$FEATURE_REL/$CONFORMANCE_REPORT_NAME"
CONFORMANCE_REPORT_FILE=""
CONFORMANCE_TMP_FILES=()
trap 'rm -f ${CONFORMANCE_TMP_FILES[@]+"${CONFORMANCE_TMP_FILES[@]}"}' EXIT
unset CONFORMANCE_REPORT  # nothing the caller's environment carries stands in for this tree's report
CONFORMANCE_RERUN="the rework is round $((ROUND + 1)): queue the next review brief and run '$SCRIPT_DIR/$REVIEW_RUNNER_NAME ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG' again, which runs the conformance check beside it; nothing was written and no PR was opened"
# The start commit, read before the existence test: an owner brief the start carried and the
# judged tree no longer holds would otherwise turn every check below into the rollout's note
START_SHA="$(git -C "$CHECKOUT" log --format='%H %s' "$JUDGED_HEAD" 2>/dev/null \
  | awk -v s="$FEATURE_SLUG$START_COMMIT_SUFFIX" 'substr($0, index($0, " ") + 1) == s { sha = $1 } END { print sha }')"
if [[ -n "$START_SHA" ]] && git -C "$CHECKOUT" cat-file -e "$START_SHA:$OWNER_BRIEF_REL" 2>/dev/null \
   && ! git -C "$CHECKOUT" cat-file -e "$JUDGED_HEAD:$OWNER_BRIEF_REL" 2>/dev/null; then
  refuse "the '$FEATURE_SLUG$START_COMMIT_SUFFIX' commit carried $FEATURE_LABEL/$OWNER_BRIEF_NAME and the head the review judged does not — the owner's request is the yardstick and cannot be removed after the start; restore it (git checkout $START_SHA -- $OWNER_BRIEF_REL) and $CONFORMANCE_RERUN"
fi
if git -C "$CHECKOUT" cat-file -e "$JUDGED_HEAD:$OWNER_BRIEF_REL" 2>/dev/null; then
  [[ -f "$CONFORMANCE_SCRIPT" ]] || refuse "the judged tree carries $FEATURE_LABEL/$OWNER_BRIEF_NAME and there is no $CONFORMANCE_SCRIPT_NAME beside this script to read the review's acceptance table with — nothing was written and no PR was opened"
  if [[ -n "$START_SHA" ]] && git -C "$CHECKOUT" cat-file -e "$START_SHA:$OWNER_BRIEF_REL" 2>/dev/null \
     && ! git -C "$CHECKOUT" diff --quiet "$START_SHA" "$JUDGED_HEAD" -- "$OWNER_BRIEF_REL" 2>/dev/null; then
    refuse "$FEATURE_LABEL/$OWNER_BRIEF_NAME at the head the review judged differs from the copy the '$FEATURE_SLUG$START_COMMIT_SUFFIX' commit carried — the owner's request is the yardstick and cannot be edited after the start; restore it (git checkout $START_SHA -- $OWNER_BRIEF_REL) and $CONFORMANCE_RERUN"
  fi
  CONFORMANCE_BRIEF_FILE="$(mktemp "${TMPDIR:-/tmp}/feature-close-brief.XXXXXX")"
  CONFORMANCE_REVIEW_FILE="$(mktemp "${TMPDIR:-/tmp}/feature-close-review.XXXXXX")"
  CONFORMANCE_REPORT_FILE="$(mktemp "${TMPDIR:-/tmp}/feature-close-conformance.XXXXXX")"
  CONFORMANCE_TMP_FILES=("$CONFORMANCE_BRIEF_FILE" "$CONFORMANCE_REVIEW_FILE" "$CONFORMANCE_REPORT_FILE")
  git -C "$CHECKOUT" show "$JUDGED_HEAD:$OWNER_BRIEF_REL" > "$CONFORMANCE_BRIEF_FILE" 2>/dev/null
  if ! git -C "$CHECKOUT" show "$JUDGED_HEAD:$FEATURE_REL/$ARCHIVED_REPORT_NAME" > "$CONFORMANCE_REVIEW_FILE" 2>/dev/null; then
    refuse "the judged tree carries $FEATURE_LABEL/$OWNER_BRIEF_NAME but no $FEATURE_LABEL/$ARCHIVED_REPORT_NAME — the review round commits it, and its '## Acceptance' table is what the close reads; $CONFORMANCE_RERUN"
  fi
  CONFORMANCE_PLAN="${REVIEW_PLAN%%-*}$CONFORMANCE_STEM_INFIX${REVIEW_PLAN##*-}"
  if ! git -C "$CHECKOUT" cat-file -e "$JUDGED_HEAD:$FEATURE_REL/review/complete/$CONFORMANCE_PLAN.md" 2>/dev/null; then
    refuse "this feature carries $FEATURE_LABEL/$OWNER_BRIEF_NAME and no conformance check ran with the review: $CONFORMANCE_PLAN is not in review/complete/ at the judged head — $CONFORMANCE_RERUN"
  fi
  if ! git -C "$CHECKOUT" show "$JUDGED_HEAD:$CONFORMANCE_REPORT_REL" > "$CONFORMANCE_REPORT_FILE" 2>/dev/null; then
    refuse "the conformance check $CONFORMANCE_PLAN ran but the judged tree holds no $CONFORMANCE_REPORT_REL — $CONFORMANCE_RERUN"
  fi
  CONFORMANCE_REPORT_SUBJECT="$(git -C "$CHECKOUT" log -1 --format=%s "$JUDGED_HEAD" -- "$CONFORMANCE_REPORT_REL" 2>/dev/null)"
  if [[ "$CONFORMANCE_REPORT_SUBJECT" != "$FEATURE_SLUG$AUDIT_ROUND_COMMIT_INFIX$ROUND" ]]; then
    refuse "$CONFORMANCE_REPORT_REL was last written by '${CONFORMANCE_REPORT_SUBJECT:-no commit}', not by the '$FEATURE_SLUG$AUDIT_ROUND_COMMIT_INFIX$ROUND' commit of the round that judged this tree — a report no review round committed is no evidence: $CONFORMANCE_RERUN"
  fi
  if ! CONFORMANCE_PROBLEMS="$(python3 -B "$CONFORMANCE_SCRIPT" check-close --owner-brief "$CONFORMANCE_BRIEF_FILE" \
        --review "$CONFORMANCE_REVIEW_FILE" --conformance "$CONFORMANCE_REPORT_FILE")"; then
    if [[ -z "$CONFORMANCE_PROBLEMS" ]]; then
      refuse "$CONFORMANCE_SCRIPT_NAME could not read the owner brief and the reports at the judged head — nothing was written and no PR was opened; see stderr above"
    fi
    echo "  the review's acceptance table and the conformance check do not clear this round:" >&2
    while IFS= read -r problem; do [[ -n "$problem" ]] && echo "    $problem" >&2; done <<<"$CONFORMANCE_PROBLEMS"
    CONFORMANCE_FIRST_PROBLEM="$(head -n 1 <<<"$CONFORMANCE_PROBLEMS")"
    refuse "$CONFORMANCE_FIRST_PROBLEM (every problem is listed above) — a row that is not done, a missing section or a disagreement with the independent check cannot be closed as clean: $CONFORMANCE_RERUN"
  fi
  rm -f "$CONFORMANCE_BRIEF_FILE" "$CONFORMANCE_REVIEW_FILE"
  CONFORMANCE_TMP_FILES=("$CONFORMANCE_REPORT_FILE")
  echo "  conform   every owner item is done in the review's acceptance table and the independent conformance check ($CONFORMANCE_PLAN) agrees"
else
  echo "  note      no $OWNER_BRIEF_NAME in $FEATURE_LABEL at the judged head — the review was judged against its own brief only, and no acceptance table or conformance check is required (LIFECYCLE.md → \"The owner's brief and the conformance check\")"
fi

# Nothing but the harness's own records may be dirty, and the check comes BEFORE the PR
# rather than after it — which is the whole reason it is here. It is the CAPTURE's reader,
# from plan-runner-roots.sh: exactly the paths step 3 would refuse, refused now, so a
# half-written file inside the feature directory cannot pass here and be refused after the
# PR is open. No sibling slug is admitted, because this script annotates nothing. Its
# labels were set above, before the head check.
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

# A router that built this feature must be pinned (self/features/router-built-pin). The
# session that ran feature-start.sh without --pin is recorded as the feature's router, and
# its cost is routing overhead; if its transcript shows it at work in this worktree it
# built the feature, and unpinned its whole build would be missing from the total this
# close is about to freeze. Its own writes there — the review briefs under the feature's
# review/ and the manifest README.md (LIFECYCLE steps 3 and 5) — are not building
# (self/features/router-brief-writes). The predicate is routing.py's; the remedy is a
# script, and the manifest it edits is a cost record, so the re-run passes the check
# above. Fail closed, like the stray check: a checker that could not run has judged nothing.
if ! BUILDER_LINE="$(python3 -B "$SCRIPT_DIR/analysis/routing.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$UNPINNED_BUILDER_FLAG" "$FEATURE_SLUG")"; then
  refuse "the router check could not run — nothing was written and no PR was opened; see stderr above"
fi
if [[ -n "$BUILDER_LINE" ]]; then
  BUILDER="${BUILDER_LINE%%"$BUILDER_FIELD_SEPARATOR"*}"
  BUILDER_EVIDENCE="${BUILDER_LINE#*"$BUILDER_FIELD_SEPARATOR"}"
  refuse "session $BUILDER started '$FEATURE_SLUG' as its router and then worked in its worktree ($BUILDER_EVIDENCE), so it built the feature — and unpinned, its cost is routing overhead rather than this feature's. Pin it: python3 $SCRIPT_DIR/analysis/manifest.py ${SELF_FLAG[@]+"${SELF_FLAG[@]} "}$FEATURE_SLUG pin-session $BUILDER, then run $RERUN_HINT again — nothing was written, and no PR was opened"
fi

# A feature README still matching its template is a feature nobody described: the PR would
# carry no spec and the corpus a blank record (vinylCatalogue's import-experiment-fixtures
# merged so). manifest.py's check-prose names each section still the template's own text or
# carrying one of its <placeholders>; a hand pull fills the same prose (its goal, the one
# review row), so the same check holds it. Fail closed: a checker that could not run has
# judged nothing. Before anything is written, like every refusal above.
if ! UNFILLED="$(python3 -B "$SCRIPT_DIR/analysis/manifest.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$FEATURE_SLUG" "$CHECK_PROSE_COMMAND")"; then
  if [[ -z "$UNFILLED" ]]; then
    refuse "the manifest check could not run — nothing was written and no PR was opened; see stderr above"
  fi
  echo "$UNFILLED" >&2
  refuse "$FEATURE_LABEL/README.md still matches its template (above) — fill those sections: the goal paragraph, the plan table's one-line rows, and delete the level and contract sections or fill them (templates/plans/features/TEMPLATE.md says which), then run $RERUN_HINT again — nothing was written, and no PR was opened"
fi

# A build nobody claims must not be recorded at $0 in silence (self/features/
# delegate-cost-claims). The capture runs after the PR, so the question is asked here, before
# it: capture_planning.py --claim-check runs the capture's own selection and writes nothing.
# Claimed — a session or delegate, or a delegate whose brief names this feature, which the
# capture will pin itself — or nothing met at all (the capture's own zero refusal speaks for
# that), it says so and the close goes on. Nothing claimed but something met in the window —
# an excluded session on the branch, an unclaimed session, a delegate whose brief names this
# feature or carries no header — it stops here, each id printed with its pin command, unless
# --allow-unclaimed gave a reason, which manifest.py writes into the fence for the capture to
# carry into planning.json. Fail closed: a check that could not run has judged nothing.
CLAIM_OUT="$(python3 -B "$SCRIPT_DIR/analysis/capture_planning.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$CLAIM_CHECK_FLAG" "$FEATURE_SLUG" 2>&1)"
CLAIM_RC=$?
if (( CLAIM_RC == CLAIM_CHECK_UNCLAIMED_RC )); then
  if [[ -z "$ALLOW_UNCLAIMED_REASON" ]]; then
    echo "$CLAIM_OUT" >&2
    refuse "no session and no delegate is claimed for '$FEATURE_SLUG''s build, and the ones above were met in its window — closed now, its build would be recorded at \$0. Pin the one that built it with the command beside it and run $RERUN_HINT again; if none of them did, run $RERUN_HINT $ALLOW_UNCLAIMED_FLAG \"<why>\", which records the reason in the manifest — nothing was written, and no PR was opened"
  fi
  echo "$CLAIM_OUT"
  if ! python3 -B "$SCRIPT_DIR/analysis/manifest.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$FEATURE_SLUG" "$ALLOW_UNCLAIMED_COMMAND" "$ALLOW_UNCLAIMED_REASON"; then
    refuse "could not record the $ALLOW_UNCLAIMED_FLAG reason in $FEATURE_LABEL/README.md — no PR was opened"
  fi
  echo "  allow     $ALLOW_UNCLAIMED_FLAG: closing with the build unclaimed; the reason is in the manifest, committed by this close"
elif (( CLAIM_RC != 0 )); then
  echo "$CLAIM_OUT" >&2
  refuse "the claim check could not run (exit $CLAIM_RC) — nothing was written and no PR was opened; see above"
else
  echo "$CLAIM_OUT"
  if [[ -n "$ALLOW_UNCLAIMED_REASON" ]]; then
    echo "  note      $ALLOW_UNCLAIMED_FLAG was not needed — the check above passed — so no reason was recorded"
  fi
fi

echo "  round     $ROUND of '$FEATURE_SLUG' came back $VERDICT_CLEAN ($REVIEW_PLAN); closing the tree it judged"

# Every stamp this script writes belongs to the round that closed, not to a round that
# has not started (plan-runner-roots.sh → "Rounds").
TIMING_ROUND="$ROUND"

# ── 2. The PR ─────────────────────────────────────────────────────────────────
# The pass's own closing stamps — the plan_end the verdict rides and pass_end — are
# written by the review runner AFTER its pass commit, and it commits them itself as
# `S: review stamps`; they are dirty here only when that commit could not be made (a
# git failure, or a review from before it did). Committing them now is what keeps
# pr.sh's own fallback commit the no-op it is meant to be, and keeps its old subject out
# of a history the next close run has to read.
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
trap 'rm -f "$PR_BODY" ${CONFORMANCE_TMP_FILES[@]+"${CONFORMANCE_TMP_FILES[@]}"}' EXIT
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
  # And the forge adapter beside this script, which a template-version 5 pr.sh calls for
  # the GitHub part (pr-find, pr-open). An older pr.sh never reads it, and a repo on
  # another forge keeps its own code; either way exporting it changes nothing for them.
  export FORGE_SCRIPT="$SCRIPT_DIR/$FORGE_SCRIPT_NAME"
  # The helper a template-version 8 pr.sh composes the body and marks the title with
  # (conformance.py: Acceptance first, the deviations section second, `[deviations]` in the
  # title), and — when the judged tree carries an owner brief — the conformance report read
  # from git at the judged head. An older pr.sh ignores both, so the PR is as it was.
  if [[ -f "$CONFORMANCE_SCRIPT" ]]; then export CONFORMANCE_SCRIPT; else unset CONFORMANCE_SCRIPT; fi
  if [[ -n "$CONFORMANCE_REPORT_FILE" ]]; then export CONFORMANCE_REPORT="$CONFORMANCE_REPORT_FILE"; fi
  # Through tee so the url pr.sh prints can be stamped: the link is the one thing worth
  # keeping from its output.
  pr_log="$(mktemp "${TMPDIR:-/tmp}/feature-close-pr.XXXXXX")"
  "$PR_SCRIPT" "$FEATURE_SLUG" "$PR_BODY" | tee "$pr_log"
  PR_RC=${PIPESTATUS[0]}
  # Only from pr.sh's own `  pr ` lines (its stdout contract): it runs `git push … 2>&1`,
  # and a refused push names the remote's url, which in a cloud container is an http
  # proxy url — read from anywhere, that would be stamped and reported as an open PR.
  PR_URL="$(grep -E "$PR_URL_LINE_RE" "$pr_log" | grep -oE "$PR_URL_RE" | tail -1)"
  rm -f "$pr_log"
  # A non-zero rc with a url is a PR that IS open — a template-version 7 pr.sh whose body
  # refresh was refused — so "open it by hand" would be wrong advice there.
  if (( PR_RC != 0 )) && [[ -n "$PR_URL" ]]; then
    echo "  warn      $PR_LABEL exited $PR_RC with the PR open at $PR_URL — its body may still describe an earlier round: replace it by hand with this round's review report; the capture below still runs"
  elif (( PR_RC != 0 )); then
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
