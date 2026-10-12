# 65 — Level sentinels in the build runner, `--up-to` in the verify runner

Feature `test-first-levels`, plan 1 of 6. The feature reorders a batch into **levels** —
tests first, then per-layer build plans — with the free mechanical gate run at every level
boundary via a sentinel plan file `NN-gate.md`, so a cross-layer seam fails at the
boundary it crosses instead of at review one batch later.

Summary: teach `plan-runner-lib.sh` to treat `NN-gate.md` as a sentinel that runs the gate
in-process (and yields with exit 4 when a level-verify plan is queued), bound `list_plans`
by an optional `PLAN_MAX_NN`, and give `run-verify.sh` the `--up-to NN` flag that sets it.

Independent of other plans (66 and 67 build on the exit code and label this plan defines,
but edit different files).

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Facts:
- bash 3.2 is the target. No associative arrays; `${a[@]+"${a[@]}"}` for possibly-empty
  arrays under `set -u`. Use `if …; then …; fi`, not `cond && cmd`, when the status is
  not being checked (`set -uo pipefail` and deliberately no `set -e`).
- `run_all` sets `shopt -s nullglob` before anything globs, so `[0-9]*.md` on an empty
  directory expands to nothing.
- `$GATE_SCRIPT`, `$REPO_DIR`, `$FEATURES_DIR`, `$SELF_ARG` are set by
  `plan-runner-roots.sh` before `plan-runner-lib.sh` is sourced. `$QUEUE` is `auto`,
  `verify` or `review`, set by the wrapper.
- `exit_reason` is a global printed by `print_status`, which runs on the EXIT trap, so
  setting it then calling `exit N` reports the reason.
- Exit codes already in use by the runners: 0 clean, 2 no such feature / ambiguous
  feature, 3 budget exhausted (plan routed to failed/), 127 missing `claude`/`jq`, 130
  interrupted. **4 is new: "paused at a level boundary".**

## Files

- `plan-runner-lib.sh` (modify)
- `run-verify.sh` (modify)
- `run-plans.sh` (modify — header comment only)
- `RUNNER.md` (modify)

## `plan-runner-lib.sh`

1. Replace `list_plans` (currently `plan-runner-lib.sh:77-83`) with a version that honours
   an optional upper bound on the plan number:

```bash
# List plan files (excluding .progress.md logs) in a directory, sorted. When PLAN_MAX_NN
# is set (run-verify.sh --up-to NN), plans whose leading number is greater than it are
# omitted — that is how a level-verify plan is drained at its level boundary while the
# final verify, numbered above every sentinel, waits for the end of the batch.
list_plans() {
  local dir="$1" f base
  for f in "$dir"/[0-9]*.md; do
    [[ "$f" == *.progress.md ]] && continue
    if [[ -n "${PLAN_MAX_NN:-}" ]]; then
      base="$(basename "$f")"
      [[ "${base%%-*}" -le "$PLAN_MAX_NN" ]] || continue
    fi
    echo "$f"
  done
}
```

   Keep `[[ -le ]]` — it compares `05` and `5` numerically without the octal trap that
   `$(( 08 ))` has. `resolve_feature` also calls `list_plans`, so with a bound set a
   feature whose only queued verify plan is above the bound reads as "nothing queued" and
   the run is a clean no-op; that is the intended result.

2. Directly after `list_plans`, add:

```bash
# A sentinel plan `NN-gate.md` marks a level boundary (AGENT_PLANS.md, "Levels"). It is
# never sent to claude: the build runner runs the mechanical gate in its place, labelled
# with NN, then files it to complete/ with no progress log, stream or usage sidecar.
is_gate_sentinel() {
  [[ "$(basename "$1")" =~ ^[0-9]+-gate\.md$ ]]
}

# Is a verify plan numbered <= the given sentinel number queued for this feature? The
# build runner yields to run-batch.sh at a boundary only when there is a level-verify
# plan to run there; otherwise it continues into the next level without stopping.
level_verify_queued() {
  local nn="$1" f base
  for f in "$FEATURES_DIR/$FEATURE_SLUG/verify/incomplete"/[0-9]*.md; do
    [[ "$f" == *.progress.md ]] && continue
    base="$(basename "$f")"
    if [[ "${base%%-*}" -le "$nn" ]]; then return 0; fi
  done
  return 1
}

# Run the repo's gate at a level boundary, passing the sentinel's number as the label
# (gate.sh copies its report to gate-report.<label>.txt). Same contract as the final
# gate in run-batch.sh: advisory on red, fatal only on an unusable environment.
run_level_gate() {
  local label="$1" rc
  if [[ ! -x "$GATE_SCRIPT" ]]; then
    echo "=== level $label: no gate script at ${GATE_SCRIPT#$REPO_DIR/}, skipping ==="
    return 0
  fi
  echo "=== level $label: mechanical gate (${GATE_SCRIPT#$REPO_DIR/}) ==="
  "$GATE_SCRIPT" "$label"
  rc=$?
  if (( rc != 0 )); then
    exit_reason="stopped: gate reports an unusable environment (exit $rc) at level $label"
    exit "$rc"
  fi
}
```

3. In `run_all`'s Phase 2 loop (`plan-runner-lib.sh:591-608`), after `current_plan` is
   assigned and **before** `local inprogress_plan=…` / the `mv`, insert:

```bash
    if is_gate_sentinel "$plan_file"; then
      local level_nn="${current_plan%%-*}"
      run_level_gate "$level_nn"
      mv "$plan_file" "$COMPLETE_DIR/$current_plan"
      if [[ "$QUEUE" == "auto" ]] && level_verify_queued "$level_nn"; then
        exit_reason="paused at level boundary $current_plan — a level-verify plan is queued; run: run-verify.sh $SELF_ARG--up-to $level_nn $FEATURE_SLUG, then re-run run-plans.sh $SELF_ARG$FEATURE_SLUG to continue"
        exit 4
      fi
      continue
    fi
```

   The sentinel bypasses `run_plan` and `finalize_plan` entirely, so it produces no
   `.progress.md`, `.stream.jsonl` or `.usage.json` — which is what keeps it invisible to
   `analysis/` (those scripts index plans by their sidecars). Phase 1 needs no change: a
   sentinel is moved atomically and is never in `inprogress/`.

## `run-verify.sh`

After `if (( SELF_MODE )); then shift; fi` and before `QUEUE="verify"`, add:

```bash
# --up-to NN: drain only verify plans numbered <= NN. run-batch.sh passes the sentinel's
# number here after a level boundary so the level-verify plan runs before the next level
# builds on a red tree; the final verify, numbered above every sentinel, is left queued.
PLAN_MAX_NN=""
if [[ "${1:-}" == "--up-to" ]]; then
  PLAN_MAX_NN="${2:?--up-to needs a plan number}"
  shift 2
fi
```

In the header comment, add one sentence naming the flag and that it follows `--self`
(`run-verify.sh --self --up-to 05 <slug>`). In `build_prompt` step 3, after "re-run only
the specific check that failed.", append the sentence: `If it lists a check as SKIPPED,
treat that as absent information, not as a pass: either run that check yourself or state
in your summary exactly what is consequently unverified.`

## `run-plans.sh`

Header comment only: add a paragraph stating that a plan file named `NN-gate.md` is a
level sentinel — the runner runs `plans/gate.sh NN` in its place and continues; if a
verify plan numbered ≤ NN is queued it exits **4** so `run-batch.sh` (or a human) can run
`run-verify.sh --up-to NN` first, and re-running `run-plans.sh` resumes from the next
build plan. Point at `RUNNER.md` → "Level sentinels".

## `RUNNER.md`

- Under "Layout and state", after the `failed/` bullet, add a paragraph "**Level
  sentinels.**" — `NN-gate.md` moves `incomplete/ → complete/` directly with no sidecars;
  the runner runs the gate with `NN` as its label instead of calling `claude`; cost
  tooling never sees it because it has no `.usage.json`.
- Under "Choosing a feature", after the paragraph on exit codes/gating (ends "…reviewing a
  state nobody intends to keep"), add: exit code **4** from `run-plans.sh` means paused at
  a level boundary with a level-verify queued; `run-batch.sh` handles it by running
  `run-verify.sh --up-to NN` and re-invoking the build pass (plan 66 adds that loop);
  by hand, run the same two commands.
- Add `run-verify.sh --up-to NN` to the description of the verify pass (around
  `RUNNER.md:35-65`): one bullet, what it bounds and why `resolve_feature` treats an
  out-of-bound queue as empty.
- In the mode table at `RUNNER.md:228`, the `gate` row: append "plus `gate-report.<NN>.txt`
  per level sentinel" to both cells.
