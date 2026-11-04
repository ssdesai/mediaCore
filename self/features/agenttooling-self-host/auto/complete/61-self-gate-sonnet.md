# 61 — agentTooling's mechanical gate

Feature: `agenttooling-self-host`, plan 3 of 5. Makes `agentTooling/` able to run the
delegated-plan workflow on itself (`--self`), so harness features are planned, executed
and costed inside agentTooling instead of inside whichever repo vendors it.

Write `agentTooling/self/gate.sh`, the deterministic check pass `run-batch.sh --self`
runs between the build and verify passes.

Independent of other plans. (Plan 59 makes `run-batch.sh --self` call this file; plan 60
writes the READMEs that describe it. Neither touches `self/gate.sh` itself.)

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- The gate's contract with `run-batch.sh`, stated in `templates/plans/gate.sh:20-27`:
  exit non-zero **only** when the environment is unusable, exit 0 otherwise even when
  checks failed, and write results to the report file in the `## label` / `$ cmd` /
  `exit: N` / output-tail format. A red tree is frequently what the verify pass exists
  to fix, so failures are recorded, not blocked on.
- This file sits one level deeper than a consuming repo's `plans/gate.sh`, but the
  template's `REPO_DIR="$(… "$(dirname "${BASH_SOURCE[0]}")/.." …)"` still resolves
  correctly: `self/..` is `agentTooling/`. Only the report path differs.
- `run-batch.sh --self` expects the report at `agentTooling/self/gate-report.txt`
  (`GATE_REPORT_LABEL="self/gate-report.txt"`, set in `plan-runner-roots.sh`). It is
  gitignored by `agentTooling/.gitignore`.
- **There is no test suite and no test runner.** agentTooling is bash plus stdlib-only
  Python 3 run directly — no `pyproject.toml`, no venv, no `npm`, no install step. The
  checks below are the entire mechanical surface.
- `analysis/*.py` import each other bare (`from pricing import compute_cost`), which
  works because Python puts the script's own directory on `sys.path`. `py_compile`
  compiles each file independently and does not exercise those imports, so it catches
  syntax errors only — that is the honest limit of what this gate can assert.
- `pricing.is_rates_stale()` reports whether the rate table has aged past
  `STALENESS_THRESHOLD_DAYS`. `analysis/README.md` makes checking it step 1 of the
  weekly flow; surfacing it here is cheaper than a human remembering.
- Scripts run under bash 3.2 (system bash on macOS) with `set -uo pipefail` and no
  `set -e`.

## Files

- Create `agentTooling/self/gate.sh` (executable)

## `agentTooling/self/gate.sh`

Start from `templates/plans/gate.sh` and keep its scaffolding **verbatim** — the header
contract comment (`:1-27`), `OUTPUT_TAIL_LINES`, the `cd`, the report preamble
(`:52-57`), `any_failed`/`check_count`, the `_record`/`record`/`record_info` helpers
(`:59-97`), and the verdict block (`:121-138`). That machinery is what `run-batch.sh`
reads; do not restyle it. Two adjustments and two replacements:

**Adjustments.** `REPORT` becomes `$REPO_DIR/self/gate-report.txt`, and the closing
`echo "=== gate: report at plans/gate-report.txt ==="` becomes
`self/gate-report.txt`. Replace the template's "seeded once into plans/gate.sh by
sync-plans.sh, fill in the REPO-SPECIFIC sections" paragraph (`:11-18`) — this file is
neither seeded nor a skeleton — with a note that this is agentTooling's own gate, run by
`run-batch.sh --self`, and that the consuming-repo counterpart is the template it was
derived from.

**Replacement 1 — the toolchain block (`:35-49`).** The only hard requirement is
`python3`; bash is running this script by definition. Missing `python3` means every
`analysis/` check is meaningless, which is the template's own bar for exiting 1:

```bash
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
```

**Replacement 2 — the checks block (`:99-119`).** Five checks. Shell syntax and Python
syntax are blocking; the other three are `record_info`, because each reports a condition
that is real but does not mean this batch is broken:

```bash
# ── The checks ───────────────────────────────────────────────────────────────
echo "=== gate: shell syntax ==="
# Every tracked script, including this one and the consuming-repo template. `bash -n`
# parses without executing, which is the whole of what can be checked without a
# harness — these scripts drive `claude -p` and cannot be run for effect here.
shell_scripts=(
  run-plans.sh
  run-verify.sh
  run-batch.sh
  plan-runner-lib.sh
  plan-runner-roots.sh
  sync-plans.sh
  migrate-plans-layout.sh
  self/gate.sh
  templates/plans/gate.sh
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
```

**Do not attempt to set the executable bit** — you have no Bash tool, and a file written
with `Write` lands non-executable. `run-batch.sh` skips a gate that fails
`[[ -x "$GATE_SCRIPT" ]]`, so as written this file is inert until
`chmod +x agentTooling/self/gate.sh` is run by hand; that is a step in interactive plan
`64-self-host-migrate.md`. Nothing about the file's *contents* depends on it.
