#!/usr/bin/env bash
set -uo pipefail

# Mechanical pre-verify gate, run by ../run-batch.sh between the build and
# verify passes. Runs this repo's deterministic checks — install, lint, tests,
# typecheck, build — and writes plans/gate-report.txt for the verify plan to read.
#
# Why this exists: running a test suite is deterministic and needs no model, but
# without this it happens *inside* the verify pass, at the highest model rate in
# the workflow. Doing it here means the verify executor reads a result instead of
# spending turns generating one. See ../../AGENT_PLANS.md -> "The mechanical gate".
#
# This is agentTooling's own gate, not a skeleton — it is run directly by
# ../run-batch.sh --self between agentTooling's own build and verify passes.
# The consuming-repo counterpart, seeded into plans/gate.sh by sync-plans.sh, is
# templates/plans/gate.sh — the template this file was derived from.
#
# Contract run-batch.sh relies on — do not change this part when customizing:
#   - Exit non-zero ONLY when the environment itself is unusable (no interpreter,
#     install failed). Then, and only then, no downstream result means anything,
#     and run-batch.sh skips the verify pass.
#   - Otherwise exit 0, even when checks failed. A red tree is often exactly what
#     the verify pass exists to fix, since build plans run without bash and can't
#     run what they wrote — recording failures, not blocking on them, is the point.
#   - Write results to plans/gate-report.txt in the format below so the verify
#     plan can read it without re-deriving the structure.
#   - A gate provisions what it needs or fails loudly. A silently skipped check is
#     worse than a failing one: a failure is triaged, an absence is inferred as a
#     pass. Prefer starting your own database or container over skipping when the
#     environment is not already warm — e.g. `docker compose up -d --no-build <svc>`
#     (so a missing image fails in seconds, not after a multi-minute build), poll for
#     readiness, and leave it running for the verify pass. Use record_skip, never a
#     bare echo, for anything that genuinely cannot run.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT="$REPO_DIR/self/gate-report.txt"
OUTPUT_TAIL_LINES=40

# Optional level label, passed by the runner when this gate runs at a level sentinel
# (NN-gate.md) instead of at the end of the batch. The report is always written to
# $REPORT; with a label it is also copied to gate-report.<label>.txt so the per-level
# results survive the final run overwriting $REPORT.
LEVEL_LABEL="${1:-}"

cd "$REPO_DIR" || exit 1

# ── Toolchain: python3 is the only hard requirement ──────────────────────────
# bash is running this script by definition. Without python3 every analysis/ check
# below is meaningless, which is this gate's bar for "environment unusable" — see the
# contract at the top. jq and claude are NOT checked here: the runners' require_tools
# already exits 127 on them, and their absence doesn't invalidate these checks. They
# are recorded informationally at the end instead.
if ! command -v python3 >/dev/null 2>&1; then
  { echo "GATE: ENVIRONMENT UNUSABLE"; echo "No python3 on PATH."; } | tee "$REPORT"
  exit 1
fi
# ──────────────────────────────────────────────────────────────────────────────

: > "$REPORT"
{
  echo "# Gate report"
  echo "generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "level: ${LEVEL_LABEL:-final}"
  echo ""
} >> "$REPORT"

any_failed=0
check_count=0
skip_count=0

# Run one check, append its command, exit code, and output tail to the report.
# _record <informational?> <label> <cmd...>
_record() {
  local informational="$1"; shift
  local label="$1"; shift
  local out rc
  out="$("$@" 2>&1)"
  rc=$?
  check_count=$((check_count + 1))
  {
    echo "## $label"
    echo "\$ $*"
    echo "exit: $rc"
    echo "$out" | tail -n "$OUTPUT_TAIL_LINES"
    echo ""
  } >> "$REPORT"
  if (( rc != 0 )); then
    if [[ "$informational" == "info" ]]; then
      echo "  note  $label (exit $rc, informational)"
    else
      any_failed=1
      echo "  FAIL  $label (exit $rc)"
    fi
  else
    echo "  ok    $label"
  fi
  return $rc
}

record() { _record blocking "$@"; }

# Recorded for the verify executor to compare against a baseline, but never
# counted toward the verdict — a check with a known standing backlog (e.g. a lint
# rule set this repo hasn't fully cleaned up) must not cry wolf every run, or the
# verdict line stops carrying information.
record_info() { _record info "$@"; }

# A check that could not run at all. Counted separately so the verdict can say so: a
# skipped suite is absent information, not a pass, and a verify executor reading this
# report must not infer green from a missing section.
record_skip() {            # record_skip <label> <reason>
  local label="$1" why="$2"
  check_count=$((check_count + 1))
  skip_count=$((skip_count + 1))
  { echo "## $label"; echo "SKIPPED: $why"; echo ""; } >> "$REPORT"
  echo "  SKIP  $label — $why"
}

# ── The checks ───────────────────────────────────────────────────────────────
echo "=== gate: shell syntax ==="
# Every tracked script, including this one and the consuming-repo template. `bash -n`
# parses without executing, which is the whole of what can be checked without a
# harness — these scripts drive `claude -p` and cannot be run for effect here.
shell_scripts=(
  run-plans.sh
  run-verify.sh
  run-review.sh
  run-batch.sh
  plan-runner-lib.sh
  plan-runner-roots.sh
  sync-plans.sh
  migrate-plans-layout.sh
  self/gate.sh
  self/pr.sh
  self/tests/level-sentinel.sh
  self/tests/tiered-gates.sh
  self/tests/cost-recovery.sh
  self/tests/capture-guard.sh
  self/tests/timestamps-are-utc.sh
  self/tests/subagent-capture.sh
  run-escalation-plan.sh
  templates/plans/gate.sh
  templates/plans/pr.sh
)
for script in "${shell_scripts[@]}"; do
  record "bash -n $script" bash -n "$script"
done

echo "=== gate: shell lint ==="
# Informational, and skipped entirely when absent: shellcheck is not a dependency of
# this repo and must not turn a machine without it into a red gate.
if command -v shellcheck >/dev/null 2>&1; then
  record_info "shellcheck" shellcheck "${shell_scripts[@]}"
else
  echo "  skip  shellcheck (not installed)"
fi

echo "=== gate: level sentinels ==="
# The one behavioural check this repo has: drives the real runners in a throwaway
# checkout with a stub claude and a stub gate (self/tests/README.md). Blocking, because
# every assertion in it is a contract run-batch.sh branches on.
record "level sentinel self-test" bash self/tests/level-sentinel.sh
record "tiered gates self-test" bash self/tests/tiered-gates.sh
record "cost recovery self-test" bash self/tests/cost-recovery.sh
record "capture guard self-test" bash self/tests/capture-guard.sh
record "timestamps are utc self-test" bash self/tests/timestamps-are-utc.sh
record "subagent capture self-test" bash self/tests/subagent-capture.sh

echo "=== gate: python syntax ==="
# Compiles each file independently — it does NOT exercise the bare cross-imports
# (`from pricing import …`), which only resolve when a script is run directly and
# python puts its own directory on sys.path.
record "py_compile analysis" python3 -m py_compile analysis/*.py

echo "=== gate: rate table ==="
# analysis/README.md makes this step 1 of the weekly flow. Informational by design:
# a stale table skews cost figures but breaks nothing, and capture_planning.py and
# report.py both surface it in their own warnings[] as well.
record_info "pricing rate table is current" \
  python3 -c "import sys; sys.path.insert(0, 'analysis'); import pricing; sys.exit(1 if pricing.is_rates_stale() else 0)"

echo "=== gate: runner prerequisites ==="
# Informational: require_tools inside the runners is the real enforcement (exit 127).
# Recorded because a missing jq is this harness's worst failure mode — both jq call
# sites suppress stderr, so it yields an empty progress log, no terminal output, and
# every plan still filed complete.
record_info "claude and jq on PATH" \
  bash -c 'command -v claude >/dev/null && command -v jq >/dev/null'
# ──────────────────────────────────────────────────────────────────────────────

if (( check_count == 0 )); then
  # Distinct from "all checks passed": zero checks ran, so a verify plan reading
  # this report must not treat silence as a green build.
  overall_note="GATE NOT CONFIGURED — no checks were run, see plans/gate.sh"
elif (( any_failed )); then
  overall_note="one or more checks FAILED — see sections above; triage is the verify executor's job"
elif (( skip_count > 0 )); then
  overall_note="checks that ran passed, but $skip_count SKIPPED — NOT a green build; a skipped suite is absent information, not a pass"
else
  overall_note="all checks passed"
fi

{
  echo "# VERDICT"
  echo "$overall_note"
} >> "$REPORT"

if [[ -n "$LEVEL_LABEL" ]]; then
  cp "$REPORT" "${REPORT%.txt}.$LEVEL_LABEL.txt"
fi

echo "=== gate: done — $overall_note ==="
echo "=== gate: report at self/gate-report.txt ==="
exit 0
