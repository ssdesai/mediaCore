#!/usr/bin/env bash
set -uo pipefail

# The weekly cost sweep: sweep.sh [--self]
#
# Runs, in order, the cadence analysis/README.md -> "How to run them" otherwise walks
# by hand: rates, backfill, recover, capture, report, unclaimed, done. The order is a
# real dependency chain, not a suggestion -- report.py reads the planning.json and
# usage.json files the two capture steps (backfill_usage.py and recover_attempts.py,
# then capture_planning.py) write, and reports nothing where they are missing rather
# than failing loudly. Rates comes first because every dollar figure below it depends
# on the table being current; unclaimed comes last because it is a discovery step over
# the whole corpus -- the delegates and sessions of the last week nobody has pinned yet
# -- not itself a source of cost records.
#
# A refusal at any step is reported and does not stop the sweep: this is the recurring
# job over the whole corpus (analysis/README.md -> "Why the cadence matters"), not one
# feature's close, and one expired transcript or one feature's unmatched branch must
# not cost every other feature its number. Every step still runs, and the done banner
# always prints what changed under the features tree.
#
# Exit codes: 2 usage; 1 when backfill, recover, capture or report exited non-zero at
# any point during the run (the rates check and the unclaimed listings never fail the
# sweep); else 0.

USAGE_RC=2
FAILED_RC=1
SWEEP_LOOKBACK_DAYS=7
COST_FILE_NAMES="planning.json usage.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
SELF_FLAG=()
if [[ "${1:-}" == "--self" ]]; then SELF_FLAG=(--self); shift; fi

usage() {
  echo "usage: sweep.sh [--self]" >&2
  exit "$USAGE_RC"
}
(( $# == 0 )) || usage

sweep_failed=0

# run_step <label> <cmd…> — runs a command, printing nothing of its own (the command's
# own stdout/stderr is the sweep's output for that step); a non-zero status sets
# sweep_failed without stopping the steps after it.
run_step() {
  local label="$1"; shift
  if ! "$@"; then
    sweep_failed=1
  fi
}

# ── rates ─────────────────────────────────────────────────────────────────────
echo "=== sweep: rates ==="
RATES_OUT="$(python3 -B -c "import sys; sys.path.insert(0, '$SCRIPT_DIR/analysis'); import pricing; print(pricing.RATES_VERIFIED, pricing.is_rates_stale())" 2>&1)"
RATES_VERIFIED_VAL="${RATES_OUT%% *}"
RATES_STALE_VAL="${RATES_OUT##* }"
echo "  rates  verified $RATES_VERIFIED_VAL"
if [[ "$RATES_STALE_VAL" == "True" ]]; then
  echo "  WARN   rate table is stale; update RATES and RATES_VERIFIED in analysis/pricing.py"
fi

# ── backfill ──────────────────────────────────────────────────────────────────
echo ""
echo "=== sweep: backfill ==="
run_step backfill python3 -B "$SCRIPT_DIR/analysis/backfill_usage.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"}

# ── recover ───────────────────────────────────────────────────────────────────
echo ""
echo "=== sweep: recover ==="
run_step recover python3 -B "$SCRIPT_DIR/analysis/recover_attempts.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"}

# ── capture ───────────────────────────────────────────────────────────────────
echo ""
echo "=== sweep: capture ==="
run_step capture python3 -B "$SCRIPT_DIR/analysis/capture_planning.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} --all

# ── report ────────────────────────────────────────────────────────────────────
# Slugs derived from git status --porcelain, resolved against the repository TOPLEVEL
# rather than REPO_DIR -- under --self inside a vendored copy, REPO_DIR is a
# subdirectory of TOPLEVEL, and porcelain paths are always relative to the latter.
echo ""
echo "=== sweep: report ==="
TOPLEVEL="$(git -C "$REPO_DIR" rev-parse --show-toplevel)"
STATUS_OUT="$(git -C "$REPO_DIR" status --porcelain -- "$FEATURES_DIR")"
REPORT_SLUGS_RAW=""
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  path="${line:3}"
  case "$path" in
    *" -> "*) path="${path##*" -> "}" ;;
  esac
  abs="$TOPLEVEL/$path"
  case "$abs" in
    "$FEATURES_DIR"/*) ;;
    *) continue ;;
  esac
  name="$(basename "$abs")"
  case " $COST_FILE_NAMES " in
    *" $name "*) ;;
    *) continue ;;
  esac
  rest="${abs#"$FEATURES_DIR"/}"
  REPORT_SLUGS_RAW="$REPORT_SLUGS_RAW${rest%%/*}"$'\n'
done <<<"$STATUS_OUT"

REPORT_SLUGS=()
while IFS= read -r s; do
  [[ -n "$s" ]] || continue
  REPORT_SLUGS+=("$s")
done < <(printf '%s' "$REPORT_SLUGS_RAW" | sort -u)

for slug in ${REPORT_SLUGS[@]+"${REPORT_SLUGS[@]}"}; do
  run_step "report:$slug" python3 -B "$SCRIPT_DIR/analysis/report.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$slug"
done
run_step "report:--all" python3 -B "$SCRIPT_DIR/analysis/report.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} --all

# ── unclaimed ─────────────────────────────────────────────────────────────────
echo ""
echo "=== sweep: unclaimed ==="
LOOKBACK_DATE="$(python3 -B -c 'import datetime as d, sys; print((d.datetime.now(d.timezone.utc) - d.timedelta(days=int(sys.argv[1]))).strftime("%Y-%m-%d"))' "$SWEEP_LOOKBACK_DAYS")"
python3 -B "$SCRIPT_DIR/analysis/capture_planning.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} --list-subagents --unclaimed --since "$LOOKBACK_DATE"
python3 -B "$SCRIPT_DIR/analysis/capture_planning.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} --list-sessions --unclaimed --since "$LOOKBACK_DATE"

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
echo "=== sweep: done ==="
FINAL_STATUS="$(git -C "$REPO_DIR" status --porcelain -- "$FEATURES_DIR")"
CHANGED_COUNT=0
if [[ -n "$FINAL_STATUS" ]]; then
  CHANGED_COUNT="$(printf '%s\n' "$FINAL_STATUS" | wc -l | tr -d ' ')"
fi
if (( CHANGED_COUNT > 0 )); then
  echo "  changed  $CHANGED_COUNT file(s) under $FEATURES_LABEL — commit them"
else
  echo "  changed  nothing"
fi
echo "  next     propagate: ./agentTooling/update.sh in each consuming repo"

if (( sweep_failed )); then
  exit "$FAILED_RC"
fi
exit 0
