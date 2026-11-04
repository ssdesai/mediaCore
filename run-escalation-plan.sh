#!/usr/bin/env bash
set -uo pipefail

# Queue the tier-2 escalation plan for one level: run-escalation-plan.sh [--self] <slug> <NN>.
# Writes plans/features/<slug>/verify/incomplete/NN-escalation-opus.md (see
# write_escalation_plan in plan-runner-lib.sh) and prints its path. Exits 1 without
# writing when an escalation for that level already exists in any state — the batch
# must never buy the same escalation twice. Called by run-batch.sh's settle_level; by
# hand it is the way to re-arm tier 2 after editing the note under escalations/.
#
# A separate script rather than a function in run-batch.sh because the plan body needs
# the lib's root variables (FEATURES_LABEL, GATE_REPORT_LABEL, …) and run-batch.sh does
# not source the lib — run_all is not something a sequencing wrapper should have loaded.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
if (( SELF_MODE )); then shift; fi

SLUG_ARG="${1:?usage: run-escalation-plan.sh [--self] <slug> <NN>}"
LEVEL_NN="${2:?usage: run-escalation-plan.sh [--self] <slug> <NN>}"

QUEUE="verify"
PLAN_KIND="verify plan"
SUMMARY_TITLE=""
CLAUDE_TOOL_ARGS=()
build_prompt() { :; }
source "$SCRIPT_DIR/plan-runner-lib.sh"
FEATURE_SLUG="$SLUG_ARG"   # after the source: the lib resets it to "" when loaded

[[ -d "$FEATURES_DIR/$FEATURE_SLUG" ]] || { echo "no feature '$FEATURE_SLUG' under $FEATURES_LABEL" >&2; exit 2; }
write_escalation_plan "$LEVEL_NN"
