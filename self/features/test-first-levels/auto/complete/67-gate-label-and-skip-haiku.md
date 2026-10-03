# 67 — Gate label, per-level report copy, and a loud SKIPPED

Feature `test-first-levels`, plan 3 of 6. The feature reorders a batch into **levels** —
tests first, then per-layer build plans — with the free mechanical gate run at every level
boundary via a sentinel plan file `NN-gate.md`, so a cross-layer seam fails at the
boundary it crosses instead of at review one batch later.

Summary: both gate scripts accept an optional level label, copy their report to a
per-level file, gain a `record_skip` primitive, and stop letting a skipped check read as a
pass.

Independent of other plans.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Facts:
- bash 3.2; `set -uo pipefail`, no `set -e`.
- `templates/plans/gate.sh` is the skeleton `sync-plans.sh` seeds into a consuming
  repo's `plans/gate.sh` once; `self/gate.sh` is agentTooling's own, hand-maintained copy.
  Both are structured identically: header comment → `REPO_DIR`/`REPORT` → toolchain
  block → report header → `any_failed`/`check_count` → `_record`/`record`/`record_info`
  → checks → verdict. Apply the same three edits to both.
- The consuming repo's `plans/gate.sh` is never overwritten; this plan changes the
  template only, and `README.md` (plan 66) tells repos to hand-merge.

## Files

- `templates/plans/gate.sh` (modify)
- `self/gate.sh` (modify)
- `templates/README.md` (modify)

## Both gate scripts — three edits

1. **Level label.** Directly after the `OUTPUT_TAIL_LINES=40` line:

```bash
# Optional level label, passed by the runner when this gate runs at a level sentinel
# (NN-gate.md) instead of at the end of the batch. The report is always written to
# $REPORT; with a label it is also copied to gate-report.<label>.txt so the per-level
# results survive the final run overwriting $REPORT.
LEVEL_LABEL="${1:-}"
```

   In the report header block (the one writing `# Gate report` and `generated:`), add a
   line `echo "level: ${LEVEL_LABEL:-final}"`. At the very end, after the `# VERDICT`
   block is appended and before the closing `echo "=== gate: done …"` lines:

```bash
if [[ -n "$LEVEL_LABEL" ]]; then
  cp "$REPORT" "${REPORT%.txt}.$LEVEL_LABEL.txt"
fi
```

2. **`record_skip`.** Next to `any_failed=0` / `check_count=0` add `skip_count=0`. After
   `record_info() { … }` add:

```bash
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
```

   In the verdict chain, insert **after** the `any_failed` branch and before the final
   `else`:

```bash
elif (( skip_count > 0 )); then
  overall_note="checks that ran passed, but $skip_count SKIPPED — NOT a green build; a skipped suite is absent information, not a pass"
```

   Leave `self/gate.sh`'s shellcheck branch as the bare `echo "  skip …"` it is: that
   check is informational by design and must not make a machine without shellcheck
   report a non-green verdict.

3. **Header principle.** In the header comment, after the contract bullets, add:

```
#   - A gate provisions what it needs or fails loudly. A silently skipped check is
#     worse than a failing one: a failure is triaged, an absence is inferred as a
#     pass. Prefer starting your own database or container over skipping when the
#     environment is not already warm — e.g. `docker compose up -d --no-build <svc>`
#     (so a missing image fails in seconds, not after a multi-minute build), poll for
#     readiness, and leave it running for the verify pass. Use record_skip, never a
#     bare echo, for anything that genuinely cannot run.
```

   In `templates/plans/gate.sh` only, extend the commented example block in the
   REPO-SPECIFIC checks section with two lines showing `record_skip "tests" "postgres
   unreachable — see gate header"` as the fallback branch of an `if`.

## `templates/README.md`

The file's tree lists `plans/PROJECT_FACTS.md` as repo-owned but omits `gate.sh` and
`pr.sh`; add both as `repo-owned — seeded once, never overwritten` lines, and a sentence
after the tree: the gate skeleton takes an optional level label (`gate.sh NN`) and writes
`gate-report.NN.txt` beside `gate-report.txt`; repos that seeded their gate before this
existed merge that change by hand — see `../README.md` → "Updating".
