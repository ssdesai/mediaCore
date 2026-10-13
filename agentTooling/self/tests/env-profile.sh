#!/usr/bin/env bash
set -uo pipefail

# Self-test for the profile detector, the checkout-layout adapter, the confinement check
# and forge.sh's profile-dependent verbs (self/DESIGN-2026-10-05-cloud-execution.md §1,
# §5; self/features/execution-profiles/). Run by self/gate.sh, or by hand:
# bash self/tests/env-profile.sh
#
# Asserts, in order:
#   D1. an explicit AGENTTOOLING_PROFILE wins — `cloud` with CLAUDE_CODE_REMOTE unset,
#       `local` with CLAUDE_CODE_REMOTE=true — and the description names that variable;
#   D2. with no explicit value, CLAUDE_CODE_REMOTE=true is `cloud`, named as the decider;
#   D3. with neither, `local`, named as the default — and CLAUDE_CODE_REMOTE=false is no
#       reason to be cloud;
#   D4. an explicit value that is neither fails profile_check, naming it;
#   D5. the decided profile is exported to a child process;
#   M1–M6. the module hooks/env_profile.py, imported as the hook imports it: the same
#       three steps and the invalid override (an InvalidProfile, a ValueError naming the
#       value, never a silent `local`), each returning the profile AND what decided it,
#       and with no mapping given it reads the process environment;
#   M7. sourcing env-profile.sh makes exactly one python3 call, to that module;
#   M8. with no module beside it, env-profile.sh leaves the profile empty, says so on
#       stderr, and profile_check refuses;
#   M9. the same under `set -euo pipefail`, with no python3 on PATH and with no module:
#       the sourcing shell carries on to the warning and the refusal, never a silent exit;
#   L1. the layout, local: feature_checkout is <primary>/.worktrees/<slug> and
#       feature_branch the slug; create_checkout makes that worktree on that branch;
#   L2. the layout, cloud: feature_checkout is the primary itself; feature_branch is the
#       --branch value, else the current branch; on the base with neither it fails;
#       create_checkout on the current branch creates nothing, and from the base makes the
#       named branch with `checkout -b`, with no worktree;
#   C1. the confinement check passes on this checkout as it is;
#   C2. it fails on a planted lifecycle script that reads CLAUDE_CODE_REMOTE, naming the
#       file, and on one that reads AGENTTOOLING_PROFILE;
#   C3. it passes on CLAUDE_CODE_REMOTE_SESSION_ID (a different variable), on prose
#       (*.md), on an allowlisted adapter, on a test under self/tests/, and on an
#       untracked file;
#   C4. it passes on the detector module hooks/env_profile.py, and fails on the hook
#       hooks/allow-repo-commands.sh spelling one — the hook is not allowlisted;
#   F1. forge.sh auto-merge, local: one `gh pr merge <url> --auto --merge --delete-branch`,
#       never squash, printing the url;
#   F2. auto-merge, cloud: one `gh api -X PUT repos/<o>/<r>/pulls/<n>/ccr/auto_merge` with
#       `merge_method=merge`, and no `gh pr` or `gh auth status` call;
#   F3. auto-merge on a url with no PR number fails before any forge call; a REST failure
#       fails it non-zero; and it is a usage error with no url;
#   F4. forge.sh reachable: local asks `gh auth status`; cloud asks `gh api repos/<o>/<r>`
#       and never `auth status`; a failure is non-zero either way;
#   F5. an explicit profile that is neither refuses every forge verb before any call.
#
# No model, no network. The detector is sourced in child shells with both variables
# cleared first, so nothing depends on the environment this test runs in — a cloud
# container sets CLAUDE_CODE_REMOTE=true, a laptop does not.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/env-profile.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

DETECTOR="$HERE/env-profile.sh"
CONFINEMENT="$HERE/self/profile-confinement.sh"
WORKTREES_DIR=".worktrees"
FORGE_OWNER_REPO="profile-owner/profile-repo"
FORGE_URL="https://github.com/$FORGE_OWNER_REPO.git"
STUB_PR_URL="https://github.com/$FORGE_OWNER_REPO/pull/42"
STUB_PR_NUMBER="42"
FORBIDDEN_FORGE_CALL_RE='^(pr |auth status)'

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# probe <snippet> [VAR=value ...] — source the detector in a clean child shell, with both
# profile variables cleared and then the given ones set, and run the snippet.
cat > "$TMP/probe.sh" <<'PROBE'
#!/usr/bin/env bash
set -uo pipefail
source "$1"
eval "$2"
PROBE
probe() {
  local snippet="$1"; shift
  env -u CLAUDE_CODE_REMOTE -u AGENTTOOLING_PROFILE "$@" bash "$TMP/probe.sh" "$DETECTOR" "$snippet" 2>&1
}

echo "env-profile"

# ── D. the detector ───────────────────────────────────────────────────────────
out="$(probe 'profile_name; profile_describe' AGENTTOOLING_PROFILE=cloud)"
check "D1a. AGENTTOOLING_PROFILE=cloud with CLAUDE_CODE_REMOTE unset is cloud, decided by AGENTTOOLING_PROFILE (got '$out')" \
  '[[ "$(sed -n 1p <<<"$out")" == cloud ]] && sed -n 2p <<<"$out" | grep -qF "AGENTTOOLING_PROFILE=cloud"'
out="$(probe 'profile_name; profile_describe' AGENTTOOLING_PROFILE=local CLAUDE_CODE_REMOTE=true)"
check "D1b. AGENTTOOLING_PROFILE=local wins over CLAUDE_CODE_REMOTE=true (got '$out')" \
  '[[ "$(sed -n 1p <<<"$out")" == local ]] && sed -n 2p <<<"$out" | grep -qF "AGENTTOOLING_PROFILE=local"'
out="$(probe 'profile_name; profile_describe; echo "$PROFILE_DECIDED_BY"' CLAUDE_CODE_REMOTE=true)"
check "D2. CLAUDE_CODE_REMOTE=true alone is cloud, decided by CLAUDE_CODE_REMOTE (got '$out')" \
  '[[ "$(sed -n 1p <<<"$out")" == cloud ]] && sed -n 2p <<<"$out" | grep -qF "CLAUDE_CODE_REMOTE=true" && [[ "$(sed -n 3p <<<"$out")" == CLAUDE_CODE_REMOTE ]]'
out="$(probe 'profile_name; echo "$PROFILE_DECIDED_BY"')"
check "D3a. neither variable is local, by default (got '$out')" \
  '[[ "$(sed -n 1p <<<"$out")" == local && "$(sed -n 2p <<<"$out")" == default ]]'
out="$(probe 'profile_name' CLAUDE_CODE_REMOTE=false)"
check "D3b. CLAUDE_CODE_REMOTE=false is local (got '$out')" '[[ "$out" == local ]]'
out="$(probe 'if profile_check; then echo passed; else echo refused; fi' AGENTTOOLING_PROFILE=bogus)"
check "D4. AGENTTOOLING_PROFILE=bogus fails profile_check, naming the value (got '$out')" \
  'grep -q "refused" <<<"$out" && grep -qF "bogus" <<<"$out" && ! grep -q "passed" <<<"$out"'
out="$(probe 'bash -c "echo \$AGENTTOOLING_PROFILE"' CLAUDE_CODE_REMOTE=true)"
check "D5. the decided profile is exported to a child (got '$out')" '[[ "$out" == cloud ]]'

# ── M. the module, hooks/env_profile.py — the one place the rule lives ────────
# M1–M5 import it as the hook does, with an explicit environment mapping, so the
# machine's own variables cannot leak in; M6 asks it with the process environment cleared.
out="$(env -u CLAUDE_CODE_REMOTE -u AGENTTOOLING_PROFILE python3 -B - "$HERE/hooks" <<'PY' 2>&1
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import env_profile as m

def show(label, environ):
    try:
        d = m.detect(environ)
        print("%s %s %s" % (label, d.profile, d.decided_by))
    except m.InvalidProfile as exc:
        print("%s invalid %s %s" % (label, isinstance(exc, ValueError), exc.value))

show("M1", {"AGENTTOOLING_PROFILE": "cloud"})
show("M1b", {"AGENTTOOLING_PROFILE": "local", "CLAUDE_CODE_REMOTE": "true"})
show("M2", {"CLAUDE_CODE_REMOTE": "true"})
show("M3", {})
show("M3b", {"CLAUDE_CODE_REMOTE": "false"})
show("M4", {"AGENTTOOLING_PROFILE": "bogus", "CLAUDE_CODE_REMOTE": "true"})
show("M6", None)
PY
)"
line() { grep "^$1 " <<<"$out"; }
check "M1. module: AGENTTOOLING_PROFILE=cloud is cloud, decided by AGENTTOOLING_PROFILE (got '$(line M1)')" \
  '[[ "$(line M1)" == "M1 cloud AGENTTOOLING_PROFILE" ]]'
check "M1b. module: the override wins over CLAUDE_CODE_REMOTE=true (got '$(line M1b)')" \
  '[[ "$(line M1b)" == "M1b local AGENTTOOLING_PROFILE" ]]'
check "M2. module: CLAUDE_CODE_REMOTE=true alone is cloud, decided by it (got '$(line M2)')" \
  '[[ "$(line M2)" == "M2 cloud CLAUDE_CODE_REMOTE" ]]'
check "M3. module: neither is local by default, and CLAUDE_CODE_REMOTE=false is no reason to be cloud (got '$(line M3)', '$(line M3b)')" \
  '[[ "$(line M3)" == "M3 local default" && "$(line M3b)" == "M3b local default" ]]'
check "M4. module: an invalid override raises InvalidProfile, a ValueError naming the value — never a silent local (got '$(line M4)')" \
  '[[ "$(line M4)" == "M4 invalid True bogus" ]]'
check "M6. module: with no mapping it reads the process environment (got '$(line M6)')" \
  '[[ "$(line M6)" == "M6 local default" ]]'

# M7. env-profile.sh asks the module exactly once when sourced: a logging python3 first on
# PATH, handing every call to the real one.
REAL_PYTHON="$(command -v python3)"
PY_LOG="$TMP/python3-calls.log"
mkdir -p "$TMP/pybin"
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nexec "%s" "$@"\n' "$PY_LOG" "$REAL_PYTHON" > "$TMP/pybin/python3"
chmod +x "$TMP/pybin/python3"
: > "$PY_LOG"
out="$(probe 'profile_name; echo "$PROFILE_DECIDED_BY"' CLAUDE_CODE_REMOTE=true PATH="$TMP/pybin:$PATH")"
check "M7. sourcing env-profile.sh makes exactly one python3 call, to hooks/env_profile.py (got $(wc -l < "$PY_LOG"): $(head -1 "$PY_LOG"))" \
  '[[ "$(wc -l < "$PY_LOG" | tr -d " ")" == 1 ]] && grep -q "hooks/env_profile.py" "$PY_LOG" && [[ "$(sed -n 1p <<<"$out")" == cloud && "$(sed -n 2p <<<"$out")" == CLAUDE_CODE_REMOTE ]]'

# M8. with the module gone, env-profile.sh decides nothing: the profile is empty, it says
# why on stderr, and profile_check refuses — never a silent local.
NOMOD="$TMP/no-module"
mkdir -p "$NOMOD"
cp "$DETECTOR" "$NOMOD/env-profile.sh"
out="$(env -u CLAUDE_CODE_REMOTE -u AGENTTOOLING_PROFILE bash "$TMP/probe.sh" "$NOMOD/env-profile.sh" 'echo "profile=[$(profile_name)]"; if profile_check >/dev/null; then echo passed; else echo refused; fi' 2>&1)"
check "M8. no module beside env-profile.sh: empty profile, a warning naming it, profile_check refuses (got '$out')" \
  'grep -qF "profile=[]" <<<"$out" && grep -qF "env_profile.py" <<<"$out" && grep -q "refused" <<<"$out" && ! grep -q "passed" <<<"$out"'

# M9. the same undetected path under `set -euo pipefail`, as a consuming repo's gate sources
# it through plans/environment.sh: the sourcing shell must carry on to the warning and the
# refusal, never exit silently on the first read's EOF. Twice — with no python3 on PATH
# (only dirname, which the file's own path needs), and with no module beside it.
cat > "$TMP/probe-e.sh" <<'PROBE'
set -euo pipefail
source "$1"
echo "profile=[$(profile_name)]"
if profile_check >/dev/null; then echo passed; else echo refused; fi
echo reached-end
PROBE
BASH_BIN="$(command -v bash)"
NOPY_BIN="$TMP/no-python-bin"
mkdir -p "$NOPY_BIN"
ln -s "$(command -v dirname)" "$NOPY_BIN/dirname"
out="$(env -u CLAUDE_CODE_REMOTE -u AGENTTOOLING_PROFILE PATH="$NOPY_BIN" "$BASH_BIN" "$TMP/probe-e.sh" "$DETECTOR" 2>&1)"; rc=$?
check "M9a. set -e, no python3 on PATH: the sourcing shell carries on, warns naming the module, profile_check refuses (got $rc: '$out')" \
  '[[ $rc -eq 0 ]] && grep -qF "profile=[]" <<<"$out" && grep -qF "env_profile.py" <<<"$out" && grep -q "refused" <<<"$out" && grep -q "reached-end" <<<"$out"'
out="$(env -u CLAUDE_CODE_REMOTE -u AGENTTOOLING_PROFILE "$BASH_BIN" "$TMP/probe-e.sh" "$NOMOD/env-profile.sh" 2>&1)"; rc=$?
check "M9b. set -e, no module beside env-profile.sh: likewise (got $rc: '$out')" \
  '[[ $rc -eq 0 ]] && grep -qF "profile=[]" <<<"$out" && grep -qF "env_profile.py" <<<"$out" && grep -q "refused" <<<"$out" && grep -q "reached-end" <<<"$out"'

# ── L. the checkout layout ────────────────────────────────────────────────────
REPO="$TMP/layout"
ORIGIN="$TMP/layout-origin.git"
git init -q "$REPO"
git -C "$REPO" symbolic-ref HEAD refs/heads/main
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "env profile test"
echo base > "$REPO/base.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m init
git init -q --bare "$ORIGIN"
git -C "$REPO" remote add origin "$ORIGIN"
git -C "$REPO" push -q -u origin main 2>/dev/null

out="$(probe "layout_init '$REPO' '$WORKTREES_DIR' main; feature_checkout lay-one; feature_branch lay-one" AGENTTOOLING_PROFILE=local)"
check "L1a. local: checkout <primary>/$WORKTREES_DIR/<slug>, branch the slug (got '$out')" \
  '[[ "$(sed -n 1p <<<"$out")" == "$REPO/$WORKTREES_DIR/lay-one" && "$(sed -n 2p <<<"$out")" == lay-one ]]'
probe "layout_init '$REPO' '$WORKTREES_DIR' main; create_checkout lay-one origin/main" AGENTTOOLING_PROFILE=local >/dev/null; rc=$?
check "L1b. local create_checkout makes the worktree on branch <slug> (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$REPO/$WORKTREES_DIR/lay-one" branch --show-current 2>/dev/null)" == lay-one && "$(git -C "$REPO" branch --show-current)" == main ]]'

out="$(probe "layout_init '$REPO' '$WORKTREES_DIR' main claude/named; feature_checkout lay-two; feature_branch lay-two" AGENTTOOLING_PROFILE=cloud)"
check "L2a. cloud: the checkout is the primary, the branch is --branch (got '$out')" \
  '[[ "$(sed -n 1p <<<"$out")" == "$REPO" && "$(sed -n 2p <<<"$out")" == claude/named ]]'
out="$(probe "layout_init '$REPO' '$WORKTREES_DIR' main; if feature_branch lay-two; then echo has-branch; else echo no-branch; fi" AGENTTOOLING_PROFILE=cloud)"
check "L2b. cloud on the base with no --branch: feature_branch fails (got '$out')" \
  'grep -q "no-branch" <<<"$out" && ! grep -q "has-branch" <<<"$out"'
probe "layout_init '$REPO' '$WORKTREES_DIR' main claude/made; create_checkout lay-three origin/main" AGENTTOOLING_PROFILE=cloud >/dev/null; rc=$?
check "L2c. cloud create_checkout from the base checks out the named branch, no worktree (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$REPO" branch --show-current)" == claude/made && ! -e "$REPO/$WORKTREES_DIR/lay-three" ]]'
out="$(probe "layout_init '$REPO' '$WORKTREES_DIR' main; feature_branch lay-four" AGENTTOOLING_PROFILE=cloud)"
check "L2d. cloud off the base: feature_branch is the current branch (got '$out')" '[[ "$out" == claude/made ]]'
heads_before="$(git -C "$REPO" for-each-ref --format='%(refname)' refs/heads | sort | tr '\n' ' ')"
probe "layout_init '$REPO' '$WORKTREES_DIR' main; create_checkout lay-four origin/main" AGENTTOOLING_PROFILE=cloud >/dev/null; rc=$?
check "L2e. cloud create_checkout already on the branch creates nothing (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$REPO" for-each-ref --format="%(refname)" refs/heads | sort | tr "\n" " ")" == "$heads_before" && "$(git -C "$REPO" branch --show-current)" == claude/made ]]'

# ── C. the confinement check ──────────────────────────────────────────────────
out="$(bash "$CONFINEMENT" "$HERE" 2>&1)"; rc=$?
check "C1. this checkout passes the confinement check (got $rc: $(tail -1 <<<"$out"))" '[[ $rc -eq 0 ]]'

# plant <dir> — a throwaway tracked repo the check is pointed at.
PLANT="$TMP/plant"
plant_reset() {
  rm -rf "$PLANT"
  mkdir -p "$PLANT/self/tests" "$PLANT/templates/plans"
  git init -q "$PLANT"
  git -C "$PLANT" config user.email test@example.invalid
  git -C "$PLANT" config user.name "env profile test"
}
plant_commit() { git -C "$PLANT" add -A && git -C "$PLANT" commit -q -m plant; }
plant_reset
printf '#!/usr/bin/env bash\nif [[ "${CLAUDE_CODE_REMOTE:-}" == true ]]; then echo cloud; fi\n' > "$PLANT/feature-start.sh"
plant_commit
out="$(bash "$CONFINEMENT" "$PLANT" 2>&1)"; rc=$?
check "C2a. a lifecycle script reading CLAUDE_CODE_REMOTE fails the check, naming it (got $rc)" \
  '[[ $rc -ne 0 ]] && grep -qF "feature-start.sh" <<<"$out"'
plant_reset
printf '#!/usr/bin/env bash\nprofile="${AGENTTOOLING_PROFILE:-local}"\n' > "$PLANT/feature-close.sh"
plant_commit
out="$(bash "$CONFINEMENT" "$PLANT" 2>&1)"; rc=$?
check "C2b. one reading AGENTTOOLING_PROFILE fails it too (got $rc)" \
  '[[ $rc -ne 0 ]] && grep -qF "feature-close.sh" <<<"$out"'
plant_reset
printf '#!/usr/bin/env bash\nenv -u CLAUDE_CODE_REMOTE_SESSION_ID true\n' > "$PLANT/plan-runner-lib.sh"
printf '# Notes\n\nThe detector reads CLAUDE_CODE_REMOTE and AGENTTOOLING_PROFILE.\n' > "$PLANT/NOTES.md"
printf '#!/usr/bin/env bash\necho "${AGENTTOOLING_PROFILE:-}"\n' > "$PLANT/env-profile.sh"
printf '#!/usr/bin/env bash\nAGENTTOOLING_PROFILE=cloud true\n' > "$PLANT/self/tests/some-test.sh"
printf '#!/usr/bin/env bash\necho "${AGENTTOOLING_PROFILE:-}"\n' > "$PLANT/templates/plans/open-session.sh"
plant_commit
printf '#!/usr/bin/env bash\necho "$CLAUDE_CODE_REMOTE"\n' > "$PLANT/untracked-scratch.sh"
out="$(bash "$CONFINEMENT" "$PLANT" 2>&1)"; rc=$?
check "C3. the session-id variable, prose, an allowlisted adapter, a test and an untracked file all pass (got $rc: $out)" \
  '[[ $rc -eq 0 ]]'
plant_reset
mkdir -p "$PLANT/hooks"
printf 'PROFILE_ENV = "AGENTTOOLING_PROFILE"\nREMOTE_ENV = "CLAUDE_CODE_REMOTE"\n' > "$PLANT/hooks/env_profile.py"
plant_commit
out="$(bash "$CONFINEMENT" "$PLANT" 2>&1)"; rc=$?
check "C4a. the detector module hooks/env_profile.py is allowlisted (got $rc: $out)" '[[ $rc -eq 0 ]]'
printf '#!/usr/bin/env python3\nimport os\nos.environ.get("CLAUDE_CODE_REMOTE")\n' > "$PLANT/hooks/allow-repo-commands.sh"
plant_commit
out="$(bash "$CONFINEMENT" "$PLANT" 2>&1)"; rc=$?
check "C4b. the hook is NOT: one that spells a variable fails the check, naming it (got $rc)" \
  '[[ $rc -ne 0 ]] && grep -qF "hooks/allow-repo-commands.sh" <<<"$out"'

# ── F. forge.sh's profile-dependent verbs ─────────────────────────────────────
GH_ARGV_LOG="$TMP/gh-argv.log"
mkdir -p "$TMP/bin"
# Stub gh: logs every argv; `auth status` answers GH_AUTH_RC; `pr merge` and every
# `gh api` call answer GH_API_RC (0 by default), with a message on failure.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${GH_ARGV_LOG:?}"
case "$1 ${2:-}" in
  "auth status") exit "${GH_AUTH_RC:-0}" ;;
esac
if [[ "${GH_API_RC:-0}" != 0 ]]; then
  echo "gh: stubbed failure" >&2
  exit "$GH_API_RC"
fi
if [[ "$1" == api ]]; then echo '{"full_name":"stub"}'; fi
exit 0
STUB
chmod +x "$TMP/bin/gh"
FORGE_DIR="$TMP/forge"
git init -q "$FORGE_DIR"
git -C "$FORGE_DIR" remote add origin "$FORGE_URL"
cp "$HERE/forge.sh" "$HERE/env-profile.sh" "$FORGE_DIR/" 2>/dev/null
mkdir -p "$FORGE_DIR/hooks"
cp "$HERE/hooks/env_profile.py" "$FORGE_DIR/hooks/env_profile.py" 2>/dev/null
chmod +x "$FORGE_DIR/forge.sh" 2>/dev/null
# forge <profile> <args...> — forge.sh under that profile, the stub gh first on PATH.
forge() {
  local profile="$1"; shift
  env -u CLAUDE_CODE_REMOTE AGENTTOOLING_PROFILE="$profile" PATH="$TMP/bin:$PATH" \
    GH_ARGV_LOG="$GH_ARGV_LOG" "$FORGE_DIR/forge.sh" "$@"
}

: > "$GH_ARGV_LOG"
out="$(forge local auto-merge "$STUB_PR_URL")"; rc=$?
check "F1a. local auto-merge exits 0 printing the url (got $rc, '$out')" '[[ $rc -eq 0 && "$out" == "$STUB_PR_URL" ]]'
check "F1b. ... with exactly one gh pr merge <url> --auto --merge --delete-branch" \
  '[[ "$(grep -c "^pr merge " "$GH_ARGV_LOG")" == 1 ]] && grep -qxF "pr merge $STUB_PR_URL --auto --merge --delete-branch" "$GH_ARGV_LOG"'
check "F1c. ... and never a squash" '! grep -q -- "--squash" "$GH_ARGV_LOG"'

: > "$GH_ARGV_LOG"
out="$(forge cloud auto-merge "$STUB_PR_URL")"; rc=$?
check "F2a. cloud auto-merge exits 0 printing the url (got $rc, '$out')" '[[ $rc -eq 0 && "$out" == "$STUB_PR_URL" ]]'
check "F2b. ... with exactly one PUT repos/$FORGE_OWNER_REPO/pulls/$STUB_PR_NUMBER/ccr/auto_merge, merge_method=merge" \
  '[[ "$(grep -c "ccr/auto_merge" "$GH_ARGV_LOG")" == 1 ]] && grep -F "repos/$FORGE_OWNER_REPO/pulls/$STUB_PR_NUMBER/ccr/auto_merge" "$GH_ARGV_LOG" | grep -F -- "-X PUT" | grep -qF "merge_method=merge"'
check "F2c. ... and no gh pr, no gh auth status, no squash" \
  '! grep -qE "$FORBIDDEN_FORGE_CALL_RE" "$GH_ARGV_LOG" && ! grep -q "squash" "$GH_ARGV_LOG"'

: > "$GH_ARGV_LOG"
out="$(forge cloud auto-merge "https://github.com/$FORGE_OWNER_REPO/pulls" 2>/dev/null)"; rc=$?
check "F3a. a url with no PR number fails before any forge call (got $rc)" '[[ $rc -ne 0 && -z "$out" && ! -s "$GH_ARGV_LOG" ]]'
out="$(GH_API_RC=1 forge cloud auto-merge "$STUB_PR_URL" 2>/dev/null)"; rc=$?
check "F3b. a REST failure fails cloud auto-merge non-zero, printing nothing (got $rc, '$out')" '[[ $rc -ne 0 && -z "$out" ]]'
out="$(GH_API_RC=1 forge local auto-merge "$STUB_PR_URL" 2>/dev/null)"; rc=$?
check "F3c. ... and local auto-merge likewise (got $rc, '$out')" '[[ $rc -ne 0 && -z "$out" ]]'
forge local auto-merge >/dev/null 2>&1; rc=$?
check "F3d. auto-merge with no url is a usage error, exit 2 (got $rc)" '[[ $rc -eq 2 ]]'

: > "$GH_ARGV_LOG"
out="$(forge local reachable)"; rc=$?
check "F4a. local reachable asks gh auth status and exits 0 (got $rc, '$out')" \
  '[[ $rc -eq 0 ]] && grep -qx "auth status" "$GH_ARGV_LOG" && grep -qF "$FORGE_OWNER_REPO" <<<"$out"'
: > "$GH_ARGV_LOG"
out="$(forge cloud reachable)"; rc=$?
check "F4b. cloud reachable asks gh api repos/$FORGE_OWNER_REPO, never auth status (got $rc, '$out')" \
  '[[ $rc -eq 0 ]] && grep -q "^api .*repos/$FORGE_OWNER_REPO\( \|$\)" "$GH_ARGV_LOG" && ! grep -qE "$FORBIDDEN_FORGE_CALL_RE" "$GH_ARGV_LOG"'
GH_AUTH_RC=1 forge local reachable >/dev/null 2>&1; rcl=$?
GH_API_RC=1 forge cloud reachable >/dev/null 2>&1; rcc=$?
check "F4c. an unreachable forge is non-zero under both (got local $rcl, cloud $rcc)" '[[ $rcl -ne 0 && $rcc -ne 0 ]]'

: > "$GH_ARGV_LOG"
forge bogus pr-find some-branch >/dev/null 2>&1; rc=$?
check "F5. an explicit profile that is neither refuses the verb before any forge call (got $rc)" \
  '[[ $rc -ne 0 && ! -s "$GH_ARGV_LOG" ]]'

echo
if (( fails > 0 )); then echo "env-profile: $fails assertion(s) FAILED"; exit 1; fi
echo "env-profile: all assertions passed"
