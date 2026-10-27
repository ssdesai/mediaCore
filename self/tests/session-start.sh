#!/usr/bin/env bash
set -uo pipefail

# Self-test for session-start.sh, the SessionStart hook hooks/wire-settings.py wires into
# every consuming repo and into this checkout. Run by self/gate.sh, or by hand:
# bash self/tests/session-start.sh
#
# A consuming repo is built under mktemp -d with session-start.sh, env-profile.sh and
# plan-runner-roots.sh copied under agentTooling/, and a stub plans/cloud-setup.sh that
# records it ran and exits with $CLOUD_SETUP_RC. Asserts, in order:
#   C1. cloud, on an assigned branch, no feature: the profile line names the profile, its
#       decider and the branch; the next line names `feature-start.sh <slug>` run HERE, on
#       that branch, with no other branch made — and says not to check out main;
#   C2. ... then runs the repo's plans/cloud-setup.sh once, and exits 0;
#   C3. a cloud-setup.sh that fails makes the hook exit with its code, after the
#       orientation has been printed;
#   C4. cloud, on main: names `--branch <name>` and that the start cuts it, then (C4b) the
#       restart line — continuing a feature started on another branch, a fresh session on
#       it is the fix, never push main — also on a detached HEAD (C4c), never on a branch;
#   C5. cloud, a tracked manifest whose branches[0] is this branch: names the feature and
#       its close, not a start — and a manifest naming ANOTHER branch, or one that only
#       mentions this branch outside branches[0], is not this branch's feature;
#   C6. cloud with no plans/cloud-setup.sh: says to run sync-plans.sh, exits 0;
#   L1. local, on main: the primary-checkout line naming branch <slug> and the worktree,
#       and plans/cloud-setup.sh is NOT run;
#   L2. local, in a branch whose manifest names it: the feature and its close;
#   L3. local, on a branch no feature names: says features start from main;
#   S1. --self: commands spelled `./feature-start.sh --self` and features under
#       self/features/, and no plans/cloud-setup.sh is run even under cloud;
#   P1. a profile that is neither: one line naming it, exit 0, nothing run;
#   R1. no run wrote anything: the fixture's `git status` is clean.
#
# No model, no network. The profile is forced with AGENTTOOLING_PROFILE, so nothing
# depends on whether this test itself runs in a cloud container.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/session-start.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

BASE="main"
ASSIGNED="claude/assigned-x1"
SETUP_RAN_MARK="cloud-setup ran"
SETUP_FAIL_RC=7
COPIED=(session-start.sh env-profile.sh plan-runner-roots.sh)

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# manifest <file> <branch> — a feature manifest whose fence names <branch> as branches[0],
# and mentions $ASSIGNED in prose, which must not count.
manifest() {
  mkdir -p "$(dirname "$1")"
  printf '# a feature\n\nNot %s.\n\n```json\n{"slug": "x", "base": "%s", "branches": ["%s"]}\n```\n' \
    "$ASSIGNED" "$BASE" "$2" > "$1"
}

# consumer <name> — a consuming repo on main with agentTooling/ and the stub setup.
consumer() {
  local repo="$TMP/$1" f
  mkdir -p "$repo/agentTooling" "$repo/plans/features"
  for f in "${COPIED[@]}"; do cp "$HERE/$f" "$repo/agentTooling/$f"; done
  # The detector env-profile.sh asks, where it looks for it
  mkdir -p "$repo/agentTooling/hooks"
  cp "$HERE/hooks/env_profile.py" "$repo/agentTooling/hooks/env_profile.py"
  printf '#!/usr/bin/env bash\necho "%s"\nexit "${CLOUD_SETUP_RC:-0}"\n' "$SETUP_RAN_MARK" \
    > "$repo/plans/cloud-setup.sh"
  chmod +x "$repo/plans/cloud-setup.sh" "$repo/agentTooling/session-start.sh"
  git init -q "$repo"
  git -C "$repo" symbolic-ref HEAD "refs/heads/$BASE"
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name "session start test"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m init
  echo "$repo"
}

# hook <profile> <script> [args] — run as the hook runs: from the repo, stdin closed.
hook() {
  local profile="$1" script="$2"; shift 2
  ( cd "$(dirname "$script")/.." && env -u CLAUDE_CODE_REMOTE AGENTTOOLING_PROFILE="$profile" \
      "$script" "$@" 2>&1 </dev/null )
}

echo "session-start"

# ── C. cloud ──────────────────────────────────────────────────────────────────
R="$(consumer cloud)"
git -C "$R" checkout -q -b "$ASSIGNED"
SS="$R/agentTooling/session-start.sh"
out="$(hook cloud "$SS")"; rc=$?
check "C1a. the profile line names cloud, its decider and the branch" \
  'grep -qF "agentTooling  profile cloud (AGENTTOOLING_PROFILE=cloud); branch $ASSIGNED" <<<"$out"'
check "C1b. ... the start runs here, on this branch, making no other" \
  'grep -qF "./agentTooling/feature-start.sh <slug>, run here" <<<"$out" && grep -qF "no other branch created or pushed" <<<"$out"'
check "C1c. ... and says not to check out $BASE or branch per slug" \
  'grep -qF "Do not check out $BASE" <<<"$out"'
check "C2. it then runs plans/cloud-setup.sh once, and exits 0 (got $rc)" \
  '[[ $rc -eq 0 && "$(grep -cF "$SETUP_RAN_MARK" <<<"$out")" == 1 ]]'
out="$(CLOUD_SETUP_RC=$SETUP_FAIL_RC hook cloud "$SS")"; rc=$?
check "C3. a failing cloud-setup.sh is the hook's exit code, after the orientation (got $rc)" \
  '[[ $rc -eq $SETUP_FAIL_RC ]] && grep -qF "feature-start.sh" <<<"$out"'

git -C "$R" checkout -q "$BASE"
out="$(hook cloud "$SS")"
check "C4. on $BASE it names --branch, which the start cuts" \
  'grep -qF "./agentTooling/feature-start.sh <slug> --branch <name>" <<<"$out" && grep -qF "cuts <name> off origin/$BASE" <<<"$out"'
check "C4b. ... then the restart case: continuing a feature on another branch, a fresh session is the fix, never push $BASE" \
  'grep -A1 -F "cuts <name> off origin/$BASE" <<<"$out" | tail -n 1 | grep -qF "continuing a feature already started on another branch" && grep -qF "fresh session launched on that branch" <<<"$out" && grep -qF "never commit or push $BASE yourself" <<<"$out"'
git -C "$R" checkout -q --detach
out="$(hook cloud "$SS")"
check "C4c. on a detached HEAD in the cloud the restart line is printed too" \
  'grep -qF "continuing a feature already started on another branch" <<<"$out"'
git -C "$R" checkout -q "$ASSIGNED"
out="$(hook cloud "$SS")"
check "C4d. on an assigned branch it is not" \
  '! grep -qF "continuing a feature already started" <<<"$out"'

git -C "$R" checkout -q "$ASSIGNED"
manifest "$R/plans/features/other-one/README.md" "claude/someone-else"
manifest "$R/plans/features/this-one/README.md" "$ASSIGNED"
git -C "$R" add -A
git -C "$R" commit -q -m "this-one: start"
out="$(hook cloud "$SS")"
check "C5a. a tracked manifest naming this branch is its feature, with the close named" \
  'grep -qF "feature '"'"'this-one'"'"' is started on this branch" <<<"$out" && grep -qF "./agentTooling/feature-close.sh this-one" <<<"$out"'
check "C5b. ... and no start is offered, nor is other-one (which only mentions it) named" \
  '! grep -qF "feature-start.sh" <<<"$out" && ! grep -qF "other-one" <<<"$out"'

R2="$(consumer no-setup)"
rm "$R2/plans/cloud-setup.sh"
git -C "$R2" commit -q -am "no setup"
git -C "$R2" checkout -q -b "$ASSIGNED"
out="$(hook cloud "$R2/agentTooling/session-start.sh")"; rc=$?
check "C6. with no plans/cloud-setup.sh it says to run sync-plans.sh, exit 0 (got $rc)" \
  '[[ $rc -eq 0 ]] && grep -qF "sync-plans.sh" <<<"$out"'

# ── L. local ──────────────────────────────────────────────────────────────────
L="$(consumer local)"
out="$(hook local "$L/agentTooling/session-start.sh")"; rc=$?
check "L1a. local on $BASE: the primary checkout, branch <slug> and its worktree (got $rc)" \
  '[[ $rc -eq 0 ]] && grep -qF "the primary checkout" <<<"$out" && grep -qF ".worktrees/<slug>" <<<"$out"'
check "L1b. ... and plans/cloud-setup.sh is not run" '! grep -qF "$SETUP_RAN_MARK" <<<"$out"'
git -C "$L" checkout -q -b local-feat
manifest "$L/plans/features/local-feat/README.md" "local-feat"
git -C "$L" add -A
git -C "$L" commit -q -m "local-feat: start"
out="$(hook local "$L/agentTooling/session-start.sh")"
check "L2. a branch its manifest names is that feature, with its close" \
  'grep -qF "feature '"'"'local-feat'"'"' is started" <<<"$out" && grep -qF "feature-close.sh local-feat" <<<"$out"'
git -C "$L" checkout -q -b stray "$BASE"
out="$(hook local "$L/agentTooling/session-start.sh")"
check "L3. a branch no feature names: features start from the primary on $BASE" \
  'grep -qF "no started feature names '"'"'stray'"'"'" <<<"$out" && grep -qF "on $BASE with ./agentTooling/feature-start.sh <slug>" <<<"$out"'

# ── S. --self ─────────────────────────────────────────────────────────────────
S="$TMP/self"
mkdir -p "$S/self/features" "$S/plans"
for f in "${COPIED[@]}"; do cp "$HERE/$f" "$S/$f"; done
mkdir -p "$S/hooks"
cp "$HERE/hooks/env_profile.py" "$S/hooks/env_profile.py"
printf '#!/usr/bin/env bash\necho "%s"\n' "$SETUP_RAN_MARK" > "$S/plans/cloud-setup.sh"
chmod +x "$S/session-start.sh" "$S/plans/cloud-setup.sh"
git init -q "$S"
git -C "$S" symbolic-ref HEAD "refs/heads/$BASE"
git -C "$S" config user.email test@example.invalid
git -C "$S" config user.name "session start test"
git -C "$S" add -A
git -C "$S" commit -q -m init
git -C "$S" checkout -q -b "$ASSIGNED"
out="$( cd "$S" && env -u CLAUDE_CODE_REMOTE AGENTTOOLING_PROFILE=cloud "$S/session-start.sh" --self 2>&1 </dev/null )"; rc=$?
check "S1a. --self spells ./feature-start.sh --self <slug> (got $rc)" \
  '[[ $rc -eq 0 ]] && grep -qF "./feature-start.sh --self <slug>, run here" <<<"$out"'
check "S1b. ... and runs no plans/cloud-setup.sh, even under cloud" '! grep -qF "$SETUP_RAN_MARK" <<<"$out"'
manifest "$S/self/features/self-one/README.md" "$ASSIGNED"
git -C "$S" add -A
git -C "$S" commit -q -m "self-one: start"
out="$( cd "$S" && env -u CLAUDE_CODE_REMOTE AGENTTOOLING_PROFILE=cloud "$S/session-start.sh" --self 2>&1 </dev/null )"
check "S1c. --self reads self/features/ and names ./feature-close.sh --self" \
  'grep -qF "self/features/self-one/README.md" <<<"$out" && grep -qF "./feature-close.sh --self self-one" <<<"$out"'

# ── P. a profile that is neither ──────────────────────────────────────────────
out="$(hook bogus "$SS")"; rc=$?
check "P1. a bogus profile: one line naming it, exit 0, nothing run (got $rc)" \
  '[[ $rc -eq 0 && "$(wc -l <<<"$out" | tr -d " ")" == 1 ]] && grep -qF "bogus" <<<"$out" && ! grep -qF "$SETUP_RAN_MARK" <<<"$out"'

# ── R. read-only ──────────────────────────────────────────────────────────────
check "R1. no run wrote anything: every fixture's git status is clean" \
  '[[ -z "$(git -C "$R" status --porcelain)$(git -C "$R2" status --porcelain)$(git -C "$L" status --porcelain)$(git -C "$S" status --porcelain)" ]]'

echo
if (( fails )); then
  echo "session-start: $fails FAILED"
  exit 1
fi
echo "session-start: all assertions passed"
