#!/usr/bin/env bash
set -uo pipefail

# BUILD runner: executes the file-edit-only plans in plans/features/<slug>/auto/
# unattended. The feature slug may be given as the first argument, and is otherwise
# inferred from whichever feature has plans queued.
# Bash is DISABLED here (--disallowedTools Bash) so a build plan can't shell out
# under acceptEdits — verification is a separate pass (see run-verify.sh). All the
# queue/resume/logging/routing machinery lives in plan-runner-lib.sh; this wrapper
# only supplies the auto-batch config and the build-executor prompt.
#
# A plan file named NN-gate.md is a level sentinel, not a plan sent to claude: the runner
# runs plans/gate.sh NN in its place and continues. If a verify plan numbered <= NN is
# queued, it exits 64 (LEVEL_PAUSE_RC) so run-batch.sh (or a human) can run run-verify.sh --up-to NN first;
# re-running run-plans.sh resumes from the next build plan. See RUNNER.md, "Level
# sentinels".
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
QUEUE="auto"
PLAN_KIND="plan"
SUMMARY_TITLE="Run summary"

# --disallowedTools Bash enforces the "no bash" rule rather than merely asking:
# acceptEdits auto-approves edits but silently allows read-only bash (grep/find/ls),
# so without this a plan can burn budget shelling out. A plan that genuinely needs
# bash now fails loudly instead.
CLAUDE_TOOL_ARGS=(--disallowedTools Bash)

build_prompt() {
  local plan_path="$1"
  local log_path="$2"
  cat <<PROMPT
You are implementing a plan incrementally. A progress log is maintained automatically by the harness so this work can be resumed if interrupted.

Relevant files (absolute paths):
- Plan:         $plan_path
- Progress log: $log_path (auto-populated — do not write to it yourself)

Process:
1. Read the progress log first. Each line was appended by the harness and has the form '<tool>: <absolute file path>', recording a mutating tool call from a previous run. Treat it as a hint about which files may already be partially or fully updated.
2. Read the plan. For each discrete change it describes, verify the current on-disk state of the target file before editing — the log is a hint, not a source of truth. If the change is already applied, skip it; otherwise, make the change.
3. Do NOT Read or Write the progress log yourself. The harness appends to it live as you use Edit/Write/MultiEdit/NotebookEdit.
4. The Bash tool is disabled for this run — no shell commands, including read-only ones like grep/find/ls. Everything you need is in the plan or reachable with Read/Edit/Write. Verification is handled separately after all plans complete.
5. Once every change in the plan's file list is applied, stop. Do not re-open files you've already edited — or their siblings — to re-check signatures, props, or consistency "just in case." The plan's Facts section and any pasted or mirrored code are the source of truth for cross-file contracts; you cannot run a typechecker or test suite here to confirm anything further, and a separate pass (verify plan, gate.sh) does that after all plans complete. Re-reading a file for a fact you've already checked is the signal to stop, not to check again.

Plan contents:

$(cat "$plan_path")
PROMPT
}

source "$SCRIPT_DIR/plan-runner-lib.sh"
run_all "$@"
