#!/usr/bin/env bash
set -uo pipefail
# template-version: 3

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
#   - Sources self/environment.sh when present — the template's plans/environment.sh
#     hook (self/DESIGN-2026-10-05-cloud-execution.md §7). agentTooling ships none: its
#     checks need no service, so nothing differs by profile today.
#   - RESUMABLE at check granularity (design §8), exactly as the template: each check's
#     result goes to self/gate-state/<tree-sha>/<label> as it finishes, and under
#     GATE_RESUME=1 — which the runners and feature-start.sh set — a check whose PASS is
#     recorded for the same tree with the same command line is not run again, its
#     recorded section going into the report as it was. A failure always re-runs. The
#     tree sha is `git write-tree` with untracked files included, through a temporary
#     index, this gate's outputs and the features corpus (self/features/, which the runners
#     write between gate runs) left out; no sha (no git, a failed write-tree) runs
#     everything. The root .gitignore ignores self/gate-state/. This is the ~13-minute
#     gate a container restart killed (design §8's defect), so it is the one that most
#     needs it. ONE EXCEPTION, which the template has no use for: a check run with
#     `record_fresh` — the settings check — runs on every gate, resumed or not, and is
#     never recorded. It was made fresh when .claude/settings.json was ignored and the
#     tree sha could not see it (self/features/session-start-precision); the file is
#     tracked now (self/features/self-cloud-bootstrap), so the sha does see a drifted
#     working copy, but the check stays fresh: it is cheap, and the working copy a
#     session loads is exactly what it checks, so its verdict never rests on a recorded
#     pass (self-settings.sh G).

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT="$REPO_DIR/self/gate-report.txt"
OUTPUT_TAIL_LINES=40
# The profile facts (design §7), sourced when this checkout has them
ENVIRONMENT_FILE="$REPO_DIR/self/environment.sh"

# Resume (design §8): the same constants as templates/plans/gate.sh, under self/.
GATE_RESUME="${GATE_RESUME:-}"
GATE_RESUME_ON="1"
GATE_STATE_ROOT="$REPO_DIR/self/gate-state"
# The features corpus is the runners' record store, not a gate input (NOTES ruling 42)
GATE_FEATURES_DIR="self/features"
GATE_TREE_EXCLUDES=("self/gate-report*.txt" "self/gate-state" "$GATE_FEATURES_DIR")
GATE_STATE_RC_KEY="rc="
GATE_STATE_CMD_KEY="cmd="
GATE_STATE_HEADER_LINES=2
GATE_STATE_PASS_RC=0
GATE_STATE_LABEL_KEEP='A-Za-z0-9_-'
GATE_STATE_LABEL_FILL='_'
GATE_TREE_SHA_SHOWN=12
GATE_STATE_DIR=""
# _record's mode for a check never reused or recorded (record_fresh; header, ONE EXCEPTION)
RECORD_FRESH="fresh"

# Optional level label, passed by the runner when this gate runs at a level sentinel
# (NN-gate.md) instead of at the end of the batch. The report is always written to
# $REPORT; with a label it is also copied to gate-report.<label>.txt so the per-level
# results survive the final run overwriting $REPORT.
LEVEL_LABEL="${1:-}"

cd "$REPO_DIR" || exit 1

if [[ -f "$ENVIRONMENT_FILE" ]]; then
  . "$ENVIRONMENT_FILE"
fi

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

# ── Resume (design §8) — templates/plans/gate.sh's functions, unchanged ──────
gate_tree_sha() {
  local real_index tmp_dir sha=""
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then return 1; fi
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/gate-index.XXXXXX")" || return 1
  real_index="$(git rev-parse --git-path index 2>/dev/null)"
  if [[ -n "$real_index" && -f "$real_index" ]]; then
    cp "$real_index" "$tmp_dir/index" 2>/dev/null
  fi
  # Add everything, then take this gate's outputs back out: an exclude pathspec on the add
  # itself fails it whenever those outputs are ignored, which they normally are.
  if GIT_INDEX_FILE="$tmp_dir/index" git add -A -- ':/' >/dev/null 2>&1 \
    && GIT_INDEX_FILE="$tmp_dir/index" git rm -r -q --cached --ignore-unmatch -- "${GATE_TREE_EXCLUDES[@]}" >/dev/null 2>&1; then
    sha="$(GIT_INDEX_FILE="$tmp_dir/index" git write-tree 2>/dev/null)"
  fi
  rm -rf "$tmp_dir"
  if [[ -z "$sha" ]]; then return 1; fi
  echo "$sha"
}

gate_state_init() {
  local sha d
  sha="$(gate_tree_sha)" || return 0
  if ! mkdir -p "$GATE_STATE_ROOT/$sha" 2>/dev/null; then return 0; fi
  GATE_STATE_DIR="$GATE_STATE_ROOT/$sha"
  for d in "$GATE_STATE_ROOT"/*; do
    if [[ -d "$d" && "$d" != "$GATE_STATE_DIR" ]]; then rm -rf "$d"; fi
  done
  if [[ "$GATE_RESUME" == "$GATE_RESUME_ON" ]]; then
    echo "=== gate: GATE_RESUME — passes recorded for tree ${sha:0:$GATE_TREE_SHA_SHOWN} are reused ==="
  fi
}

gate_state_file() {
  local safe
  if [[ -z "$GATE_STATE_DIR" ]]; then return 0; fi
  safe="$(printf '%s' "$1" | tr -c "$GATE_STATE_LABEL_KEEP" "$GATE_STATE_LABEL_FILL")"
  if [[ -n "$safe" ]]; then echo "$GATE_STATE_DIR/$safe"; fi
}

gate_state_reusable() {
  if [[ "$GATE_RESUME" != "$GATE_RESUME_ON" || -z "$1" || ! -f "$1" ]]; then return 1; fi
  if [[ "$(sed -n 1p "$1")" != "$GATE_STATE_RC_KEY$GATE_STATE_PASS_RC" ]]; then return 1; fi
  [[ "$(sed -n 2p "$1")" == "$GATE_STATE_CMD_KEY$2" ]]
}

_section() {
  echo "## $1"
  echo "\$ $2"
  echo "exit: $3"
  echo "$4" | tail -n "$OUTPUT_TAIL_LINES"
  echo ""
}

# Run one check, append its command, exit code, and output tail to the report, and record
# it for a resumed run (a fresh one is neither reused nor recorded, and fails like blocking).
# _record <blocking|info|fresh> <label> <cmd...>
_record() {
  local informational="$1"; shift
  local label="$1"; shift
  local out rc state=""
  # A fresh check must describe the working copy as it is now (header, ONE EXCEPTION), so
  # it is never reused or recorded
  if [[ "$informational" != "$RECORD_FRESH" ]]; then state="$(gate_state_file "$label")"; fi
  if gate_state_reusable "$state" "$*"; then
    check_count=$((check_count + 1))
    tail -n +"$((GATE_STATE_HEADER_LINES + 1))" "$state" >> "$REPORT"
    echo "  ok    $label (resumed: passed on this tree already)"
    return 0
  fi
  out="$("$@" 2>&1)"
  rc=$?
  check_count=$((check_count + 1))
  _section "$label" "$*" "$rc" "$out" >> "$REPORT"
  if [[ -n "$state" ]]; then
    if { echo "$GATE_STATE_RC_KEY$rc"; echo "$GATE_STATE_CMD_KEY$*"; _section "$label" "$*" "$rc" "$out"; } > "$state.tmp" 2>/dev/null; then
      mv "$state.tmp" "$state" 2>/dev/null
    fi
  fi
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

# Blocking, but run on every gate, resumed or not, and never recorded: for a cheap check
# whose verdict must always describe the working copy as it is now (this checkout's
# generated .claude/settings.json — tracked, but the file every session loads), never a
# pass recorded before that file was deleted or drifted.
record_fresh() { _record "$RECORD_FRESH" "$@"; }

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

# The tree every check below is recorded against: taken once, before the first check
gate_state_init

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
  stamp-timing.sh
  feature-start.sh
  feature-capture.sh
  feature-close.sh
  forge.sh
  env-profile.sh
  check-plans.sh
  update.sh
  self/gate.sh
  self/profile-confinement.sh
  self/pr.sh
  self/worktree-setup.sh
  self/open-session.sh
  self/tests/level-sentinel.sh
  self/tests/tiered-gates.sh
  self/tests/cost-recovery.sh
  self/tests/capture-guard.sh
  self/tests/timestamps-are-utc.sh
  self/tests/subagent-capture.sh
  self/tests/claims-ledger.sh
  self/tests/session-share.sh
  self/tests/session-claims.sh
  self/tests/manifest-window.sh
  self/tests/manifest-pin-subagent.sh
  self/tests/manifest-unpin.sh
  self/tests/direct-timing.sh
  self/tests/stale-failed-sidecars.sh
  self/tests/stream-capture.sh
  self/tests/usage-limit-kill.sh
  self/tests/batch-sigpipe.sh
  self/tests/report-footnotes.sh
  self/tests/report-rounds.sh
  self/tests/feature-lifecycle.sh
  self/tests/verdict-readers.sh
  self/tests/routing-record.sh
  self/tests/capture-from-worktree.sh
  self/tests/worktree-claims.sh
  self/tests/recover-at-close.sh
  self/tests/recover-duration.sh
  self/tests/check-plans.sh
  self/tests/sync-check.sh
  self/tests/propagation-pull.sh
  self/tests/audit-fixes.sh
  self/tests/template-versions.sh
  self/tests/open-session.sh
  self/tests/allow-repo-commands.sh
  self/tests/hook-quote-oracle.sh
  self/tests/hook-escalation.sh
  self/tests/hook-wiring.sh
  self/tests/self-settings.sh
  self/tests/policy-table.sh
  self/tests/plan-numbering.sh
  self/tests/start-takeover.sh
  self/tests/rates-history.sh
  self/tests/env-profile.sh
  self/tests/cloud-start.sh
  self/tests/gate-resume.sh
  run-escalation-plan.sh
  templates/plans/gate.sh
  templates/plans/pr.sh
  templates/plans/worktree-setup.sh
  templates/plans/open-session.sh
  templates/plans/environment.sh
  templates/plans/cloud-setup.sh
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

# pricing.py prices a model the rate history lacks from LiteLLM, live; nothing the gate
# runs may reach the network. Each self-test that prices also exports this itself, so a
# test run by hand is offline too; rates-history.sh L turns it back on per call, pointed
# at a local fixture (self/features/live-model-rates/README.md).
export RATES_LIVE_LOOKUP=off

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
record "claims ledger self-test" bash self/tests/claims-ledger.sh
record "session share self-test" bash self/tests/session-share.sh
record "session claims self-test" bash self/tests/session-claims.sh
record "manifest window self-test" bash self/tests/manifest-window.sh
record "manifest pin-subagent self-test" bash self/tests/manifest-pin-subagent.sh
record "manifest unpin self-test" bash self/tests/manifest-unpin.sh
record "direct timing self-test" bash self/tests/direct-timing.sh
record "stale failed sidecars self-test" bash self/tests/stale-failed-sidecars.sh
record "stream capture self-test" bash self/tests/stream-capture.sh
record "usage limit kill self-test" bash self/tests/usage-limit-kill.sh
record "batch sigpipe self-test" bash self/tests/batch-sigpipe.sh
record "report footnotes self-test" bash self/tests/report-footnotes.sh
record "report rounds self-test" bash self/tests/report-rounds.sh
record "feature lifecycle self-test" bash self/tests/feature-lifecycle.sh
# The round readers the close and the batch branch on, called directly: the first line
# rule and the numeric stem order are invisible from a whole-lifecycle run.
record "verdict readers self-test" bash self/tests/verdict-readers.sh
record "routing record self-test" bash self/tests/routing-record.sh
record "capture from worktree self-test" bash self/tests/capture-from-worktree.sh
record "worktree claims self-test" bash self/tests/worktree-claims.sh
record "recover at close self-test" bash self/tests/recover-at-close.sh
record "recover duration self-test" bash self/tests/recover-duration.sh
record "check plans self-test" bash self/tests/check-plans.sh
record "sync check self-test" bash self/tests/sync-check.sh
# A propagation pull is its own hand feature in the consuming repo: update.sh pulls only
# on a started feature's branch, in its worktree, and nothing in the permission policy
# denies the merge it performs (LIFECYCLE.md -> "Propagate").
record "propagation pull self-test" bash self/tests/propagation-pull.sh
record "audit fixes self-test" bash self/tests/audit-fixes.sh
# Reads the checked-in templates rather than driving a runner, but blocking for the same
# reason as the rest: a template body edited without a version bump reports `in-sync` in
# every consuming repo while their seeded copies are stale (self/tests/README.md).
record "template versions self-test" bash self/tests/template-versions.sh
# The session opener's BODY, with osascript and claude stubbed on PATH: the worktree path
# reaches the session intact through both escaping layers. feature-lifecycle.sh S5 reads
# the same two files as text; this one runs them, which is the only way a quoting bug in
# a path nobody has yet is caught before it bills a session to the wrong branch.
record "open session self-test" bash self/tests/open-session.sh
# The auto-approve hook and its wiring (hooks/README.md). Blocking: every case in the
# first is a bypass that once approved a read outside the tree, a write, or an
# execution, and the second asserts the wiring never removes a repo's own settings.
record "allow repo commands self-test" bash self/tests/allow-repo-commands.sh
# The guard every deny keeps is a model of shell quoting, checked against bash and zsh
# themselves: three review rounds found it wrong by reasoning, and one case none found.
record "hook quote oracle self-test" bash self/tests/hook-quote-oracle.sh
# The other half of the same policy: the per-session escalation counter, the headless
# fall-through and the scratch entry point, none of which a single decision can show.
record "hook escalation self-test" bash self/tests/hook-escalation.sh
record "hook wiring self-test" bash self/tests/hook-wiring.sh
# This checkout's own policy file is tracked and generated: the check below fails on a
# missing or drifted copy, its guarded hook command is a no-op where the hook script is
# absent, and a vendored copy is held to the same bytes with the fix named upstream.
record "self settings self-test" bash self/tests/self-settings.sh
# The table both of them read (hooks/policy.py): the prefix rules it renders must cover
# every mutating entry, and the hook's own reader must deny each one. This is what keeps
# the two halves of the git policy from drifting apart again.
record "policy table self-test" bash self/tests/policy-table.sh
# A new feature's review stub is always 01, whatever another feature's corpus holds
# (self/PROJECT_FACTS.md) — one rule, both modes, and the start script is the only thing
# that writes that number.
record "plan numbering self-test" bash self/tests/plan-numbering.sh
# A start stopped between `worktree add -b` and its `S: start` commit is taken over by the
# next start of its slug, and pruned by any start, only when its lock proves it dead
# (self/features/start-takeover/).
record "start takeover self-test" bash self/tests/start-takeover.sh
# Every dollar figure is tokens times analysis/rates_history.json: the seed must price
# exactly as the hand table it replaced did, and a LiteLLM refresh may only ever append
# (self/features/litellm-pricing/README.md).
record "rates history self-test" bash self/tests/rates-history.sh
# The lifecycle never asks where it is running (self/DESIGN-2026-10-05-cloud-execution.md
# §1): the detector's three cases, the layout adapter, the confinement check on planted
# files, and forge.sh's two profile-dependent verbs; then the cloud start itself — the
# container as the worktree, its refusals and resume, the coordinator with no routing
# record whose window opens at its own first instant (self/features/execution-profiles/).
record "env profile self-test" bash self/tests/env-profile.sh
record "cloud start self-test" bash self/tests/cloud-start.sh
# A gate killed with its container re-runs only what had not finished on the same tree,
# and everything on a changed one (design §8) — the template gate and this one, each
# copied into a sandbox with stub checks, killed mid-run and resumed.
record "gate resume self-test" bash self/tests/gate-resume.sh

echo "=== gate: profile confinement ==="
# Only env-profile.sh, the adapters and their tests may spell the two profile variables
# (the script names them); every lifecycle script asks env-profile.sh's functions instead.
# Blocking: a script that reads the variable itself is the per-environment branch the
# design exists to keep out of the lifecycle. Prose (*.md) is exempt.
record "profile variables confined to the detector and its adapters" bash self/profile-confinement.sh

echo "=== gate: python syntax ==="
# Compiles each file independently — it does NOT exercise the bare cross-imports
# (`from pricing import …`), which only resolve when a script is run directly and
# python puts its own directory on sys.path.
record "py_compile analysis" python3 -m py_compile analysis/*.py
# The hook keeps a .sh name so its settings.json entry reads as a hook script; it is
# Python, and this is the one place its syntax is checked without running it.
record "py_compile hooks" python3 -m py_compile hooks/policy.py hooks/wire-settings.py hooks/allow-repo-commands.sh

echo "=== gate: permission policy ==="
# This checkout's .claude/settings.json is tracked but not hand-authored:
# hooks/wire-settings.py --self generates it, exactly as sync-plans.sh writes a consuming
# repo's (hooks/README.md, self/features/self-cloud-bootstrap). Blocking, because a file
# that has drifted from the helper is a policy nobody is enforcing — the deny rules a
# session actually loads are whatever the file says — and a missing one fails too: it
# means a fresh clone is born with no hook at all. Compared byte for byte; the failure
# names the exact regenerate command. In a vendored agentTooling the same comparison runs
# over the subtree's copy, and a failure there says the fix is upstream. record_fresh:
# never reused under GATE_RESUME=1 and never recorded (header, ONE EXCEPTION).
# -B: leave no hooks/__pycache__ behind in the tree the gate is checking.
record_fresh "permission policy wired into .claude/settings.json" \
  python3 -B hooks/wire-settings.py --self --repo "$REPO_DIR" --check

echo "=== gate: rate history ==="
# Whether analysis/rates_history.json's `checked` date is within the staleness threshold.
# Informational by design: a stale history skews cost figures but breaks nothing, and
# capture_planning.py and report.py both surface it in their own warnings[] as well. The
# gate never fetches — `analysis/refresh_rates.py --check` is the network half.
record_info "pricing rate history is current" \
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
