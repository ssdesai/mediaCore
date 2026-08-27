#!/usr/bin/env bash
set -uo pipefail

# Mechanical pre-verify gate, run by ../../run-batch.sh between the build and
# verify passes. Runs this repo's deterministic checks — install, lint, tests,
# typecheck, build — and writes plans/gate-report.txt for the verify plan to read.
#
# Why this exists: running a test suite is deterministic and needs no model, but
# without this it happens *inside* the verify pass, at the highest model rate in
# the workflow. Doing it here means the verify executor reads a result instead of
# spending turns generating one. See ../../AGENT_PLANS.md -> "The mechanical gate".
#
# Seeded ONCE into plans/gate.sh by ../../sync-plans.sh, exactly like
# PROJECT_FACTS.md — then repo-owned, never overwritten again. Fill in the two
# REPO-SPECIFIC sections below with this project's real commands and delete
# whichever don't apply. A repo with no gate.sh (or a non-executable one) is
# fine too: run-batch.sh just skips the step.
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
REPORT="$REPO_DIR/plans/gate-report.txt"
OUTPUT_TAIL_LINES=40

# Optional level label, passed by the runner when this gate runs at a level sentinel
# (NN-gate.md) instead of at the end of the batch. The report is always written to
# $REPORT; with a label it is also copied to gate-report.<label>.txt so the per-level
# results survive the final run overwriting $REPORT.
LEVEL_LABEL="${1:-}"
# Set by the runner from the sentinel's `expected-red:` / `defer:` lines (plan-runner-roots.sh
# → level_expectations); empty at the final gate. Honoured below: the test run ignores the
# expected-red globs, and a deferred section is recorded as DEFERRED and not run. DEFERRED
# does not count against the verdict — it is not this level's business, unlike SKIPPED,
# which is a check that could not run and leaves the level unverified.
GATE_EXPECTED_RED="${GATE_EXPECTED_RED:-}"
GATE_DEFERRED="${GATE_DEFERRED:-}"; GATE_DEFERRED="${GATE_DEFERRED//, /,}"   # "a, b" and "a,b" both match

cd "$REPO_DIR" || exit 1

# ── REPO-SPECIFIC: resolve the toolchain, exit 1 if it isn't usable ──────────
# Example (Python project with uv, falling back to a committed .venv):
#
#   if command -v uv >/dev/null 2>&1; then
#     PY=(uv run python); INSTALL=(uv pip install -e ".[dev]")
#   elif [[ -x "$REPO_DIR/.venv/bin/python" ]]; then
#     PY=("$REPO_DIR/.venv/bin/python")
#     INSTALL=("$REPO_DIR/.venv/bin/python" -m pip install -e ".[dev]" -q)
#   else
#     { echo "GATE: ENVIRONMENT UNUSABLE"; echo "No uv on PATH and no .venv."; } | tee "$REPORT"
#     exit 1
#   fi
#
# A Node-only repo would resolve `node`/`npm` here instead; a Go repo would check
# `go`. Whatever this repo needs to run its own checks.
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
  if [[ -n "$GATE_DEFERRED" && ",$GATE_DEFERRED," == *",$label,"* ]]; then
    check_count=$((check_count + 1))
    { echo "## $label"; echo "deferred: not owned by level ${LEVEL_LABEL:-final}; runs at a later gate"; echo ""; } >> "$REPORT"
    echo "=== gate: $label — DEFERRED (level $LEVEL_LABEL) ==="
    return 0
  fi
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

# ── REPO-SPECIFIC: the checks themselves ─────────────────────────────────────
# Nothing is configured yet. Replace this whole block with this repo's real
# checks, e.g.:
#
#   echo "=== gate: installing ==="
#   record "install" "${INSTALL[@]}" || { echo "# VERDICT" >> "$REPORT"; \
#     echo "ENVIRONMENT UNUSABLE — install failed." >> "$REPORT"; exit 1; }
#   record "lint" "${PY[@]}" -m ruff check src tests
#   if [[ -d "$REPO_DIR/database" ]]; then
#     # Expected-red globs from the level sentinel become --ignore-glob flags:
#     IGNORES=(); for g in $GATE_EXPECTED_RED; do IGNORES+=("--ignore-glob=$g"); done
#     # With pytest-xdist in the dev extras, `-n auto --dist loadfile` roughly halves
#     # the section; loadfile keeps each file's tests on one worker, so tests that
#     # write shared fixture files cannot race each other across workers.
#     record "tests" "${PY[@]}" -m pytest -q ${IGNORES[@]+"${IGNORES[@]}"}
#   else
#     record_skip "tests" "postgres unreachable — see gate header"
#   fi
#   # Two gates run at once whenever two worktrees are in flight (EXPERIMENTS.md arms,
#   # one batch per feature), and a suite that binds a fixed port — a dev server, a
#   # real-backend browser suite — makes them race for it; either side can lose and
#   # read as red. Bind-probe free ports here and hand them to the suites' configs
#   # via env, with the configs defaulting to the usual values for bare runs.
#   DEV_PORT=$("${PY[@]}" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
#   export DEV_PORT
#   record "frontend typecheck" npm --prefix frontend run typecheck
#   record "frontend build" npm --prefix frontend run build
#
echo "  note  plans/gate.sh has not been filled in for this repo yet"
{
  echo "## (unconfigured)"
  echo "plans/gate.sh has not been filled in for this repo yet — no checks ran."
  echo "Edit it with this repo's real install/lint/test/typecheck/build commands;"
  echo "see agentTooling/templates/plans/gate.sh for the skeleton and"
  echo "agentTooling/AGENT_PLANS.md -> \"The mechanical gate\" for what belongs here."
} >> "$REPORT"
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
echo "=== gate: report at plans/gate-report.txt ==="
exit 0
