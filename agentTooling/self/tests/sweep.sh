#!/usr/bin/env bash
set -uo pipefail

# Self-test for sweep.sh, the weekly cost sweep (self/features/sweep-and-check/README.md).
# Run by self/gate.sh, or by hand: bash self/tests/sweep.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d — a real git repo with one
# commit, holding copies of sweep.sh, plan-runner-roots.sh, analysis/*.py and an empty
# self/features/ — and drives sweep.sh --self against it, with $HOME redirected so a
# synthesized transcript is the only session on disk. No model, no network.
#
# The contract under test (repeated verbatim in plan 78, which implements it): sweep.sh
# [--self] prints seven banners in order — rates, backfill, recover, capture, report,
# unclaimed, done — running python3 -B analysis/backfill_usage.py, recover_attempts.py,
# capture_planning.py --all and, for every slug with a modified or untracked
# planning.json/usage.json, report.py <slug> then report.py --all; exits 1 when any of
# backfill, recover, capture or report exited non-zero, but every step still runs and the
# done banner still prints; anything but --self on the command line is a usage error,
# exit 2.
#
# Asserts, in order:
#   1. usage: an unknown flag, with or without --self, is exit 2;
#   (Both fixture features have a closed window: capture --all skips an open one as
#   in flight, so a sweep never freezes a feature its close has not captured — see
#   capture-guard.sh phase 18.)
#   2. a clean run over one well-formed feature (feat-a) exits 0, prints the seven
#      banners in order, captures a planning.json with one session, writes report.md,
#      and the done banner names a nonzero changed-file count and the propagate line;
#   3. re-running is a no-op on the frozen capture — planning.json is byte-identical,
#      which is capture_planning.py's already-captured skip (self/tests/capture-guard.sh
#      assertion 10), not new behaviour sweep.sh invents;
#   4. a second feature (feat-b) whose declared branch matches no transcript makes the
#      capture step refuse — sweep.sh exits 1, feat-b gets no planning.json, but the
#      refusal does not stop the sweep: the done banner's two lines still print, and
#      feat-a's already-captured planning.json is untouched.
#
# RED until plan 78 lands: sweep.sh does not exist yet, so the cp below is tolerated
# (the cost-recovery.sh / sync-check.sh convention), and every assertion below fails
# loudly instead of the run aborting.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
AT_TMP="$TMP/agentTooling"
mkdir -p "$AT_TMP/analysis" "$AT_TMP/self/features"

cp "$HERE/sweep.sh" "$AT_TMP/sweep.sh" 2>/dev/null || true
cp "$HERE/plan-runner-roots.sh" "$AT_TMP/plan-runner-roots.sh" 2>/dev/null || true
for f in "$HERE"/analysis/*.py; do
  cp "$f" "$AT_TMP/analysis/$(basename "$f")" 2>/dev/null || true
done
chmod +x "$AT_TMP/sweep.sh" 2>/dev/null || true

# session_root() (roots.py) walks up from FEATURES_DIR for the nearest ancestor holding
# .git, and the report step's git status is read from that same checkout — so, unlike
# capture-guard.sh's bare `mkdir .git`, this one has to be a real, committed repo.
git -C "$AT_TMP" init -q
git -C "$AT_TMP" symbolic-ref HEAD refs/heads/main
git -C "$AT_TMP" config user.email test@example.invalid
git -C "$AT_TMP" config user.name "sweep test"
git -C "$AT_TMP" add -A && git -C "$AT_TMP" commit -q -m "init"

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"

# project_dir <cwd> — the directory under $FAKE_HOME/.claude/projects/ a transcript for
# a session launched in <cwd> lives in. Copied from feature-lifecycle.sh, not sourced.
project_dir() { echo "$FAKE_HOME/.claude/projects/$(echo "$1" | tr '/' '-')"; }

# session_line SESSION_ID CWD BRANCH MESSAGE_ID MODEL TIMESTAMP INPUT OUTPUT CACHE_READ
#              CACHE_5M CACHE_1H — one transcript line. Copied from
# self/tests/fixtures/transcripts/build-transcript.sh (via feature-lifecycle.sh), not
# sourced.
session_line() {
  local session_id="$1" cwd="$2" branch="$3" message_id="$4" model="$5" timestamp="$6"
  local input="$7" output="$8" cache_read="$9" cache_5m="${10}" cache_1h="${11}"
  printf '{"type":"assistant","sessionId":"%s","cwd":"%s","gitBranch":"%s","timestamp":"%s","isSidechain":false,"message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s}}}}\n' \
    "$session_id" "$cwd" "$branch" "$timestamp" "$message_id" "$model" "$input" "$output" "$cache_read" "$cache_5m" "$cache_1h"
}

sweep() { ( cd "$TMP" && HOME="$FAKE_HOME" "$AT_TMP/sweep.sh" "$@" 2>&1 ); }

# sessions_count <planning.json> — the length of its sessions array.
sessions_count() { python3 -B -c "import json,sys; print(len(json.load(open(sys.argv[1]))['sessions']))" "$1" 2>/dev/null; }

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# write_manifest DIR SLUG BRANCHES_JSON — a feature README whose last ```json fence
# capture_planning.py reads: slug, branches, plans (empty), a session_window whose from
# is well before the fixture session and whose to is open.
write_manifest() {
  local dir="$1" slug="$2" branches="$3"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<EOF
# $slug

Fixture feature for self/tests/sweep.sh.

\`\`\`json
{
  "slug": "$slug",
  "branches": $branches,
  "plans": [],
  "session_window": {"from": "2026-01-01T00:00:00Z", "to": "2026-12-31T00:00:00Z"}
}
\`\`\`
EOF
}

# BANNERS — the contract's seven, in order.
BANNERS=(
  "=== sweep: rates ==="
  "=== sweep: backfill ==="
  "=== sweep: recover ==="
  "=== sweep: capture ==="
  "=== sweep: report ==="
  "=== sweep: unclaimed ==="
  "=== sweep: done ==="
)

# banners_in_order OUTPUT — each banner appears, and their first occurrences are at
# strictly increasing line numbers.
banners_in_order() {
  local out="$1" prev=0 ln b
  for b in "${BANNERS[@]}"; do
    ln="$(grep -nF -- "$b" <<<"$out" | head -n 1 | cut -d: -f1)"
    [[ -n "$ln" ]] || return 1
    (( ln > prev )) || return 1
    prev=$ln
  done
  return 0
}

echo "sweep"

# ── 1. usage ──────────────────────────────────────────────────────────────────
sweep --bogus >/dev/null 2>&1; rc=$?
check "1a. sweep.sh --bogus: exit 2 (got $rc)" '[[ $rc -eq 2 ]]'
sweep --self --bogus >/dev/null 2>&1; rc=$?
check "1b. sweep.sh --self --bogus: exit 2 (got $rc)" '[[ $rc -eq 2 ]]'

# ── 2. a clean run over one well-formed feature ─────────────────────────────────
SLUG_A="feat-a"
FD_A="$AT_TMP/self/features/$SLUG_A"
write_manifest "$FD_A" "$SLUG_A" '["feat-a"]'
git -C "$AT_TMP" add -A && git -C "$AT_TMP" commit -q -m "feat-a: manifest"

SESSION_A="aaaaaaaa-0000-0000-0000-000000000001"
MODEL="claude-sonnet-5"
AT_PROJECTS="$(project_dir "$AT_TMP")"
mkdir -p "$AT_PROJECTS"
session_line "$SESSION_A" "$AT_TMP" "$SLUG_A" "msg-a" "$MODEL" "2026-06-01T00:00:00.000Z" \
  100 500 0 0 0 > "$AT_PROJECTS/$SESSION_A.jsonl"

out="$(sweep --self)"; rc=$?
PLANNING_A="$FD_A/planning.json"
check "2a. sweep.sh --self exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "2b. the seven banners appear, strictly in order" 'banners_in_order "$out"'
check "2c. feat-a's planning.json exists with one session" \
  '[[ -f "$PLANNING_A" ]] && [[ "$(sessions_count "$PLANNING_A")" == "1" ]]'
check "2d. feat-a's report.md was written" '[[ -f "$FD_A/report.md" ]]'
check "2e. output shows the rates verified line" 'grep -q "  rates  verified " <<<"$out"'
check "2f. output shows a nonzero changed-file count" \
  'grep -q "  changed  " <<<"$out" && ! grep -q "  changed  nothing" <<<"$out"'
check "2g. output shows the propagate line" 'grep -q "  next     propagate" <<<"$out"'

# ── 3. re-running is a no-op on the frozen capture ──────────────────────────────
cp "$PLANNING_A" "$TMP/planning-a.before.json"
out="$(sweep --self)"; rc=$?
check "3a. a second clean run exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "3b. planning.json is byte-identical (capture skipped a frozen record)" \
  'cmp -s "$TMP/planning-a.before.json" "$PLANNING_A"'

# ── 4. a refusing feature does not stop the sweep ───────────────────────────────
SLUG_B="feat-b"
FD_B="$AT_TMP/self/features/$SLUG_B"
write_manifest "$FD_B" "$SLUG_B" '["nowhere"]'
git -C "$AT_TMP" add -A && git -C "$AT_TMP" commit -q -m "feat-b: manifest"

out="$(sweep --self)"; rc=$?
PLANNING_B="$FD_B/planning.json"
check "4a. sweep.sh --self exits 1 when a feature's capture refuses (got $rc)" '[[ $rc -eq 1 ]]'
check "4b. feat-b gets no planning.json" '[[ ! -e "$PLANNING_B" ]]'
check "4c. the output still ends with the done banner's two lines" \
  '[[ "$(tail -n 1 <<<"$out")" == "  next     propagate: ./agentTooling/update.sh in each consuming repo" ]] && [[ "$(tail -n 2 <<<"$out" | head -n 1)" == "  changed  "* ]]'
check "4d. feat-a's planning.json is still byte-identical" \
  'cmp -s "$TMP/planning-a.before.json" "$PLANNING_A"'

echo
if (( fails > 0 )); then echo "sweep: $fails assertion(s) FAILED"; exit 1; fi
echo "sweep: all assertions passed"
