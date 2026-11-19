#!/usr/bin/env bash
set -uo pipefail

# Self-test for the review round's checkpoint push (self/features/cloud-checkpoint-push/):
# under the cloud profile run-review.sh pushes the feature's branch (the manifest's
# branches[0]) to origin once the round's commits are made, through the one push function
# plan-runner-roots.sh holds, so a container reclaimed after the round loses nothing. The
# start's own push is asserted in self/tests/cloud-start.sh (A1i, P1e). Run by
# self/gate.sh, or by hand: bash self/tests/cloud-checkpoint-push.sh
#
# A consuming repo is built under mktemp -d with run-review.sh, the runner library, the
# profile adapter and its detector under agentTooling/, a stub `claude`, and a bare origin;
# the checkout sits on the session's assigned branch, which the manifest names as
# branches[0]. The profile is forced with AGENTTOOLING_PROFILE and CLAUDE_CODE_REMOTE is
# cleared, so the result is the same on a laptop and in a container. Asserts:
#   C1. cloud: the pass exits 0 and origin's copy of the branch is the local HEAD — the
#       round's last commit — with the commit subjects of the round on it, and the output
#       says the branch was pushed;
#   C2. local: the same pass pushes nothing — origin holds no such branch — and prints no
#       push line, no push warning;
#   C3. cloud, origin unreachable: the checkpoint is advisory — the pass still exits as
#       the reachable one did, the round's commits stay local, and exactly one warning line
#       says the push failed;
#   C4. cloud, no origin at all: exits 0, no push line and no warning;
#   C5. cloud, on a branch the manifest does not name as branches[0]: nothing is pushed.
#
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cloud-checkpoint-push.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

BASE="main"
SLUG="feat-ckpt"
BR="claude/feat-ckpt"
OTHER_BR="claude/someone-else"
REMOTE="origin"
# the role reader refuses a copy without its two modules (hook-silent-allow-sweep, item 7)
RUNNER_FILES=(run-review.sh plan-runner-lib.sh plan-runner-roots.sh stamp-timing.sh env-profile.sh hooks/orchestrator_role.py hooks/shared_rules.py)
DETECTOR="hooks/env_profile.py"
STAMPS_SUBJECT="$SLUG: review stamps"
ROUND_SUBJECT_RE="^$SLUG: review round [0-9]+$"
# What a checkpoint push prints: a success line naming the branch and remote, and (the
# only other line it may print) a warning naming the push
PUSH_LINE_RE="^  push +"
PUSH_WARN_RE="^  warn .*push"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s' "${@: -1}" > "${PROMPT_OUT:?}"
printf '{"type":"result","total_cost_usd":0,"session_id":"stub"}\n'
STUB
chmod +x "$TMP/bin/claude"

gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# fixture <name> — a consuming repo at $TMP/<name>/repo on $BR, origin at $TMP/<name>/origin.git
fixture() {
  local dir="$TMP/$1" repo origin f
  repo="$dir/repo"; origin="$dir/origin.git"
  mkdir -p "$repo/agentTooling/hooks" "$repo/plans/features/$SLUG/review/incomplete"
  for f in "${RUNNER_FILES[@]}"; do cp "$HERE/$f" "$repo/agentTooling/$f"; done
  cp "$HERE/$DETECTOR" "$repo/agentTooling/$DETECTOR"
  chmod +x "$repo"/agentTooling/*.sh
  git init -q "$repo"
  gitq "$repo" symbolic-ref HEAD "refs/heads/$BASE"
  gitq "$repo" config user.email test@example.invalid
  gitq "$repo" config user.name "checkpoint push test"
  printf '# %s\n\n```json\n{"slug": "%s", "base": "%s", "branches": ["%s"], "plans": ["01-review-opus"]}\n```\n' \
    "$SLUG" "$SLUG" "$BASE" "$BR" > "$repo/plans/features/$SLUG/README.md"
  printf '# 01 — review\n\nfeature: agentTooling/%s\n\nReview it.\n' "$SLUG" \
    > "$repo/plans/features/$SLUG/review/incomplete/01-review-opus.md"
  echo base > "$repo/base.txt"
  gitq "$repo" add -A
  gitq "$repo" commit -q -m "base"
  git init -q --bare "$origin"
  gitq "$origin" symbolic-ref HEAD "refs/heads/$BASE"
  gitq "$repo" remote add "$REMOTE" "$origin"
  gitq "$repo" push -q "$REMOTE" "$BASE"
  gitq "$repo" checkout -q -b "$BR"
  echo one > "$repo/feature-one.txt"
  gitq "$repo" add -A
  gitq "$repo" commit -q -m "feature: one"
  echo "$repo"
}

# review <repo> <profile> — the pass, as a coordinator runs it
review() {
  ( cd "$1" && env -u CLAUDE_CODE_REMOTE AGENTTOOLING_PROFILE="$2" PROMPT_OUT="$1/../prompt" \
      PATH="$TMP/bin:$PATH" agentTooling/run-review.sh "$SLUG" 2>&1 )
}
remote_branch() { git -C "$1" rev-parse --verify --quiet "refs/heads/$2" 2>/dev/null; }

echo "cloud-checkpoint-push"

# ── C1. cloud: the round is pushed ─────────────────────────────────────────────
repo="$(fixture c1)"; origin="$TMP/c1/origin.git"
out="$(review "$repo" cloud)"; rc=$?
head="$(git -C "$repo" rev-parse HEAD)"
check "C1a. the cloud pass exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "C1b. origin's $BR is the local HEAD, so the round's commits are on the remote" \
  '[[ -n "$head" && "$(remote_branch "$origin" "$BR")" == "$head" ]]'
check "C1c. ... and the local HEAD is the round's own commit, not the feature's" \
  'grep -qE "$ROUND_SUBJECT_RE|^$STAMPS_SUBJECT$" <<<"$(git -C "$repo" log -2 --format=%s)"'
check "C1d. the output says $BR was pushed to $REMOTE" 'grep -qE "${PUSH_LINE_RE}$BR -> $REMOTE" <<<"$out"'
check "C1e. the tree is clean after the pass" '[[ -z "$(git -C "$repo" status --porcelain)" ]]'

# ── C2. local: nothing pushed, nothing printed ─────────────────────────────────
repo="$(fixture c2)"; origin="$TMP/c2/origin.git"
out="$(review "$repo" local)"; rc=$?
check "C2a. the local pass exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "C2b. origin holds no $BR" '[[ -z "$(remote_branch "$origin" "$BR")" ]]'
check "C2c. the output has no push line and no push warning" \
  '! grep -qE "$PUSH_LINE_RE|$PUSH_WARN_RE" <<<"$out"'

# ── C3. cloud, origin unreachable: advisory ────────────────────────────────────
repo="$(fixture c3)"
gitq "$repo" remote set-url "$REMOTE" "$TMP/c3/gone.git"
out="$(review "$repo" cloud)"; rc=$?
check "C3a. an unreachable origin does not change the exit status (got $rc)" '[[ $rc -eq 0 ]]'
check "C3b. ... the round's commits are made locally" \
  'grep -qE "$ROUND_SUBJECT_RE|^$STAMPS_SUBJECT$" <<<"$(git -C "$repo" log -3 --format=%s)"'
check "C3c. ... and exactly one warning line says the push failed (got $(grep -cE "$PUSH_WARN_RE" <<<"$out"))" \
  '[[ "$(grep -cE "$PUSH_WARN_RE" <<<"$out")" == 1 ]]'

# ── C4. cloud, no origin ───────────────────────────────────────────────────────
repo="$(fixture c4)"
gitq "$repo" remote remove "$REMOTE"
out="$(review "$repo" cloud)"; rc=$?
check "C4. no origin: exits 0, no push line, no push warning (got $rc)" \
  '[[ $rc -eq 0 ]] && ! grep -qE "$PUSH_LINE_RE|$PUSH_WARN_RE" <<<"$out"'

# ── C5. cloud, on a branch the manifest does not name ──────────────────────────
repo="$(fixture c5)"; origin="$TMP/c5/origin.git"
gitq "$repo" checkout -q -b "$OTHER_BR"
out="$(review "$repo" cloud)"; rc=$?
check "C5. on $OTHER_BR (not branches[0]) nothing is pushed: neither branch is on origin (got $rc)" \
  '[[ -z "$(remote_branch "$origin" "$OTHER_BR")" && -z "$(remote_branch "$origin" "$BR")" ]] && ! grep -qE "$PUSH_LINE_RE" <<<"$out"'

echo
if (( fails > 0 )); then echo "cloud-checkpoint-push: $fails assertion(s) FAILED"; exit 1; fi
echo "cloud-checkpoint-push: all assertions passed"
