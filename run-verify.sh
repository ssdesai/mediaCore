#!/usr/bin/env bash
set -uo pipefail

# VERIFY runner: executes the post-build verify plans in plans/features/<slug>/verify/
# after the auto batch finishes (see AGENT_PLANS.md "Verify plans"). The feature slug
# may be given as the first argument, and is otherwise inferred from whichever feature
# has plans queued. Differs from run-plans.sh in exactly the security-relevant way:
# Bash is ENABLED (--allowedTools Bash) and auto-approved alongside edits, so a
# high-level executor can actually run the work the build plans wrote — typecheck,
# tests, codegen checks — and fix or report the defects a bash-free build runner can't
# catch. All the shared queue/resume/logging/routing machinery lives in
# plan-runner-lib.sh; this wrapper only supplies the verify-batch config and the
# verify-executor prompt. Pass --up-to NN (after --self, if present) to bound the queue
# at a level sentinel's number, e.g. run-verify.sh --self --up-to 05 <slug> — see
# RUNNER.md, "Level sentinels".
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

# --up-to NN: drain only verify plans numbered <= NN. run-batch.sh passes the sentinel's
# number here after a level boundary so the level-verify plan runs before the next level
# builds on a red tree; the final verify, numbered above every sentinel, is left queued.
PLAN_MAX_NN=""
if [[ "${1:-}" == "--up-to" ]]; then
  PLAN_MAX_NN="${2:?--up-to needs a plan number}"
  shift 2
fi

QUEUE="verify"
PLAN_KIND="verify plan"
SUMMARY_TITLE="Verify run summary"

# The whole point of the separate script: Bash is on. --allowedTools adds it to the
# allowlist so it is auto-approved along with edits under acceptEdits. The build
# runner stays bash-free; only this privileged pass gets the wider scope.
CLAUDE_TOOL_ARGS=(--allowedTools Bash)

# A circuit breaker, not a budget: it should fire rarely, and when it does it means the
# brief asked for more than a verify pass should do. Every rule in AGENT_PLANS.md
# "Verify plans" is an instruction the executor can talk itself out of at turn 40 with a
# plausible reason; this is the one limit that does not depend on it judging its own scope.
#
# Calibrated on measured runs rather than guessed: the three verify passes that motivated
# these rules cost $6.14, $5.78 and $3.75, while the most expensive *legitimate* plan run in
# the same repo — a sonnet plan that wrote a whole test module — was $1.95. $3.00 clears any
# honest verify pass under the current rules and would have caught all three of those.
# Re-derive it after a few runs under the narrowed rules: take the median and double it.
#
# Enforced after each API call, so a run overshoots by at most one turn's spend.
VERIFY_BUDGET_USD="${VERIFY_BUDGET_USD:-3.00}"
CLAUDE_BUDGET_ARGS=(--max-budget-usd "$VERIFY_BUDGET_USD")

# The level passes get their own caps (RUNNER.md → "Red gates: the tier ladder"). A
# level-verify is a fix session for a RED level — it only runs when the gate failed — so
# it is expected to edit and re-run, and the first pilot's measured honest run was $3.82
# after a $3.00 cap had already stopped the same work once at 14/31 red. $6.00 clears
# that with room; re-derive as median × 2 once there are a few runs. An escalation is
# opus, reads the manifest and the queued plans, and may rewrite both — $8.00 is a
# starting estimate, not a measured value.
LEVEL_VERIFY_BUDGET_USD="${LEVEL_VERIFY_BUDGET_USD:-6.00}"
ESCALATION_BUDGET_USD="${ESCALATION_BUDGET_USD:-8.00}"

is_escalation_plan() { [[ "$(basename "$1")" =~ ^[0-9]+-escalation-[a-z]+\.md$ ]]; }
is_level_plan()      { [[ -n "$PLAN_MAX_NN" ]] || [[ "$(basename "$1")" =~ ^[0-9]+-level- ]]; }

budget_for_plan() {
  if is_escalation_plan "$1"; then
    CLAUDE_BUDGET_ARGS=(--max-budget-usd "$ESCALATION_BUDGET_USD")
  elif is_level_plan "$1"; then
    CLAUDE_BUDGET_ARGS=(--max-budget-usd "$LEVEL_VERIFY_BUDGET_USD")
  else
    CLAUDE_BUDGET_ARGS=(--max-budget-usd "$VERIFY_BUDGET_USD")
  fi
  echo "    budget: ${CLAUDE_BUDGET_ARGS[1]} USD"
}

# Tier 2 of the red-gate ladder: a synthesized opus plan (write_escalation_plan in
# plan-runner-lib.sh). Its brief already carries the charge; this preamble only sets the
# tool rules, which differ from a verify pass in one way — it may edit plan files.
build_escalation_prompt() {
  local plan_path="$1"
  local log_path="$2"
  cat <<PROMPT
You are running an ESCALATION plan: the pass the batch runs when a level's gate is still red after its level-verify (which was forbidden from changing a contract). You may change a contract; you may edit queued plan files so they mirror what you changed; you must leave the level's gate green. A progress log is maintained automatically by the harness so this work can be resumed if interrupted.

Relevant files (absolute paths):
- Plan:         $plan_path
- Progress log: $log_path (auto-populated — do not write to it yourself)

Rules:
1. Read the progress log first: each line is '<tool>: <absolute file path>' for a mutating call from a previous attempt.
2. Read the plan. It names what to read and in which order — the manifest comes before the code.
3. Bash IS available. Use it to re-run the failing gate sections and, at the end, the whole gate script.
4. NEVER mutate repo-wide VCS state: no \`git stash\`, \`git checkout\`, \`git reset\`, \`git clean\`, or branch switch. The plan queue is untracked working-tree state and this run can stop at any turn. Read-only git is fine.
5. Do NOT Read or Write the progress log yourself.

Plan contents:

$(cat "$plan_path")
PROMPT
}

# Appended to the verify preamble when the plan is a level-verify (tier 1). The one rule
# that makes tier 1 cheap and safe to run unattended: it fixes the tree to the contract,
# never the contract to the tree.
level_verify_rules() {
  cat <<RULES
11. THIS IS A LEVEL-VERIFY (tier 1 of the red-gate ladder). Your job is to make THIS level's gate green — the sections the plan names — and nothing above it. You may fix code, tests and fixtures at this level to match the contract the manifest states. You may NOT change a contract: no renamed or re-typed identifier, field, route, fixture shape or signature that a plan queued above this level could be pinning. If the gate cannot go green without such a change, write \`$FEATURES_LABEL/${FEATURE_SLUG:-<slug>}/escalations/${PLAN_MAX_NN:-NN}.md\` stating which contract must change and why, stop editing, and end your turn. The batch will run an escalation pass with the authority you lack; what it needs from you is the precise question, not a half-applied answer.
12. THE GATE REPORT IS THE EVIDENCE. It ran under the repo's own shell and toolchain (\`#!/usr/bin/env bash\` — on macOS that is bash 3.2), which may differ from the shell your Bash tool uses. If a failure in the report does not reproduce when you run the command yourself, that difference IS the finding — read the report's output tail and the gate script line that produced it before touching anything else. The first tiered pilot's tier 1 spent a whole pass on tests that were already green because the real red (a bash-3.2 array subscript in the gate) did not reproduce in its shell.
13. Finish by running \`$GATE_SCRIPT_LABEL ${PLAN_MAX_NN:-NN}\` and reporting its verdict line verbatim.
RULES
}

build_prompt() {
  local plan_path="$1"
  local log_path="$2"
  if is_escalation_plan "$plan_path"; then build_escalation_prompt "$plan_path" "$log_path"; return; fi
  cat <<PROMPT
You are running a VERIFY plan: a post-build pass that checks work produced by a batch of build plans (which ran under run-plans.sh with no bash and could not run what they wrote). A progress log is maintained automatically by the harness so this work can be resumed if interrupted.

Relevant files (absolute paths):
- Plan:         $plan_path
- Progress log: $log_path (auto-populated — do not write to it yourself)

Process:
1. Read the progress log first. Each line was appended by the harness as '<tool>: <absolute file path>', recording a mutating tool call from a previous run. Treat it as a hint about which files you may already have changed.
2. Read the plan. It is a BRIEF, not a diff: it states the goal and the checks — not step-by-step edits. Use your judgment.
3. If $GATE_REPORT_LABEL exists, read it. Install, format, lint, tests, typecheck and build ALREADY RAN and their output is in that report. Do not re-run them. If it lists failures, triage those first and re-run only the specific check that failed. If it lists a check as SKIPPED, treat that as absent information, not as a pass: either run that check yourself or state in your summary exactly what is consequently unverified.
4. READ THE TESTS BEFORE CHECKING ANYTHING BY HAND. The gate report says which checks ran, not what they assert. For every behaviour the plan asks you to confirm, first open the test files covering that surface. If a test already asserts it, say so and move on — do NOT re-establish it empirically. Re-deriving what the suite already proves is the single largest waste in this pass.
5. DO NOT BUILD A WORLD. Constructing a collection, generating fixtures, starting a server and driving it over HTTP is a test's job, written once and run free thereafter — not work to redo here at this model rate. If a check would need that setup, the answer is 'this needs a test', and reporting the assertion that would cover it is worth more than performing the check once.
6. Do not check whether a model obeys an instruction. Such checks are flaky by construction and cannot fail informatively.
7. Bash IS available. Spend it on what a script cannot express: cross-layer invariants, security boundaries, adversarial inputs that need no setup, and re-running one specific failing check.
8. FIX ONLY WHAT IS LOCAL — a wrong monkeypatch target, an assertion on the wrong field name, a drifted README line (edits are auto-accepted; re-run to confirm). Anything needing a new function, a changed signature, or a design decision is NOT yours to implement: report it, with the failing command and its verbatim output, as work for the next batch's build plan. Fixes here run at peak context and cost several times what the same edit costs in a build plan.
9. NEVER mutate repo-wide VCS state: no \`git stash\`, \`git checkout\`, \`git reset\`, \`git clean\`, or branch switch. Two reasons, both load-bearing. (a) The plan queue you are running from is UNTRACKED working-tree state, so \`git stash -u\` sweeps this plan, its progress log and its usage record out from under the runner — and \`git stash pop\` restores the files but not the queue directories it emptied, which strands this plan in inprogress/ where the next run resumes it. (b) This run can stop at ANY turn (budget cap, usage limit), and a stop between stash and pop leaves the whole batch's uncommitted output in a stash nobody knows to look for. To compare behaviour against a baseline, use \`git worktree add <scratch-path> HEAD\` — it never touches this working tree — or report the comparison as work for the next batch. Read-only git (\`status\`, \`log\`, \`diff\`, \`show\`) is fine.
10. Do NOT Read or Write the progress log yourself. The harness appends to it live as you use Edit/Write.
$(if is_level_plan "$plan_path"; then level_verify_rules; fi)
Plan contents:

$(cat "$plan_path")
PROMPT
}

source "$SCRIPT_DIR/plan-runner-lib.sh"
run_all "$@"
