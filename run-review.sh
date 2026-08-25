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
4. If $GATE_REPORT_LABEL exists, read it. Install, format, lint, tests, typecheck and build ALREADY RAN. Do not re-run them, and do not re-derive their verdict. A green gate is your starting condition, not your finding.
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
10. WRITE YOUR VERDICT TO $REVIEW_REPORT_LABEL, overwriting whatever is there. This file becomes the body of the pull request a human reviews, so write it for that reader: what the batch was supposed to do, whether it does it, then two separate lists — what you fixed in this pass, and what you are escalating to the next batch. Markdown. "No findings" is a legitimate and useful verdict; say it outright rather than manufacturing something to justify the pass, because a list of speculative concerns is worse than an empty list — the next batch has to spend turns disproving each one. If you write nothing here, the PR gets a placeholder body and your review is invisible to the person approving it.
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
# Fingerprint taken before the pass so "the report was written by THIS run" is a
# content comparison rather than a guess (mtime granularity is a second, which a stub
# or a fast pass can fit inside); see the budget-capped branch below.
report_fingerprint() { if [[ -f "$REVIEW_REPORT" ]]; then cksum < "$REVIEW_REPORT"; else echo absent; fi; }
REVIEW_BEFORE="$(report_fingerprint)"
run_all "$@"
run_rc=$?
(( BUDGET_CAPPED )) && run_rc=1

# --- Open the PR the review pass is asking a human to approve. ---
#
# In the script, not the executor prompt: branching, committing, pushing and calling a
# forge CLI is deterministic work with a real exit code, and AGENT_PLANS.md "The
# mechanical gate" already settles that such work leaves the model. The model's
# contribution is the review itself, which reaches the PR as its body via
# $REVIEW_REPORT.
#
# Gated on a clean pass, with one exception. A review that failed or was interrupted
# has not finished judging the batch, and a PR opened on its behalf would carry a
# half-written verdict past a human who reasonably assumes the pass completed. The
# exception is a BUDGET cap that fired after the report was written: the verdict is
# complete — the executor writes the report as its last act (prompt step 10) — and the
# cap cut off only the turns after it. Measured: the first pilot's review wrote its full
# report, then hit the cap, was filed to failed/, and the PR was opened by hand with the
# identical body. The report is used as-is with a banner saying the pass was capped, so
# the approver knows the review's own fix loop may have been cut short.
capped_after_report() {
  [[ -n "$(list_plans "$FAILED_DIR")" ]] || return 1
  [[ -z "$(list_plans "$INPROGRESS_DIR")$(list_plans "$INCOMPLETE_DIR")" ]] || return 1
  [[ -f "$REVIEW_REPORT" && "$(report_fingerprint)" != "$REVIEW_BEFORE" ]] || return 1
  grep -qs "reached the run budget" "$FAILED_DIR"/*.progress.md
}
open_pr=0
if [[ -n "${FEATURE_SLUG:-}" ]]; then
  if (( run_rc == 0 )) && [[ -z "$(list_plans "$FAILED_DIR")$(list_plans "$INPROGRESS_DIR")$(list_plans "$INCOMPLETE_DIR")" ]]; then
    open_pr=1
  elif (( BUDGET_CAPPED )) && capped_after_report; then
    echo ""
    echo "=== review pass hit its budget AFTER writing its report — opening the PR with that report ==="
    printf '\n---\n_Review pass reached its budget cap (%s USD) after writing this verdict; any fixes it was still applying may be incomplete. The review itself is as written above._\n' "$REVIEW_BUDGET_USD" >> "$REVIEW_REPORT"
    open_pr=1
  fi
fi
if (( open_pr )); then
  if [[ ! -x "$PR_SCRIPT" ]]; then
    echo ""
    echo "=== no PR hook at ${PR_SCRIPT#$REPO_DIR/} (run sync-plans.sh to seed one) ==="
  else
    echo ""
    echo "=== opening PR (${PR_SCRIPT#$REPO_DIR/}) ==="
    "$PR_SCRIPT" "$FEATURE_SLUG" "$REVIEW_REPORT"
    pr_rc=$?
    # Advisory, exactly like the gate: the review pass already succeeded, and failing
    # to open a PR does not retroactively make its findings wrong. Report and carry on.
    (( pr_rc != 0 )) && echo "=== PR hook exited $pr_rc — open the PR by hand ==="
  fi
elif [[ -n "${FEATURE_SLUG:-}" ]]; then
  echo ""
  echo "=== review pass did not finish cleanly — no PR opened ==="
fi

exit "$run_rc"
