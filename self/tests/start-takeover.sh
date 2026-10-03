#!/usr/bin/env bash
set -uo pipefail

# Self-test for feature-start.sh taking over its own abandoned half-start
# (self/features/start-takeover/). Run by self/gate.sh, or by hand:
# bash self/tests/start-takeover.sh
#
# A half-start is what a start leaves when it stops between `git worktree add -b` and its
# `S: start` commit: branch S still at the commit it was created from, worktree
# R/.worktrees/S, no feature directory. An interrupt leaves one, and so does every refusal
# in that stretch (a failing hook, a red gate — the common case on a flaky base). Before
# this feature a re-run refused the existing branch for good and agents may not delete
# refs, so only a human cleared it. The rule under test:
#
#   - the start writes a lock carrying its PID right after `worktree add -b`, at
#     `$(git -C <worktree> rev-parse --absolute-git-dir)/feature-start.lock` (the
#     worktree's own admin dir under the common .git/worktrees/, invisible to its status),
#     and removes it after the `S: start` commit;
#   - a re-run of the same slug TAKES OVER the half-start — removes it and starts afresh —
#     only when the branch is unmoved since creation, the worktree is clean, and the
#     earlier start is provably dead: its lock names a PID that no longer exists, or there
#     is no lock at all (the shape every start before this feature left);
#   - a lock naming a live PID is a concurrent start: refused, naming the PID;
#   - the prune, run by a start of ANY slug, removes another slug's half-start whose lock
#     is dead, and keeps one whose lock is live or missing (a start between `worktree add`
#     and its lock write looks exactly like a missing lock, and the prune never deletes what
#     it cannot prove).
#
# Asserts, in order:
#   K1. a start killed during its hook leaves branch and worktree, and a lock naming its
#       PID, which is gone;
#   K2. re-run with the same slug, it succeeds: `S: start` on top of origin/main, a clean
#       worktree, no lock left, and a line saying it took over;
#   L1. a half-start whose lock names a live PID (a backgrounded sleep) is refused, naming
#       that PID, with the branch and worktree untouched; L2. once that process is killed,
#       the same re-run succeeds;
#   D1. a dirty half-start worktree is refused, the untracked file still in place;
#   M1. a branch that has moved since creation is refused, its commit still there;
#   N1. a half-start with no lock — the pre-fix shape — is taken over;
#   G1. a red gate refuses and leaves the worktree AND the lock, which now records the
#       refusal and names a PID that is gone; G2. the retry with a green gate succeeds —
#       the flaky-base case in self/BACKLOG.md;
#   P1. the prune takes another slug's dead-locked half-start and keeps a live-locked one,
#       a lockless one and a dirty dead-locked one.
#
# No model, no network. Stands up a throwaway agentTooling checkout that is a real git
# repo with a bare origin beside it, carrying the real feature-start.sh,
# plan-runner-roots.sh, analysis/{manifest,roots,pricing,transcript,routing}.py and the
# manifest template, plus a stub hook and a stub gate.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/start-takeover.XXXXXX")"
SLEEP_PIDS=""
trap 'if [[ -n "$SLEEP_PIDS" ]]; then kill $SLEEP_PIDS 2>/dev/null; fi; rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

# The lock's name inside the worktree's admin dir (feature-start.sh's START_LOCK_NAME) and
# the one line of it this test reads and forges.
LOCK_NAME="feature-start.lock"
LOCK_PID_KEY="pid"
WORKTREES_DIR=".worktrees"
# Long enough to outlive every phase that needs a live PID; killed by the EXIT trap.
LIVE_SLEEP_SECONDS=600
# How long kill_and_reap waits for a killed process to leave the process table.
REAP_POLLS=50
REAP_POLL_SECONDS=0.1
KILLED_BY_SIGKILL_RC=137

AT="$TMP/agentTooling"
ORIGIN="$TMP/origin.git"
mkdir -p "$AT/analysis" "$AT/self/features" "$AT/templates/plans/features"
for f in feature-start.sh plan-runner-roots.sh; do
  cp "$HERE/$f" "$AT/$f" 2>/dev/null || true
done
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
for f in roots.py manifest.py pricing.py litellm_prices.py rates_history.json transcript.py routing.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done
cp "$HERE/templates/plans/features/TEMPLATE.md" "$AT/templates/plans/features/TEMPLATE.md" 2>/dev/null || true

# Stub hook. HOOK_MODE=kill reads the lock the running start wrote, copies it to
# HOOK_LOCK_OUT, and SIGKILLs the start it names — an interrupt at the one point that
# matters, after `worktree add -b` and before `S: start`. Any other mode is a no-op.
cat > "$AT/self/worktree-setup.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "${HOOK_MODE:-}" == kill ]]; then
  lock="$(git rev-parse --absolute-git-dir)/feature-start.lock"
  cp "$lock" "${HOOK_LOCK_OUT:?}" 2>/dev/null
  pid="$(sed -n 's/^pid=//p' "$lock" 2>/dev/null)"
  if [[ -n "$pid" ]]; then kill -9 "$pid"; fi
fi
exit 0
STUB
# Stub gate: the real contract — exit 0, verdict in the report's last section.
cat > "$AT/self/gate.sh" <<'STUB'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
{ echo "# Gate report"; echo ""; echo "# VERDICT"; echo "${GATE_STUB_VERDICT:-all checks passed}"; } > "$HERE/self/gate-report.txt"
exit 0
STUB
printf 'self/gate-report*.txt\n' > "$AT/.gitignore"
chmod +x "$AT"/*.sh "$AT/self/"*.sh 2>/dev/null || true

git -C "$AT" init -q
git -C "$AT" symbolic-ref HEAD refs/heads/main
git -C "$AT" config user.email test@example.invalid
git -C "$AT" config user.name "start takeover test"
git -C "$AT" add -A
git -C "$AT" commit -q -m "init" >/dev/null 2>&1
git init -q --bare "$ORIGIN"
git -C "$AT" remote add origin "$ORIGIN"
git -C "$AT" push -q -u origin main 2>/dev/null

# $HOME is redirected because a start derives its routing record from the running
# session's transcript, and no test may read the machine's own ~/.claude (README.md); no
# session id at all, so no start here writes one.
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"
unset CLAUDE_CODE_SESSION_ID

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

start() { ( cd "$TMP" && HOME="$FAKE_HOME" "$AT/feature-start.sh" --self "$@" 2>&1 ); }
wt_path() { echo "$AT/$WORKTREES_DIR/$1"; }
lock_path() { echo "$(git -C "$(wt_path "$1")" rev-parse --absolute-git-dir 2>/dev/null)/$LOCK_NAME"; }
lock_pid() { sed -n "s/^$LOCK_PID_KEY=//p" "$1" 2>/dev/null | head -1; }
tip() { git -C "$AT" rev-parse -q --verify "refs/heads/$1" 2>/dev/null; }
tip_subject() { git -C "$AT" log -1 --format=%s "refs/heads/$1" 2>/dev/null; }
has_branch() { git -C "$AT" show-ref --verify --quiet "refs/heads/$1"; }
pid_alive() { [[ -n "$1" ]] && ps -p "$1" >/dev/null 2>&1; }
started_cleanly() {
  [[ "$(tip_subject "$1")" == "$1: start" \
    && "$(git -C "$AT" rev-parse "refs/heads/$1~1" 2>/dev/null)" == "$(git -C "$AT" rev-parse origin/main)" \
    && -z "$(git -C "$(wt_path "$1")" status --porcelain 2>/dev/null)" \
    && ! -e "$(lock_path "$1")" ]]
}

# half_start <slug> — a start SIGKILLed in its hook; leaves the lock copy at $TMP/<slug>.lock.
# Its stderr is dropped: that is only the subshell's "Killed: 9" job line.
half_start() {
  HOOK_MODE=kill HOOK_LOCK_OUT="$TMP/$1.lock" start "$1" >/dev/null 2>&1
}
# live_sleep — a process that stays alive, its PID in LIVE_PID. Started from a command
# substitution so it is nobody's job: this shell never prints a "Terminated" line for it.
live_sleep() {
  LIVE_PID="$(sleep "$LIVE_SLEEP_SECONDS" >/dev/null 2>&1 & echo $!)"
  SLEEP_PIDS="$SLEEP_PIDS $LIVE_PID"
}
# kill_and_reap <pid> — kill it and wait until ps no longer lists it.
kill_and_reap() {
  local tries=0
  kill "$1" 2>/dev/null
  while pid_alive "$1" && (( tries < REAP_POLLS )); do
    sleep "$REAP_POLL_SECONDS"; tries=$((tries + 1))
  done
}
# forge_lock <slug> <pid> — the lock a still-running start of <slug> would hold.
forge_lock() { printf '%s=%s\n' "$LOCK_PID_KEY" "$2" > "$(lock_path "$1")"; }

echo "start takeover"

# ── K. a start killed between worktree add and its start commit ───────────────
SLUG="takeover-killed"
half_start "$SLUG"; rc=$?
KILLED_PID="$(lock_pid "$TMP/$SLUG.lock")"
check "K1a. the killed start exits by SIGKILL (got $rc)" '[[ $rc -eq $KILLED_BY_SIGKILL_RC ]]'
check "K1b. it leaves branch and worktree, with no start commit" \
  'has_branch "$SLUG" && [[ -d "$(wt_path "$SLUG")" && "$(tip "$SLUG")" == "$(git -C "$AT" rev-parse origin/main)" ]]'
check "K1c. during its hook, the lock named the start's PID (got '$KILLED_PID')" '[[ "$KILLED_PID" =~ ^[0-9]+$ ]]'
check "K1d. ... and the lock is still there after the kill, naming a process that is gone" \
  '[[ -f "$(lock_path "$SLUG")" && "$(lock_pid "$(lock_path "$SLUG")")" == "$KILLED_PID" ]] && ! pid_alive "$KILLED_PID"'
out="$(start "$SLUG")"; rc=$?
check "K2a. re-run with the same slug succeeds (got $rc)" '[[ $rc -eq 0 ]]'
check "K2b. ... S: start on origin/main, a clean worktree, and no lock left behind" 'started_cleanly "$SLUG"'
check "K2c. ... and it says it took the half-start over" 'grep -qi "took over" <<<"$out"'

# ── L. a lock naming a live PID is a concurrent start ─────────────────────────
SLUG="takeover-live"
half_start "$SLUG"
live_sleep
forge_lock "$SLUG" "$LIVE_PID"
tip_before="$(tip "$SLUG")"
out="$(start "$SLUG")"; rc=$?
check "L1a. a half-start whose lock names a live PID is refused (got $rc)" '[[ $rc -ne 0 ]]'
check "L1b. ... naming that PID" 'grep -q "$LIVE_PID" <<<"$out"'
check "L1c. ... and the branch, worktree and lock are untouched" \
  '[[ "$(tip "$SLUG")" == "$tip_before" && -d "$(wt_path "$SLUG")" && "$(lock_pid "$(lock_path "$SLUG")")" == "$LIVE_PID" ]]'
kill_and_reap "$LIVE_PID"
out="$(start "$SLUG")"; rc=$?
check "L2. once that process is gone, the same re-run succeeds (got $rc)" '[[ $rc -eq 0 ]] && started_cleanly "$SLUG"'

# ── D. a dirty half-start is somebody's work ──────────────────────────────────
SLUG="takeover-dirty"
half_start "$SLUG"
echo "work in progress" > "$(wt_path "$SLUG")/notes.txt"
out="$(start "$SLUG")"; rc=$?
check "D1a. a dirty half-start worktree is refused (got $rc)" '[[ $rc -ne 0 ]]'
check "D1b. ... with the branch, the worktree and the untracked file still in place" \
  'has_branch "$SLUG" && [[ -f "$(wt_path "$SLUG")/notes.txt" ]]'
check "D1c. ... saying why" 'grep -qi "uncommitted" <<<"$out"'

# ── M. a branch that has moved holds work ─────────────────────────────────────
SLUG="takeover-moved"
half_start "$SLUG"
git -C "$(wt_path "$SLUG")" commit -q --allow-empty -m "somebody's work"
tip_before="$(tip "$SLUG")"
out="$(start "$SLUG")"; rc=$?
check "M1a. a branch that moved since its creation is refused (got $rc)" '[[ $rc -ne 0 ]]'
check "M1b. ... its commit still on it" '[[ "$(tip "$SLUG")" == "$tip_before" && "$(tip_subject "$SLUG")" == "somebody'"'"'s work" ]]'

# ── N. no lock at all: the half-start every earlier start left ────────────────
SLUG="takeover-nolock"
git -C "$AT" worktree add -q "$(wt_path "$SLUG")" -b "$SLUG" origin/main
out="$(start "$SLUG")"; rc=$?
check "N1. a lockless, unmoved, clean half-start is taken over (got $rc)" '[[ $rc -eq 0 ]] && started_cleanly "$SLUG"'

# ── G. the refusal path: a red gate on a flaky base ───────────────────────────
SLUG="takeover-flaky"
GATE_STUB_VERDICT="one or more checks FAILED" start "$SLUG" >/dev/null; rc=$?
G_LOCK="$(lock_path "$SLUG")"
check "G1a. a red gate refuses, leaving the worktree (got $rc)" '[[ $rc -ne 0 && -d "$(wt_path "$SLUG")" ]]'
check "G1b. ... and the lock, recording the refusal" '[[ -f "$G_LOCK" ]] && grep -q "^refused=" "$G_LOCK"'
check "G1c. ... naming a start that is gone" 'G_PID="$(lock_pid "$G_LOCK")"; [[ "$G_PID" =~ ^[0-9]+$ ]] && ! pid_alive "$G_PID"'
out="$(start "$SLUG")"; rc=$?
check "G2. the retry under the same slug, the gate green now, succeeds (got $rc)" '[[ $rc -eq 0 ]] && started_cleanly "$SLUG"'

# ── P. the prune uses the same predicate ──────────────────────────────────────
DEAD="takeover-prune-dead"; LIVE="takeover-prune-live"; NOLOCK="takeover-prune-nolock"
DIRTY="takeover-prune-dirty"
# The dead one LAST: every half_start is a start, and its own prune would take a
# dead-locked half-start made before it — correctly, but out of sight of P1b.
half_start "$LIVE"; live_sleep; forge_lock "$LIVE" "$LIVE_PID"
git -C "$AT" worktree add -q "$(wt_path "$NOLOCK")" -b "$NOLOCK" origin/main
half_start "$DIRTY"; echo "wip" > "$(wt_path "$DIRTY")/notes.txt"
half_start "$DEAD"
out="$(start takeover-pruner --no-gate)"; rc=$?
check "P1a. a start of another slug succeeds (got $rc)" '[[ $rc -eq 0 ]]'
check "P1b. ... and prunes the half-start whose lock is dead, worktree and branch" \
  '[[ ! -e "$(wt_path "$DEAD")" ]] && ! has_branch "$DEAD" && grep -q "$DEAD" <<<"$out"'
check "P1c. ... keeps the one whose lock names a live PID" '[[ -d "$(wt_path "$LIVE")" ]] && has_branch "$LIVE"'
check "P1d. ... keeps the one with no lock, which it cannot prove dead" '[[ -d "$(wt_path "$NOLOCK")" ]] && has_branch "$NOLOCK"'
check "P1e. ... and keeps a dead-locked one with uncommitted work, saying so" \
  '[[ -f "$(wt_path "$DIRTY")/notes.txt" ]] && has_branch "$DIRTY" && grep -q "kept .*$DIRTY" <<<"$out"'

if (( fails )); then echo "start takeover: FAILED ($fails)"; exit 1; fi
echo "start takeover: all checks passed"
