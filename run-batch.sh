#!/usr/bin/env bash
set -uo pipefail

# BATCH runner: fire-and-forget wrapper that runs the full delegated-plan cycle in
# order — the build pass (run-plans.sh, Bash disabled), then the verify pass
# (run-verify.sh, Bash enabled), then the review pass (run-review.sh) — so a batch
# of build plans plus its verify and review plans can be executed with a single
# command. Each stage IS the real runner; this script only sequences them and gates
# each pass on the one before it. A corpus lint (check-plans.sh) runs first, at no
# model cost, and stops the batch before the build pass on any FAIL.
#
# The build pass may pause at a level boundary rather than finish or fail outright,
# signaled by exit code 64 (LEVEL_PAUSE_RC, plan-runner-roots.sh): run-plans.sh exits
# that way when it has just run a level's gate sentinel (NN-gate.md), the gate is red,
# and a verify plan numbered ≤ NN is queued. This script then climbs the tier ladder for
# that level (settle_level below; RUNNER.md → "Red gates: the tier ladder"):
#
#   tier 1  the authored level-verify (run-verify.sh --up-to NN, sonnet) — fixes the tree
#           to the contract, may not change a contract;
#   re-gate the gate runs again at no model cost; green means build on;
#   tier 2  a synthesized escalation plan (opus) that may change a contract and must
#           patch the queued plans above it to match; re-gate again;
#   tier 3  still red: the batch stops, exit non-zero, escalations/NN.md says why.
#
# The full sequence is therefore build → [gate NN → tiers → build …] → gate → verify →
# review, with the bracketed part repeating once per level boundary crossed. A batch
# re-run after an interruption checks for an unsettled level first, so a level-verify
# left in inprogress/ (usage limit) or failed/ (budget) is settled before the next
# level builds on it — the first pilot's resume built level 3 on a half-fixed level 2.
#
# The verify pass is skipped unless the build pass completes cleanly. run-plans.sh
# exits non-zero the moment a plan fails, a usage limit is hit, or it is
# interrupted, and exits 0 only when every build plan finished — so a non-zero
# build code means there is no point verifying (the code under test was never
# finished being written). In that case this script forwards the build pass's exit
# code and stops.
#
# The review pass is gated on verify the same way, for a different reason. Verify
# is permitted to edit, so a verify pass that stopped early (a failed plan, a
# budget cap) leaves a tree that is half-fixed rather than unfinished. Reviewing
# that tree produces findings about a state nobody intends to keep. A skipped
# review is not lost work — run-review.sh takes the same slug and can be run on its
# own once verify is settled, which is what the skip message says.
#
# Each pass is optional in the sense that an empty queue is a no-op: a feature with
# no review plans queued makes the review pass print "nothing to do" and exit 0, so
# adding this stage does not disturb a feature authored before it existed.
#
# Between the two passes, an optional repo-provided gate script (plans/gate.sh) runs
# the deterministic checks — install, lint, tests, typecheck, build — and leaves its
# results in plans/gate-report.txt for the verify plan to read. That work needs no
# model, and doing it here means the verify executor reads a result instead of
# spending its (expensive, high-model) turns generating one. The gate is advisory:
# a red tree is frequently what the verify pass exists to fix, so only an unusable
# environment (non-zero gate exit) skips verification.
#
# The optional feature slug (first arg) is forwarded to both passes, and is otherwise
# inferred once by the build pass and reused by the verify pass. The optional first
# argument may instead be --self, which selects agentTooling's own queue and its own
# gate — see plan-runner-roots.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
if (( SELF_MODE )); then shift; fi

# Forwarded verbatim to both passes so they can never resolve to different roots — the
# same failure the FEATURE_SLUG_OUT handshake below prevents for the feature slug.
# ${a[@]+"${a[@]}"}: expanding an empty array the naive way aborts under `set -u` on
# bash 3.2, still the system bash on macOS.
SELF_FLAG=()
if (( SELF_MODE )); then SELF_FLAG=(--self); fi

# When no slug is given, each pass would infer independently, and they read different
# queues: the build pass looks at auto/incomplete, the verify pass at verify/incomplete,
# the review pass at review/incomplete. A feature with a leftover queued verify or review
# plan would then capture that pass and get a run — and a usage record — belonging to the
# feature just built. Capture what the build pass resolved and pass it to both.
FEATURE_SLUG_FILE="$(mktemp)"
# The second handshake, shaped exactly like the first. run-plans.sh KNOWS which sentinel
# paused it — it had the file in its hand one process ago — while this script could only
# re-derive the number by sorting auto/complete/, which is right only as long as the
# highest-numbered filed sentinel is the one that paused. Reading it back is the same
# fix as FEATURE_SLUG_OUT above: let the process that knows say so.
LEVEL_PAUSE_NN_FILE="$(mktemp)"
# The batch's own timing stamps (stamp_timing, plan-runner-roots.sh) need the slug; an
# explicit one is known now, an inferred one only after the build pass — FEATURE_SLUG is
# re-resolved there. The closing stamp rides the EXIT trap so every exit path leaves it.
FEATURE_SLUG="${1:-}"
trap 'batch_rc=$?; stamp_timing batch_end rc="$batch_rc"; rm -f "$FEATURE_SLUG_FILE" "$LEVEL_PAUSE_NN_FILE"' EXIT
export FEATURE_SLUG_OUT="$FEATURE_SLUG_FILE"
export LEVEL_PAUSE_NN_OUT="$LEVEL_PAUSE_NN_FILE"
stamp_timing batch_start

# The lint runs before anything is spent. A malformed corpus — a plan without a model
# suffix, a stem missing from plans[], a review stub still carrying its marker — is
# otherwise found by a runner mid-batch or by a cost report that omits a plan.
if [[ -n "$FEATURE_SLUG" && -x "$SCRIPT_DIR/check-plans.sh" ]]; then
  echo "########## BATCH: check-plans ##########"
  if ! "$SCRIPT_DIR/check-plans.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$FEATURE_SLUG"; then
    echo "########## BATCH: check-plans failed — nothing run; fix the corpus and re-run ##########"
    exit 1
  fi
fi

# Did level NN's gate report a fully green tree? Same rule as level_gate_green in
# plan-runner-lib.sh (this script does not source the lib): the line under "# VERDICT"
# in gate-report.NN.txt is exactly "all checks passed".
gate_green() {
  local report="$REPO_DIR/$GATE_REPORT_LABEL"
  local labelled="${report%.txt}.$1.txt"
  [[ -f "$labelled" ]] && report="$labelled"
  [[ -f "$report" ]] || return 1
  [[ "$(awk '/^# VERDICT/{getline; print; exit}' "$report")" == "all checks passed" ]]
}

# Is a level plan (NN-level-* or NN-escalation-*) for level NN sitting in inprogress/?
# That is a usage-limit or interrupt stop, not an outcome — resume it, never climb past it.
level_plan_inprogress() {
  ls "$FEATURES_DIR/$1/verify/inprogress/$2"-{level,escalation}-*.md 2>/dev/null | grep -q .
}

# Any verify plan numbered <= NN still queued (incomplete/ or inprogress/)?
level_verify_pending() {
  local f base
  for f in "$FEATURES_DIR/$1/verify/incomplete"/[0-9]*.md "$FEATURES_DIR/$1/verify/inprogress"/[0-9]*.md; do
    [[ -e "$f" && "$f" != *.progress.md ]] || continue
    base="$(basename "$f")"
    (( 10#${base%%-*} <= 10#$2 )) && return 0
  done
  return 1
}

# Re-run the gate for level NN at no model cost, so the ladder decides on a fresh
# verdict rather than on the report the pause was taken from.
regate() {
  [[ -x "$GATE_SCRIPT" ]] || return 0
  echo "########## BATCH: level $2 — re-running the gate (${GATE_SCRIPT#$REPO_DIR/} $2) ##########"
  level_expectations "$FEATURES_DIR/$1/auto/complete/$2-gate.md"
  stamp_timing gate_start level="$2" regate=true
  "$GATE_SCRIPT" "$2"
  local rc=$?
  unset GATE_EXPECTED_RED GATE_DEFERRED
  local green=false
  gate_green "$2" && green=true
  stamp_timing gate_end level="$2" rc="$rc" green="$green" regate=true
  return "$rc"
}

# settle_level <slug> <NN>: climb the tier ladder until level NN's gate is green or
# nothing more can be done unattended. Returns 0 on green, non-zero otherwise.
settle_level() {
  local slug="$1" nn="$2" rc

  if level_verify_pending "$slug" "$nn"; then
    echo ""
    echo "########## BATCH: level $nn — tier 1, the level-verify (run-verify.sh --up-to $nn) ##########"
    "$SCRIPT_DIR/run-verify.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} --up-to "$nn" "$slug"
    rc=$?
    if level_plan_inprogress "$slug" "$nn"; then
      echo "########## BATCH: level $nn — level pass left in inprogress (exit $rc); re-run the batch to resume it ##########"
      return "$rc"
    fi
  fi

  regate "$slug" "$nn"
  if gate_green "$nn"; then
    echo "########## BATCH: level $nn — green after tier 1; building the next level ##########"
    return 0
  fi

  echo ""
  if ! "$SCRIPT_DIR/run-escalation-plan.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$slug" "$nn"; then
    echo "########## BATCH: level $nn — escalation already ran for this level; not buying it twice ##########"
    echo "########## BATCH: level $nn — still red; see $FEATURES_LABEL/$slug/escalations/$nn.md ##########"
    return 1
  fi
  echo "########## BATCH: level $nn — tier 2, escalation (run-verify.sh --up-to $nn, opus) ##########"
  "$SCRIPT_DIR/run-verify.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} --up-to "$nn" "$slug"
  rc=$?
  if level_plan_inprogress "$slug" "$nn"; then
    echo "########## BATCH: level $nn — escalation left in inprogress (exit $rc); re-run the batch to resume it ##########"
    return "$rc"
  fi

  regate "$slug" "$nn"
  if gate_green "$nn"; then
    echo "########## BATCH: level $nn — green after tier 2; building the next level ##########"
    return 0
  fi
  echo "########## BATCH: level $nn — tier 3: still red after escalation; stopping. See $FEATURES_LABEL/$slug/escalations/$nn.md ##########"
  return 1
}

# The slug, resolved once so the resume check below and every pass agree on it.
resolve_batch_slug() {
  local slug="${1:-}"
  if [[ -z "$slug" && -s "$FEATURE_SLUG_FILE" ]]; then slug="$(cat "$FEATURE_SLUG_FILE")"; fi
  echo "$slug"
}

# Highest-numbered sentinel already filed to auto/complete/ — the level most recently
# crossed, and the one a resumed batch has to check before building further.
last_sentinel_nn() {
  ls "$FEATURES_DIR/$1/auto/complete/" 2>/dev/null | grep -E '^[0-9]+-gate\.md$' | sort | tail -1 | cut -d- -f1
}

# --- Resume check: settle an unsettled level before the build pass runs again. ---
# Only when the slug is explicit; an inferred slug is not known until the build pass has
# run once, and a fresh batch has no crossed level to settle anyway.
#
# The condition is about the LEVEL, not about the queue behind it: an unsettled level owes
# its tier ladder whether or not there are build plans left to run on top of it. A batch
# killed during its last level's level-verify has every build plan complete, and gating the
# settle on a non-empty auto/incomplete/ let such a resume walk straight past the ladder —
# the ordinary verify pass then ran the queued level-verify with no tier behind it, a red
# gate there escalated nothing, and the batch reported the failure only at the final gate.
# The cost of the wider condition is bounded: a finished batch re-run with its gate reports
# intact is already settled and settles nothing, and one re-run on a fresh clone (the
# reports are gitignored) re-runs that level's mechanical gate once, at no model cost.
if [[ -n "${1:-}" ]]; then
  resume_nn="$(last_sentinel_nn "$1")"
  if [[ -n "$resume_nn" ]] && ( level_verify_pending "$1" "$resume_nn" || ! gate_green "$resume_nn" ); then
    echo "########## BATCH: resuming — level $resume_nn was crossed but is not settled; settling it before building on ##########"
    settle_level "$1" "$resume_nn" || exit 1
  fi
fi

while :; do
  echo "########## BATCH 1/3: build pass (run-plans.sh) ##########"
  # Truncated per iteration so a second pause can never be settled against the first
  # pause's number, and so "the runner reported nothing" is a state this loop can see.
  : > "$LEVEL_PAUSE_NN_FILE"
  "$SCRIPT_DIR/run-plans.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$@"
  build_rc=$?
  if (( build_rc == LEVEL_PAUSE_RC )); then
    # Paused at a level boundary with a level-verify plan queued and the gate red. The
    # runner named the sentinel through LEVEL_PAUSE_NN_OUT; the sort over auto/complete/
    # is the fallback for a runner that predates the handshake.
    level_slug="$(resolve_batch_slug "${1:-}")"
    level_nn=""
    if [[ -s "$LEVEL_PAUSE_NN_FILE" ]]; then level_nn="$(cat "$LEVEL_PAUSE_NN_FILE")"; fi
    if [[ -z "$level_nn" ]]; then level_nn="$(last_sentinel_nn "$level_slug")"; fi
    if [[ -z "$level_nn" ]]; then
      # Neither source knows which level paused. Settling an empty level would run
      # `run-verify.sh --up-to ""`, which drains no plan and re-gates an unlabelled
      # level — a silent no-op the batch would then read as progress. Stop instead.
      echo ""
      echo "########## BATCH: paused at a level boundary but no level number was reported and none is filed in auto/complete/ — cannot settle an unknown level ##########"
      exit 1
    fi
    if ! settle_level "$level_slug" "$level_nn"; then
      echo ""
      echo "########## BATCH: level $level_nn could not be settled unattended — not building the next level on it ##########"
      exit 1
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
unset FEATURE_SLUG_OUT
FEATURE_SLUG="$(resolve_batch_slug "${1:-}")"

if [[ -x "$GATE_SCRIPT" ]]; then
  echo ""
  echo "########## BATCH: mechanical gate (${GATE_SCRIPT#$REPO_DIR/}) ##########"
  stamp_timing gate_start level=final
  "$GATE_SCRIPT"
  gate_rc=$?
  final_green=false
  gate_green final && final_green=true
  stamp_timing gate_end level=final rc="$gate_rc" green="$final_green"
  if (( gate_rc != 0 )); then
    echo ""
    echo "########## BATCH: gate reports an unusable environment (exit $gate_rc) — skipping verify ##########"
    exit "$gate_rc"
  fi
fi

echo ""
echo "########## BATCH 2/3: verify pass (run-verify.sh) ##########"
batch_feature="${1:-}"
if [[ -z "$batch_feature" && -s "$FEATURE_SLUG_FILE" ]]; then
  batch_feature="$(cat "$FEATURE_SLUG_FILE")"
  echo "########## BATCH: verifying '$batch_feature' (inferred by the build pass) ##########"
fi
"$SCRIPT_DIR/run-verify.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$batch_feature"
verify_rc=$?

if (( verify_rc != 0 )); then
  echo ""
  echo "########## BATCH: verify pass stopped (exit $verify_rc) — skipping review ##########"
  echo "########## BATCH: settle verify, then: run-review.sh $SELF_ARG$batch_feature ##########"
  exit "$verify_rc"
fi

echo ""
echo "########## BATCH 3/3: review pass (run-review.sh) ##########"
"$SCRIPT_DIR/run-review.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$batch_feature"
review_rc=$?

echo ""
if (( review_rc != 0 )); then
  echo "########## BATCH: review pass stopped (exit $review_rc) ##########"
else
  echo "########## BATCH: complete — build + verify + review all finished ##########"
fi
exit "$review_rc"
