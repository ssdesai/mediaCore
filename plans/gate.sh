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
# One pure-Python package, built with hatchling, installed editable into this
# repo's own .venv. The venv is per-tree (never shared with a sibling worktree),
# so two gates running at once cannot fight over one editable install.
VENV_PYTHON="$REPO_DIR/.venv/bin/python"

if [[ ! -x "$VENV_PYTHON" ]]; then
  BOOTSTRAP_PYTHON="$(command -v python3.13 || command -v python3.12 \
    || command -v python3.11 || command -v python3 || true)"
  if [[ -z "$BOOTSTRAP_PYTHON" ]]; then
    { echo "GATE: ENVIRONMENT UNUSABLE"
      echo "No python3 on PATH; cannot create $REPO_DIR/.venv."; } | tee "$REPORT"
    exit 1
  fi
  if ! venv_out="$("$BOOTSTRAP_PYTHON" -m venv "$REPO_DIR/.venv" 2>&1)"; then
    { echo "GATE: ENVIRONMENT UNUSABLE"
      echo "python -m venv failed:"; echo "$venv_out"; } | tee "$REPORT"
    exit 1
  fi
fi

PY=("$VENV_PYTHON")
INSTALL=("$VENV_PYTHON" -m pip install -e ".[dev]" -q --disable-pip-version-check)
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
# No server, no database, no ports: this repo is one pure-Python package plus a
# fixture generator, so the whole gate is install / lint / fixture / tests.

# The fixture bundle under fixtures/its-saxy/ is generated, not hand-written, and
# every filename in it is a sha256 of the generated bytes. It is therefore only
# trustworthy while `scripts/make_fixture_its_saxy.py` is deterministic. This check
# proves that two ways:
#   1. regenerate in place, then regenerate again into a temp directory and require
#      the two trees to be byte-identical (catches randomness/timestamps even before
#      the fixture is committed, which is the state during the batch that builds it);
#   2. require `git status --porcelain fixtures/` to be empty afterwards — i.e. the
#      committed fixture is exactly what the script produces today.
# The `?? fixtures/` line is filtered out of (2): a wholly-untracked fixtures/ means
# "not committed yet", which (1) already covers, whereas a modified tracked file
# shows up as ` M fixtures/...` and is a real failure.
fixture_idempotent() {
  local tmp dirty
  "${PY[@]}" scripts/make_fixture_its_saxy.py || return 1
  tmp="$(mktemp -d)" || return 1
  if ! "${PY[@]}" scripts/make_fixture_its_saxy.py "$tmp/its-saxy"; then
    rm -rf "$tmp"; return 1
  fi
  if ! diff -r "$tmp/its-saxy" "$REPO_DIR/fixtures/its-saxy"; then
    echo "regenerating the fixture twice produced different trees"
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"
  dirty="$(git status --porcelain fixtures/ | grep -v '^?? fixtures/$' || true)"
  if [[ -n "$dirty" ]]; then
    echo "fixtures/ changed when the generator was re-run:"
    echo "$dirty"
    return 1
  fi
  return 0
}

echo "=== gate: installing ==="
record "install" "${INSTALL[@]}" || {
  { echo "# VERDICT"
    echo "ENVIRONMENT UNUSABLE — install failed."; } >> "$REPORT"
  echo "=== gate: aborted — install failed ==="
  exit 1
}

record "lint" "${PY[@]}" -m ruff check src tests

# Runs before "tests" so tests/test_fixture.py reads a freshly generated bundle.
record "fixture idempotent" fixture_idempotent

# Expected-red globs from the level sentinel become --ignore-glob flags, so a level
# is judged only on what it owns. pytest fnmatches the glob against the *absolute*
# collected path, so a repo-relative glob ("tests/test_fixture.py") never matches on
# its own — prefix it with */ unless the sentinel already wrote an absolute or
# wildcard-leading pattern.
IGNORES=()
for glob in $GATE_EXPECTED_RED; do
  case "$glob" in
    /*|\**) IGNORES+=("--ignore-glob=$glob") ;;
    *)      IGNORES+=("--ignore-glob=*/$glob") ;;
  esac
done
record "tests" "${PY[@]}" -m pytest -q ${IGNORES[@]+"${IGNORES[@]}"}
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
