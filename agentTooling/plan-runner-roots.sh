#!/usr/bin/env bash
# Root resolution shared by run-plans.sh, run-verify.sh, run-review.sh and
# run-batch.sh. Sourced (never executed) before plan-runner-lib.sh, which needs
# REPO_DIR and FEATURES_DIR already set.
#
# Two modes, differing only in which repo's queue a run drains:
#
#   normal   REPO_DIR = the consuming repo root (this checkout's parent)
#            queue    = plans/features/<slug>/
#   --self   REPO_DIR = this agentTooling checkout
#            queue    = self/features/<slug>/
#
# Self-mode is how agentTooling builds its own features with its own harness. It lives
# here rather than in each wrapper for the same reason plan-runner-lib.sh exists: three
# copies of a two-branch path rule is three chances for the modes to drift apart, and a
# run that resolves the wrong root files its cost records under the wrong repo.

# resolve_roots <first-arg>
#
# Inspects only whether the first argument is --self; the caller does the shift, so
# nothing here mutates the caller's positional parameters.
#
# Sets, for the caller:
#   SELF_MODE          1 when --self was passed, else 0
#   REPO_DIR           the root the runner cd's to, so claude runs from there
#   FEATURES_DIR       absolute path to the per-feature tree
#   FEATURES_LABEL     that same path as a human would type it FROM REPO_DIR — used in
#                      messages, which are all printed after run_all's cd
#   SELF_ARG           "--self " or "", so a message can echo back a command line that
#                      actually reproduces this run
#   GATE_SCRIPT        the mechanical gate run-batch.sh runs after the build pass
#   GATE_SCRIPT_LABEL  that same path relative to REPO_DIR, for executor prompts
#   GATE_REPORT_LABEL  where that gate leaves its report, relative to REPO_DIR
#   PR_SCRIPT          the repo-owned PR hook run-review.sh runs after a clean pass
#   REVIEW_REPORT      absolute path the review executor writes its findings to, and
#                      the PR hook reads as the PR body
#   REVIEW_REPORT_LABEL that same path relative to REPO_DIR, for the executor prompt
# Exit code run-plans.sh uses for "paused at a level boundary — a level-verify plan is
# queued" (RUNNER.md → "Level sentinels"). Reserved: finalize_plan and run_level_gate clamp
# a child process that happens to exit with this code, so a failed plan or gate can never
# be mistaken for a pause by run-batch.sh. 64 is EX_USAGE in sysexits.h, which neither
# claude nor a gate script returns in practice; 1-3 and 127/130 are already spoken for.
LEVEL_PAUSE_RC=64

resolve_roots() {
  local first_arg="${1:-}"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ "$first_arg" == "--self" ]]; then
    SELF_MODE=1
    REPO_DIR="$script_dir"
    FEATURES_DIR="$script_dir/self/features"
    FEATURES_LABEL="self/features"
    SELF_ARG="--self "
    GATE_SCRIPT="$script_dir/self/gate.sh"
    GATE_SCRIPT_LABEL="self/gate.sh"
    GATE_REPORT_LABEL="self/gate-report.txt"
    PR_SCRIPT="$script_dir/self/pr.sh"
    REVIEW_REPORT="$script_dir/self/review-report.md"
    REVIEW_REPORT_LABEL="self/review-report.md"
  else
    SELF_MODE=0
    REPO_DIR="$(cd "$script_dir/.." && pwd)"
    FEATURES_DIR="$REPO_DIR/plans/features"
    FEATURES_LABEL="plans/features"
    SELF_ARG=""
    GATE_SCRIPT="$REPO_DIR/plans/gate.sh"
    GATE_SCRIPT_LABEL="plans/gate.sh"
    GATE_REPORT_LABEL="plans/gate-report.txt"
    PR_SCRIPT="$REPO_DIR/plans/pr.sh"
    REVIEW_REPORT="$REPO_DIR/plans/review-report.md"
    REVIEW_REPORT_LABEL="plans/review-report.md"
  fi
}

# level_expectations <sentinel-path>
#
# A sentinel (NN-gate.md) may say what its level does NOT own, so the gate's verdict is
# about this level and not about tests that are red by design until a level above builds
# them (the first tiered pilot spent a tier-1 and a tier-2 pass on a level that was green
# everywhere it owned). Two directives, each on its own line, each optional:
#
#   expected-red: <glob> [<glob>...]   test paths the gate's test run ignores at this level
#   defer: <label>, <label>, ...       gate sections recorded as deferred, not run
#
# Exported for the repo's gate.sh as GATE_EXPECTED_RED (space-separated) and GATE_DEFERRED
# (comma-separated); both empty for the final gate, which owns everything. A gate.sh that
# predates these ignores them and behaves as before.
level_expectations() {
  local sentinel="${1:-}"
  GATE_EXPECTED_RED=""
  GATE_DEFERRED=""
  [[ -f "$sentinel" ]] || { export GATE_EXPECTED_RED GATE_DEFERRED; return 0; }
  GATE_EXPECTED_RED="$(sed -n 's/^expected-red:[[:space:]]*//p' "$sentinel" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  GATE_DEFERRED="$(sed -n 's/^defer:[[:space:]]*//p' "$sentinel" | tr '\n' ',' | sed 's/,[[:space:]]*$//')"
  export GATE_EXPECTED_RED GATE_DEFERRED
}
