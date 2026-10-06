#!/usr/bin/env bash
set -uo pipefail

# REVIEW runner: executes the post-verify review plans in plans/features/<slug>/review/
# after the verify pass finishes (see AGENT_PLANS.md "Review plans"). The feature slug
# may be given as the first argument, and is otherwise inferred from whichever feature
# has plans queued.
#
# Why a third pass rather than a second verify plan. Verify generates observations by
# RUNNING the work — it finds what only execution reveals (a 500 that needs an
# unreadable directory to reach, a job run across a config switch). Review generates
# observations by READING the diff — it finds what stays green: an invariant with no
# test, a cross-layer contract broken on one side, a README whose field list no longer
# matches the shape it documents. Neither subsumes the other, and the split is the whole
# point: AGENT_PLANS.md "The mechanical gate" rules out handing a high model a
# transcript to summarize, because the defects worth finding are not in the output.
# Reading a diff is not reading a transcript.
#
# Same tool scope and the same fix policy as verify: Bash is ENABLED, edits are
# auto-approved, and the executor fixes what is LOCAL and reports what is structural.
# A review that could not fix a drifted README line would be buying a whole extra batch
# to correct a one-line defect it already found.
#
# This pass ends a ROUND and nothing more (self/DESIGN-2026-09-17-close-and-review-rounds.md
# §2–§3). It reads the verdict from the report's first line, commits its own output as
# `<slug>: review round N`, stamps that round's plan_end with the verdict and the head it
# judged, and names what comes next: feature-close.sh on a clean round, or the rework
# brief it has just written to <features>/<slug>/escalations/<review-stem>.md. It opens no
# PR and runs no capture — those belong to the close, which refuses any tree a clean review
# has not judged, so a rework cannot happen behind a PR body describing the tree before it.
#
# This script lives in the shared agentTooling checkout, vendored at agentTooling/ in the
# consuming repo root. By default REPO_DIR is therefore that root, and the plan queue it
# operates on lives in that repo's own plans/ directory. Passing --self as the first
# argument instead points the run at agentTooling's own self/features/ queue — see
# plan-runner-roots.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
if (( SELF_MODE )); then shift; fi
QUEUE="review"
PLAN_KIND="review plan"
SUMMARY_TITLE="Review run summary"
# The step that follows a CLEAN round, and the only way out of a feature: it opens the PR,
# stamps it, captures the cost on the branch and asks for the merge, in that order
# (LIFECYCLE.md → step 6). This runner names it and never runs it — a runner is a runner
# (self/DESIGN-2026-09-17-close-and-review-rounds.md §2).
CLOSE_SCRIPT_NAME="feature-close.sh"
CLOSE_SCRIPT="$SCRIPT_DIR/$CLOSE_SCRIPT_NAME"
# The subject this runner commits the pass's own output under. The round is what makes one
# round's commit distinguishable from the next's; pr.sh's own fallback commit keeps its
# older subject and, now that this runner always commits first, is only ever a no-op.
PASS_COMMIT_ROUND_PREFIX=": review round "
# The base a feature whose manifest names none was cut from (pr.sh's FALLBACK_BASE). Only
# the commit decision below uses it: on the base branch itself there is nothing to commit
# to, and pr.sh's own refusal says so.
FALLBACK_BASE="main"

# Bash is on for the same reason it is on for verify, plus one specific to this pass:
# establishing what the batch changed is read-only git (status/diff/log/show), and there
# is no other way to get it.
CLAUDE_TOOL_ARGS=(--allowedTools Bash)

# A circuit breaker, not a budget — same role as VERIFY_BUDGET_USD, calibrated
# separately because this pass defaults to a more expensive model. Verify's $3.00 was
# derived from sonnet runs (see run-verify.sh); an opus pass at comparable turn counts
# does not fit inside it, and a cap that fires on every honest run teaches nothing.
#
# $5.00 was the starting estimate; the first two measured opus runs cost $4.53 and
# $5.11 (the second capped after it had written its report), so $7.00 is the median
# doubled, rounded down to what those runs say an honest pass needs with headroom.
# Re-derive again after a few more.
#
# Enforced after each API call, so a run overshoots by at most one turn's spend.
REVIEW_BUDGET_USD="${REVIEW_BUDGET_USD:-7.00}"
CLAUDE_BUDGET_ARGS=(--max-budget-usd "$REVIEW_BUDGET_USD")

build_prompt() {
  local plan_path="$1"
  local log_path="$2"
  cat <<PROMPT
You are running a REVIEW plan: a post-verify pass that reads the DIFF a batch produced and judges the code itself. The build pass wrote it, the mechanical gate ran the deterministic checks, and the verify pass already ran the work and fixed what running revealed. You are the last pass, and you are looking for what all three of those miss: defects that are still there while every check is green. A progress log is maintained automatically by the harness so this work can be resumed if interrupted.

Relevant files (absolute paths):
- Plan:         $plan_path
- Progress log: $log_path (auto-populated — do not write to it yourself)

Process:
1. Read the progress log first. Each line was appended by the harness as '<tool>: <absolute file path>', recording a mutating tool call from a previous run. Treat it as a hint about which files you may already have changed.
2. Read the plan. It is a BRIEF, not a diff: it states what the batch was supposed to do and which contracts to hold it to. Use your judgment.
3. ESTABLISH THE DIFF FIRST, before reading any file in full. Read-only git is available and is the right tool: \`git status\`, \`git diff\`, \`git log --oneline\`, \`git diff <base>...HEAD\`, \`git show\`. The plan names the base to compare against. Read the diff before opening whole files — a diff shows you what changed, and a file shows you everything, most of which this batch did not touch.
4. If $GATE_REPORT_LABEL exists, read it. Install, format, lint, tests, typecheck and build ALREADY RAN. Do not re-run them, and do not re-derive their verdict. A green gate is your starting condition, not your finding. If it lists a check as SKIPPED, treat that as absent information, not as a pass: either run that check yourself or state in your verdict exactly what is consequently unverified.
5. DO NOT REDO THE VERIFY PASS. It already ran the work, exercised the behaviour, and triaged what failed. Re-running tests, starting a server, driving an endpoint, or constructing fixtures is either its job or a test's job, and it is not yours. If the only way to settle a question is to run something, that is a signal you are answering the wrong question in this pass — record it as a missing test instead.
6. LOOK FOR WHAT STAYS GREEN. That is the entire value of this pass, and it is where the batch's real defects live. In particular:
   - An invariant the code depends on that no test asserts — the highest-value finding this pass produces, because naming the missing assertion lets the next batch write it at a cheaper model's rate and the gate then runs it forever.
   - A contract broken on one side only: a response shape and its client type, a serialized field and its reader, a constant mirrored by hand across two layers.
   - Documentation that has drifted out of agreement with the code it documents — a field list missing a field, a stated guarantee the implementation no longer makes.
   - An edge case the change introduces and does not handle: empty, absent, malformed, or already-present input on a path the batch just added.
   - A stated project invariant the change quietly amends. If the batch needed to amend one, say so plainly — an amended invariant is a decision, and it should be visible as one rather than discovered later.
7. FIX ONLY WHAT IS LOCAL — a drifted README line, an off-by-one in a bound, a missing null guard, a wrong constant (edits are auto-accepted). Anything needing a new function, a changed signature, or a DESIGN DECISION is NOT yours to implement: report it, precisely enough to act on — the file, the line, what is wrong, and what it should be — as work for the next batch's build plan. Expect to escalate more often than a verify pass does: a defect found by reading is more often structural than one found by running, and rewriting a design at peak context on this model is the most expensive way this workflow can correct anything.
8. NEVER mutate repo-wide VCS state: no \`git stash\`, \`git checkout\`, \`git reset\`, \`git clean\`, or branch switch. Two reasons, both load-bearing. (a) The plan queue you are running from is UNTRACKED working-tree state, so \`git stash -u\` sweeps this plan, its progress log and its usage record out from under the runner — and \`git stash pop\` restores the files but not the queue directories it emptied, which strands this plan in inprogress/ where the next run resumes it. (b) This run can stop at ANY turn (budget cap, usage limit), and a stop between stash and pop leaves the whole batch's uncommitted output in a stash nobody knows to look for. To compare against a baseline, use \`git worktree add <scratch-path> HEAD\`, which never touches this working tree. Read-only git is not just fine here, it is the point — see step 3.
9. Do not check whether a model obeys an instruction. Such checks are flaky by construction and cannot fail informatively.
10. WRITE YOUR VERDICT TO $REVIEW_REPORT_LABEL, overwriting whatever is there. Its FIRST LINE must be exactly \`$VERDICT_PREFIX $VERDICT_CLEAN\` or \`$VERDICT_PREFIX $VERDICT_ESCALATED\` — \`$VERDICT_CLEAN\` means the escalated list below is EMPTY, and nothing else does. The harness reads that line, and only that line: \`$VERDICT_CLEAN\` lets the feature be closed, \`$VERDICT_ESCALATED\` makes the rework a new round, and a first line it cannot read is treated as \`$VERDICT_ESCALATED\`. Then write the report for the human who approves the PR, since this file becomes its body: what the batch was supposed to do, whether it does it, then two separate lists — what you fixed in this pass, and what you are escalating to the next round. Markdown. "No findings" is a legitimate and useful verdict; say it outright rather than manufacturing something to justify the pass, because a list of speculative concerns is worse than an empty list — the next round has to spend turns disproving each one. If you write nothing here, your review is invisible to the person approving it and the harness reads the missing verdict as an escalation.
11. Do NOT Read or Write the progress log yourself. The harness appends to it live as you use Edit/Write.

Plan contents:

$(cat "$plan_path")
PROMPT
}

# Lets run_all return after a budget cap instead of exiting, so the PR block below gets
# to look at whether the report was written first (finalize_plan, plan-runner-lib.sh).
after_budget_exceeded() { BUDGET_CAPPED=1; }
BUDGET_CAPPED=0

source "$SCRIPT_DIR/plan-runner-lib.sh"
# This runner finishes its own plan_end stamp: the verdict and the sha of the commit it
# makes below are both details that do not exist when finalize_plan has the exit code
# (plan-runner-lib.sh → "plan_end, and the one wrapper that finishes the stamp itself").
PLAN_END_DEFERRED=1
# Fingerprint taken before the pass so "the report was written by THIS run" is a
# content comparison rather than a guess (mtime granularity is a second, which a stub
# or a fast pass can fit inside); see the budget-capped branch below.
report_fingerprint() { if [[ -f "$REVIEW_REPORT" ]]; then cksum < "$REVIEW_REPORT"; else echo absent; fi; }
REVIEW_BEFORE="$(report_fingerprint)"
run_all "$@"
run_rc=$?
(( BUDGET_CAPPED )) && run_rc=1

# --- Read the verdict, commit the pass, and stop. ---
#
# In the script, not the executor prompt: committing is deterministic work with a real
# exit code, and AGENT_PLANS.md "The mechanical gate" already settles that such work
# leaves the model. The model's contribution is the review itself — which reaches the PR
# as its body when feature-close.sh opens one, via $REVIEW_REPORT.
#
# A runner is a runner (design §2). This pass records what the round decided and names
# the next step; it opens no PR and runs no capture, so a rework after an escalated round
# cannot happen behind a PR body and a frozen record that describe the tree before it.
#
# Gated on a clean pass, with one exception. A review that failed or was interrupted has
# not finished judging the batch, and a verdict recorded on its behalf would be a
# half-written one. The exception is a BUDGET cap that fired after the report was written:
# the verdict is complete — the executor writes the report as its last act (prompt step
# 10) — and the cap cut off only the turns after it. Measured: the first pilot's review
# wrote its full report, then hit the cap, was filed to failed/, and the PR was opened by
# hand with the identical body. The report is used as-is with a banner saying the pass was
# capped, so the approver knows the review's own fix loop may have been cut short.
capped_after_report() {
  [[ -n "$(list_plans "$FAILED_DIR")" ]] || return 1
  [[ -z "$(list_plans "$INPROGRESS_DIR")$(list_plans "$INCOMPLETE_DIR")" ]] || return 1
  [[ -f "$REVIEW_REPORT" && "$(report_fingerprint)" != "$REVIEW_BEFORE" ]] || return 1
  grep -qs "reached the run budget" "$FAILED_DIR"/*.progress.md
}
record_verdict=0
if [[ -n "${FEATURE_SLUG:-}" ]]; then
  if (( run_rc == 0 )) && [[ -z "$(list_plans "$FAILED_DIR")$(list_plans "$INPROGRESS_DIR")$(list_plans "$INCOMPLETE_DIR")" ]]; then
    record_verdict=1
  elif (( BUDGET_CAPPED )) && capped_after_report; then
    echo ""
    echo "=== review pass hit its budget AFTER writing its report — the verdict in it stands ==="
    printf '\n---\n_Review pass reached its budget cap (%s USD) after writing this verdict; any fixes it was still applying may be incomplete. The review itself is as written above._\n' "$REVIEW_BUDGET_USD" >> "$REVIEW_REPORT"
    record_verdict=1
  fi
fi
# commit_pass_output <branch> <base> <subject> — commit everything this pass produced.
#
# The commit is the RUNNER'S, and pr.sh's older one is now only a fallback that finds a
# clean tree. pr.sh returns 0 without committing on four ordinary paths — no forge CLI
# installed, not authenticated, detached HEAD, no pr.sh seeded at all — and until the
# runner committed, each of them left the pass's own files dirty when feature-capture.sh
# ran next, which refuses anything that is not a cost record as a stranger's work: every
# clean review in such a repo ended with "capture exited 1" (the capture-on-branch
# review's escalation; self/DESIGN-2026-09-16-lifecycle-restructure.md §3.8).
#
# On the base branch there is nothing to commit to — committing the primary's work in
# progress is what LIFECYCLE.md rule 2 exists to prevent. Advisory throughout, exactly
# like the gate: a review that succeeded is never unwound by a git failure after it, and
# the verdict is stamped either way.
commit_pass_output() {
  local branch="$1" base="$2" subject="$3"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    echo "=== detached HEAD — the pass's output is left uncommitted ==="
    return 0
  fi
  if [[ "$branch" == "$base" ]]; then
    echo "=== on '$branch', this feature's base — the pass's output is left uncommitted ==="
    return 0
  fi
  if [[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
    echo "=== nothing to commit — the working tree is already clean ==="
    return 0
  fi
  if ! git -C "$REPO_DIR" add -A; then
    echo "=== git add failed — the pass's output is left uncommitted ==="
    return 0
  fi
  if ! git -C "$REPO_DIR" commit -q -m "$subject"; then
    echo "=== git commit failed — the pass's output is left uncommitted ==="
    return 0
  fi
  echo "=== committed the pass as '$subject' on $branch ==="
}

if (( record_verdict )); then
  # The round this pass belongs to, fixed by run_all at pass_start, and the plan whose
  # plan_end is still held (plan-runner-lib.sh): the one that wrote the report.
  round="${TIMING_ROUND:-$(next_round "$FEATURE_SLUG")}"
  review_plan="${PLAN_END_HELD_PLAN:-$(latest_review_plan "$FEATURE_SLUG")}"
  verdict="$(report_verdict "$REVIEW_REPORT")"
  pass_subject="$FEATURE_SLUG$PASS_COMMIT_ROUND_PREFIX$round"
  escalations_dir="$FEATURES_DIR/$FEATURE_SLUG/$ESCALATIONS_DIR_NAME"
  escalations_file="$escalations_dir/$review_plan.md"
  escalations_label="$FEATURES_LABEL/$FEATURE_SLUG/$ESCALATIONS_DIR_NAME/$review_plan.md"

  echo ""
  case "$verdict" in
    "$VERDICT_CLEAN")
      echo "=== round $round verdict: $VERDICT_CLEAN ==="
      ;;
    "$VERDICT_UNREADABLE")
      echo "=== round $round verdict: $VERDICT_UNREADABLE — the report's first line carried no '$VERDICT_PREFIX' the harness could read, so it is treated as $VERDICT_ESCALATED (fail closed) ==="
      ;;
    *)
      echo "=== round $round verdict: $VERDICT_ESCALATED ==="
      ;;
  esac

  # The rework brief, written by the RUNNER and not by the executor: the report already
  # carries the two lists the prompt asks for, and one file with one writer is what keeps
  # the brief and the verdict from disagreeing. Same directory the tier ladder writes
  # NN.md into (RUNNER.md → "Red gates").
  if [[ "$verdict" != "$VERDICT_CLEAN" ]]; then
    if mkdir -p "$escalations_dir" && cp "$REVIEW_REPORT" "$escalations_file" 2>/dev/null; then
      echo "=== the rework brief is $escalations_label ==="
    else
      echo "=== could not write $escalations_label — the report is at $REVIEW_REPORT_LABEL ==="
    fi
  fi

  # The branch this feature was cut from, recorded by feature-start.sh: on it there is
  # nothing for this pass to commit to. Read here, once, so nothing else parses markdown.
  feature_base="$(manifest_field "$FEATURES_DIR/$FEATURE_SLUG/README.md" base)"
  echo ""
  echo "=== committing the pass's output ==="
  commit_pass_output "$(git -C "$REPO_DIR" branch --show-current 2>/dev/null)" \
    "${feature_base:-$FALLBACK_BASE}" "$pass_subject"

  # The stamps, after the commit: `head` is the sha of the tree this verdict judged, which
  # is what feature-close.sh refuses to close anything but. pass_end is written here
  # rather than left to the EXIT trap so the two land together, one line after the other.
  stamp_head="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)"
  flush_plan_end verdict="$verdict" head="$stamp_head"
  stamp_pass_end

  echo ""
  if [[ "$verdict" == "$VERDICT_CLEAN" ]]; then
    echo "=== next: $CLOSE_SCRIPT $SELF_ARG$FEATURE_SLUG ==="
    echo "=== the close opens the PR with this verdict as its body, captures the cost on the branch, and asks for the merge — in that order, and nothing runs after the merge ==="
  else
    echo "=== nothing after this review runs: the rework is round $((round + 1)) ==="
    echo "=== next round: brief the rework from $escalations_label (route it like a build — direct, plans or by hand, at a cheaper model where the findings are precise), queue the re-review as $FEATURES_LABEL/$FEATURE_SLUG/review/incomplete/NN-review-<model>.md, add its stem with 'python3 analysis/manifest.py $SELF_ARG$FEATURE_SLUG set-plans <stem>...', then run: $SCRIPT_DIR/run-review.sh $SELF_ARG$FEATURE_SLUG ==="
  fi
elif [[ -n "${FEATURE_SLUG:-}" ]]; then
  echo ""
  echo "=== review pass did not finish cleanly — no verdict was recorded, and nothing after the review runs ==="
fi

exit "$run_rc"
