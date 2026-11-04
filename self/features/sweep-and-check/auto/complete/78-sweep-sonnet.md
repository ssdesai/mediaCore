# 78 — sweep.sh

Feature: sweep-and-check — the weekly cost sweep, a pre-run lint of a feature's plan
corpus, drift detection for repo-owned files and the consumer update, each as a script
(manifest: `self/features/sweep-and-check/README.md`). Plan 6 of 8 build plans.

Write `sweep.sh`, the weekly cadence `analysis/README.md` → "How to run them" describes
as five commands in a fixed order, to the contract below. Plan 75's
`self/tests/sweep.sh` asserts it.

Depends on: nothing at build time. `sweep-and-check/75` is the test.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- bash 3.2: no associative arrays; `${a[@]+"${a[@]}"}` for a possibly-empty array;
  `set -uo pipefail`, no `set -e`; `if …; then` over `cond && cmd`.
- `plan-runner-roots.sh` (same directory): `resolve_roots "${1:-}"` sets `SELF_MODE`,
  `REPO_DIR`, `FEATURES_DIR`, `FEATURES_LABEL`. Mirror `feature-close.sh:60-66` for
  sourcing it and building `SELF_FLAG=()` / `SELF_FLAG=(--self)`, and
  `feature-close.sh:134-135` for invoking the analysis scripts as
  `python3 -B "$SCRIPT_DIR/analysis/<script>.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} …`.
- The analysis scripts take `--self` as their **first** argument. `capture_planning.py
  --all` exits non-zero when any feature was refused and still processes the rest;
  `--list-subagents --unclaimed --since YYYY-MM-DD` and
  `--list-sessions --unclaimed --since YYYY-MM-DD` print tables and exit 0.
- macOS `date` has no `-d`; compute the look-back date with
  `python3 -c 'import datetime as d, sys; print((d.datetime.now(d.timezone.utc) - d.timedelta(days=int(sys.argv[1]))).strftime("%Y-%m-%d"))' "$SWEEP_LOOKBACK_DAYS"`.
- Every magic value is a named constant at the top (`USAGE_RC=2`, `FAILED_RC=1`,
  `SWEEP_LOOKBACK_DAYS=7`, the cost file names `planning.json usage.json`).

## Files

- create `sweep.sh` (executable)
- modify `README.md` (one Contents row — see below)

## The contract (this block is repeated verbatim in plan 75)

```
sweep.sh [--self]                       anything else: usage on stderr, exit 2
AT = the directory holding sweep.sh; every python call is `python3 -B`, --self forwarded first.
Banners, in this order, each on its own line:
  === sweep: rates ===       python3 -B -c "import sys; sys.path.insert(0, '<AT>/analysis'); import pricing; print(pricing.RATES_VERIFIED, pricing.is_rates_stale())"
                             prints "  rates  verified <RATES_VERIFIED>"; when stale, also
                             "  WARN   rate table is stale; update RATES and RATES_VERIFIED in analysis/pricing.py"; never stops
  === sweep: backfill ===    <AT>/analysis/backfill_usage.py [--self]
  === sweep: recover ===     <AT>/analysis/recover_attempts.py [--self]
  === sweep: capture ===     <AT>/analysis/capture_planning.py [--self] --all
  === sweep: report ===      for each slug with a modified or untracked planning.json or usage.json under
                             $FEATURES_DIR (git -C "$REPO_DIR" status --porcelain -- "$FEATURES_DIR"):
                             <AT>/analysis/report.py [--self] <slug>; then report.py [--self] --all
  === sweep: unclaimed ===   capture_planning.py [--self] --list-subagents --unclaimed --since <D>
                             capture_planning.py [--self] --list-sessions --unclaimed --since <D>
                             D = today minus SWEEP_LOOKBACK_DAYS (7) as YYYY-MM-DD, computed with python3
  === sweep: done ===        "  changed  <N> file(s) under <FEATURES_LABEL> — commit them" or "  changed  nothing"
                             then "  next     propagate: ./agentTooling/update.sh in each consuming repo"
exit 1 when any of backfill, recover, capture or report exited non-zero — every step still
runs and the done banner still prints — else 0.
```

## `sweep.sh`

Header comment in the style of `feature-close.sh`'s: the cadence this replaces
(`analysis/README.md` → "How to run them"), why the order is a dependency chain
(`report.py` reads what the two captures write), that a refusal is reported and does
not stop the later steps, exit codes. Then the constants, `resolve_roots`, argument
parsing (`--self` only; anything else usage), then the seven banners in order. A
`run_step <label> <cmd…>` helper runs a command, prints nothing of its own, and sets
`sweep_failed=1` on a non-zero status. The report step derives its slugs by taking the
path column of `git status --porcelain` (columns start after the two status characters
and a space; a rename shows `old -> new` — take the part after `-> ` when present),
keeping only paths under `$FEATURES_DIR` whose basename is one of the cost file names,
and reading the slug as the path component directly under `$FEATURES_DIR`; `sort -u`
them. `git status --porcelain` paths are relative to the repository root — resolve
against `git -C "$REPO_DIR" rev-parse --show-toplevel`, not against `$REPO_DIR`, which
under `--self` inside a vendored copy is a subdirectory of the toplevel. The `changed`
count in the done banner is the number of lines that same `git status` prints for
`$FEATURES_DIR`.

## `README.md`

In the Contents table's "Costing" group, add a row for `sweep.sh`: "The weekly
cadence in order — rates, backfill, recover, capture `--all`, report — then the
unclaimed delegates and sessions of the last week and what changed under the features
tree; `--self` for this repo's own corpus." Match the neighbouring rows' form.
