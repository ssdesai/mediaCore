# 66 — The level loop in `run-batch.sh`

Feature `test-first-levels`, plan 2 of 6. The feature reorders a batch into **levels** —
tests first, then per-layer build plans — with the free mechanical gate run at every level
boundary via a sentinel plan file `NN-gate.md`, so a cross-layer seam fails at the
boundary it crosses instead of at review one batch later.

Summary: make `run-batch.sh` re-invoke the build pass after each level boundary, running
`run-verify.sh --up-to NN` in between, and document the new rows in `README.md`.

Depends on: 65-runner-sentinels-sonnet.md (defines exit code 4 and `--up-to`).

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Facts:
- bash 3.2 is the target; `${a[@]+"${a[@]}"}` for possibly-empty arrays under `set -u`.
- `run-batch.sh` sources `plan-runner-roots.sh` and calls `resolve_roots`, so
  `$FEATURES_DIR`, `$GATE_SCRIPT`, `$REPO_DIR`, `$SELF_ARG` are set. `SELF_FLAG` is the
  array it already builds for forwarding `--self`.
- `FEATURE_SLUG_OUT` is exported before the build pass; `run_all` writes the resolved slug
  into that file on every invocation that resolves a feature, and leaves it untouched when
  nothing is queued ("Nothing to do", exit 0).
- `run-plans.sh` exits **4** when it has just run a sentinel `NN-gate.md` and a verify
  plan numbered ≤ NN is queued. The sentinel is then already in `auto/complete/`.
- `run-verify.sh` takes `--up-to NN` **after** `--self` and before the slug:
  `run-verify.sh --self --up-to 05 <slug>`.

## Files

- `run-batch.sh` (modify)
- `README.md` (modify)

## `run-batch.sh`

Replace the single build-pass block (`run-batch.sh:67-75`: the `BATCH 1/3` echo through
the `if (( build_rc != 0 ))` stop) with a loop. Keep the existing behaviour for every
non-4 exit code:

```bash
while :; do
  echo "########## BATCH 1/3: build pass (run-plans.sh) ##########"
  "$SCRIPT_DIR/run-plans.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$@"
  build_rc=$?
  if (( build_rc == 4 )); then
    # Paused at a level boundary with a level-verify plan queued. The sentinel that
    # paused us is the highest-numbered NN-gate.md now in auto/complete/.
    level_slug="${1:-}"
    if [[ -z "$level_slug" && -s "$FEATURE_SLUG_FILE" ]]; then level_slug="$(cat "$FEATURE_SLUG_FILE")"; fi
    level_nn="$(ls "$FEATURES_DIR/$level_slug/auto/complete/" 2>/dev/null \
      | grep -E '^[0-9]+-gate\.md$' | sort | tail -1 | cut -d- -f1)"
    echo ""
    echo "########## BATCH: level $level_nn — running the queued level-verify (run-verify.sh --up-to $level_nn) ##########"
    "$SCRIPT_DIR/run-verify.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} --up-to "$level_nn" "$level_slug"
    lv_rc=$?
    if (( lv_rc != 0 )); then
      echo ""
      echo "########## BATCH: level-verify stopped (exit $lv_rc) — not building the next level on it ##########"
      exit "$lv_rc"
    fi
    continue
  fi
  break
done

if (( build_rc != 0 )); then
  echo ""
  echo "########## BATCH: build pass stopped (exit $build_rc) — skipping verify ##########"
  exit "$build_rc"
fi
```

Then move the existing `unset FEATURE_SLUG_OUT` (currently just before the verify pass)
to **after** this loop — it must stay exported across loop iterations — keeping it before
the final verify pass as it is now. The final gate, final verify and review below are
unchanged; the final gate runs with no label, so `gate-report.txt` at verify time is the
whole-tree result.

Update the header comment: one paragraph saying the build pass may pause at a level
boundary (exit 4) and that this script runs the level-verify and resumes it, with the
sequence `build → [gate NN → level-verify ≤ NN → build …] → gate → verify → review`.

## `README.md`

In the contents table:
- `run-plans.sh` row: append a sentence — a plan named `NN-gate.md` is a level sentinel:
  the runner runs `plans/gate.sh NN` in its place and exits 4 instead of continuing when a
  verify plan numbered ≤ NN is queued.
- `run-verify.sh` row: append — `--up-to NN` (after `--self`) drains only verify plans
  numbered ≤ NN; how `run-batch.sh` runs a level-verify at a boundary.
- `run-batch.sh` row: replace "Sequences the three…" with a sentence that includes the
  level loop: build pass, then for each level boundary that paused it, the level-verify and
  a resumed build pass; then the final gate, verify and review.
- `plan-runner-lib.sh` row: append — also owns sentinel handling (`is_gate_sentinel`,
  `level_verify_queued`, `run_level_gate`) and the `PLAN_MAX_NN` bound on `list_plans`.

Under "Running", add the line
`./agentTooling/run-verify.sh --up-to 05 <slug>   # only the level-verify plans numbered ≤ 05`
and, under "Updating", a short numbered list titled "After pulling a version with level
sentinels": (1) `sync-plans.sh` as always; (2) hand-merge the gate edits from
`templates/plans/gate.sh` into the repo-owned `plans/gate.sh` — accept `$1` as a level
label, copy the report to `gate-report.<label>.txt`, add `record_skip` and the SKIPPED
verdict — since that file is never overwritten; (3) widen the repo's gitignore pattern
from `plans/gate-report.txt` to `plans/gate-report*.txt`; (4) author the next feature in
the shape `AGENT_PLANS.md` → "Levels" describes.
