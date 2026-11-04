#!/usr/bin/env bash
set -uo pipefail

# Self-test for two guards in feature-start.sh under the cloud profile
# (self/features/start-tree-guard): the start commit carries the feature directory and
# nothing else the tree holds, and a tree that changes while the setup hook and the gate
# run is refused. Run by self/gate.sh, or by hand: bash self/tests/start-tree-guard.sh
#
# Each scenario is a fresh "container" as in cloud-start.sh — a throwaway checkout with a
# bare origin, the real feature-start.sh and its helpers, a stub hook, and a fake gate the
# fixture controls through the environment (GATE_RED, GATE_EDIT, GATE_TOUCH_FEATURE). No
# model, no network.
#
# Asserts, in order:
#   C1. a resumed start (the first refused by a red gate, the second green) with one file
#       staged and one tracked file modified outside the feature directory: the
#       `<slug>: start` commit names only paths under the feature directory, the staged file
#       is still staged and the modified file still modified, exit 0;
#   C2. a start whose gate modifies a tracked file outside the feature directory while it
#       runs is refused, the refusal names the path, no start commit, the lock left;
#   C3. once that change is committed on the branch, the same command resumes and succeeds;
#   C4. the control: a gate that writes only a (not ignored) gate report, and one that
#       writes into the feature directory, are not refused.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/start-tree-guard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

BASE="main"
LOCK_NAME="feature-start.lock"
TRACKED_FILE="tracked.txt"
STAGED_FILE="staged.txt"
GATE_EDIT_MARK="gate-edit"

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"
export HOOK_CWD_OUT="$TMP/hook-cwd"
unset CLAUDE_CODE_SESSION_ID GATE_RESUME GATE_RED GATE_EDIT GATE_TOUCH_FEATURE

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# container <name> [ignore-report] — a fresh checkout at $TMP/<name>/agentTooling on main,
# its bare origin beside it, one tracked file outside any feature directory. The report is
# git-ignored unless the second argument is "track-report".
container() {
  local root="$TMP/$1" at origin f
  at="$root/agentTooling"; origin="$root/origin.git"
  mkdir -p "$at/analysis" "$at/self/features" "$at/templates/plans/features" "$at/hooks"
  for f in feature-start.sh plan-runner-roots.sh env-profile.sh; do
    cp "$HERE/$f" "$at/$f" 2>/dev/null || true
  done
  cp "$HERE/hooks/env_profile.py" "$at/hooks/env_profile.py" 2>/dev/null || true
  for f in pricing.py litellm_prices.py rates_history.json roots.py transcript.py capture_planning.py report.py manifest.py routing.py recover_attempts.py; do
    cp "$HERE/analysis/$f" "$at/analysis/$f" 2>/dev/null || true
  done
  cp "$HERE/templates/plans/features/TEMPLATE.md" "$at/templates/plans/features/TEMPLATE.md" 2>/dev/null || true
  cp "$HERE/self/open-session.sh" "$at/self/open-session.sh" 2>/dev/null || true
  printf '#!/usr/bin/env bash\npwd > "${HOOK_CWD_OUT:?}"\nexit 0\n' > "$at/self/worktree-setup.sh"
  cat > "$at/self/gate.sh" <<'GATE'
#!/usr/bin/env bash
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${GATE_EDIT:-}" ]]; then
  grep -q gate-edit "$H/$GATE_EDIT" 2>/dev/null || echo gate-edit >> "$H/$GATE_EDIT"
fi
if [[ -n "${GATE_TOUCH_FEATURE:-}" ]]; then
  mkdir -p "$H/self/features/$GATE_TOUCH_FEATURE"
  echo note > "$H/self/features/$GATE_TOUCH_FEATURE/note.txt"
fi
verdict="all checks passed"
[[ -n "${GATE_RED:-}" ]] && verdict="1 check failed"
{ echo "# VERDICT"; echo "$verdict"; } > "$H/self/gate-report.txt"
GATE
  if [[ "${2:-}" != track-report ]]; then printf 'self/gate-report*.txt\n' > "$at/.gitignore"; fi
  echo "tracked" > "$at/$TRACKED_FILE"
  # A tracked file in the features folder, as a real repo has: git reports a new feature
  # directory as itself, not collapsed into an otherwise empty parent.
  echo "# features" > "$at/self/features/README.md"
  chmod +x "$at"/*.sh "$at/self/"*.sh 2>/dev/null || true
  git init -q "$at"
  git -C "$at" symbolic-ref HEAD "refs/heads/$BASE"
  git -C "$at" config user.email test@example.invalid
  git -C "$at" config user.name "tree guard test"
  git -C "$at" add -A
  git -C "$at" commit -q -m init
  git init -q --bare "$origin"
  git -C "$origin" symbolic-ref HEAD "refs/heads/$BASE"
  git -C "$at" remote add origin "$origin"
  git -C "$at" push -q -u origin "$BASE" 2>/dev/null
  echo "$at"
}
# cstart <checkout> <slug> [args] — that checkout's start under the cloud profile.
cstart() {
  local at="$1"; shift
  ( cd "$TMP" && env -u CLAUDE_CODE_REMOTE -u CLAUDE_CODE_SESSION_ID HOME="$FAKE_HOME" AGENTTOOLING_PROFILE=cloud "$at/feature-start.sh" --self "$@" 2>&1 )
}
# newbranch <checkout> <branch> — the container's session branch, cut at origin/main.
newbranch() { git -C "$1" checkout -q -b "$2" "origin/$BASE"; }

echo "start-tree-guard"

# ── C1. the start commit carries the feature directory only ───────────────────
AT="$(container c1)"
newbranch "$AT" claude/tg-one
FD="self/features/tg-one"
out="$(GATE_RED=1 cstart "$AT" tg-one --method direct)"; rc=$?
check "C1a. a start whose gate is red is refused, leaving a lock (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "^refused=" "$AT/.git/$LOCK_NAME" 2>/dev/null'
echo "modified" > "$AT/$TRACKED_FILE"
echo "staged" > "$AT/$STAGED_FILE"
git -C "$AT" add "$STAGED_FILE"
out="$(cstart "$AT" tg-one --method direct)"; rc=$?
check "C1b. the re-run, green, with a staged and a modified file outside the feature, resumes and starts (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$AT" log -1 --format=%s)" == "tg-one: start" ]] && grep -qi "resum" <<<"$out"'
check "C1c. ... the start commit names only paths under $FD" \
  '[[ -n "$(git -C "$AT" show --name-only --format= HEAD)" ]] && ! git -C "$AT" show --name-only --format= HEAD | grep -qv "^$FD/"'
check "C1d. ... the staged file is still staged and the modified file still modified" \
  '[[ "$(git -C "$AT" diff --cached --name-only)" == "$STAGED_FILE" && "$(git -C "$AT" diff --name-only)" == "$TRACKED_FILE" ]]'

# ── C2, C3. a tree that changes while the gate runs ───────────────────────────
AT="$(container c2)"
newbranch "$AT" claude/tg-two
head_before="$(git -C "$AT" rev-parse HEAD)"
out="$(GATE_EDIT="$TRACKED_FILE" cstart "$AT" tg-two --method direct)"; rc=$?
check "C2a. a gate that edits a tracked file while it runs is refused (got $rc)" '[[ $rc -eq 1 ]] && grep -q "refused" <<<"$out"'
check "C2b. ... the refusal names the path and says the gate judged a tree that no longer exists" \
  'grep -qF "$TRACKED_FILE" <<<"$out" && grep -qF "no longer exists" <<<"$out"'
check "C2c. ... no start commit, and the lock is left recording the refusal" \
  '[[ "$(git -C "$AT" rev-parse HEAD)" == "$head_before" ]] && grep -q "^refused=" "$AT/.git/$LOCK_NAME" 2>/dev/null'
git -C "$AT" add "$TRACKED_FILE"
git -C "$AT" commit -q -m "tg-two: keep the gate's edit"
out="$(GATE_EDIT="$TRACKED_FILE" cstart "$AT" tg-two --method direct)"; rc=$?
check "C3. with the change committed, the same command resumes and succeeds (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$AT" log -1 --format=%s)" == "tg-two: start" ]] && grep -qi "resum" <<<"$out" && [[ ! -e "$AT/.git/$LOCK_NAME" ]]'

# ── C4. the control: the gate report and the feature directory are not changes ─
AT="$(container c4 track-report)"
newbranch "$AT" claude/tg-four
out="$(cstart "$AT" tg-four --method direct)"; rc=$?
check "C4a. a gate that writes only a report that is not ignored is not refused (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$AT" log -1 --format=%s)" == "tg-four: start" ]]'
AT="$(container c4b)"
newbranch "$AT" claude/tg-five
out="$(GATE_TOUCH_FEATURE=tg-five cstart "$AT" tg-five --method direct)"; rc=$?
check "C4b. a gate that writes only into the feature directory is not refused (got $rc: $(tail -n 3 <<<"$out"))" \
  '[[ $rc -eq 0 && "$(git -C "$AT" log -1 --format=%s)" == "tg-five: start" ]]'

echo
if (( fails > 0 )); then echo "start-tree-guard: $fails assertion(s) FAILED"; exit 1; fi
echo "start-tree-guard: all assertions passed"
