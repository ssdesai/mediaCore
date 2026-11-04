#!/usr/bin/env bash
set -uo pipefail

# Self-test: in a cloud container, a consuming repo's feature-start.sh waits for the
# background setup session-start.sh began before it runs its setup hook and its base gate
# (self/features/hand-start-friction, item 1). Run by self/gate.sh, or by hand:
# bash self/tests/cloud-setup-wait.sh
#
# Every hand session in the 2026-10 propagation rounds ran the start as its first command
# while the repo's cloud setup was still installing in the background, and the base gate
# refused ("fastapi missing"). The contract is templates/plans/cloud-setup.sh's, at
# template-version 3: `setup_in_background` detaches a slow step, and `--wait` blocks
# until it is done.
#
# The fixture is a consumer repo with agentTooling vendored one level down (the layout
# feature-start.sh resolves without --self), a bare origin beside it, a stub gate that is
# green only when the slow step has finished, a stub plans/worktree-setup.sh that records
# whether it had, and a plans/cloud-setup.sh that is the REAL template with its
# "nothing configured" line replaced by one background step. The profile is forced with
# AGENTTOOLING_PROFILE and CLAUDE_CODE_REMOTE is cleared.
#
# Asserts:
#   W1. the template itself: `--wait` with nothing started exits 0 at once; a step started
#       through setup_in_background is not started a second time while it runs (one pid);
#       and `--wait` returns 0 only once the step has finished; it fails (exit 1) for a
#       step that ended with no exit code recorded (W1f) and for one still running at
#       its timeout (W1g); and under the local profile neither run writes anything (W1h);
#   W2. the setup started, then the start run at once: the start prints one `setup` line
#       saying it waited, the hook ran after the step finished, the gate is green, the
#       fence records gate "green", and `S: start` is committed;
#   W3. a background step that fails: the start refuses naming `plans/cloud-setup.sh
#       --wait`, commits nothing, and its hook never ran;
#   W4. a copy with no --wait (template-version < 3): one line says the start cannot wait,
#       and the start goes on;
#   W5. the local profile: no `setup` line, and the setup is never run.
#
# No model, no network. $HOME is a scratch directory for every start.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cloud-setup-wait.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
unset CLAUDE_CODE_REMOTE CLAUDE_CODE_SESSION_ID GATE_RESUME

TEMPLATE="$HERE/templates/plans/cloud-setup.sh"
# The skeleton's last line, which each fixture copy replaces with its own step
SKELETON_LINE_PREFIX='echo "  cloud-setup  plans/cloud-setup.sh has nothing configured'
# How long the stub's background step takes: longer than a start takes to reach its hook
SLOW_STEP_SECONDS=4
# A --wait timeout below that step's length (W1g)
SHORT_TIMEOUT_SECONDS=2
# The marker the slow step leaves in the git dir (never the tree: a dirty tree is refused)
DONE_MARKER_NAME="setup-done"
BRANCH="claude/wait-test"
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

fence() {
  python3 -c "import json,re,sys; t=open(sys.argv[1]).read(); m=re.findall(r'\`\`\`json\n(.*?)\n\`\`\`', t, re.S); d=json.loads(m[-1]); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null
}

# setup_copy <dest> <step body> — the real template with its skeleton line replaced by a
# function holding <step body> run through setup_in_background.
setup_copy() {
  awk -v prefix="$SKELETON_LINE_PREFIX" -v body="$2" '
    index($0, prefix) == 1 { print "slow_step() { " body " }"; print "setup_in_background slow_step"; next }
    { print }' "$TEMPLATE" > "$1"
  chmod +x "$1"
}

# consumer <name> <step body> — a fresh consumer repo on main, pushed to its bare origin,
# with the vendored slice a start needs. Prints the repo's path.
consumer() {
  local repo="$TMP/$1" at f
  at="$repo/agentTooling"
  mkdir -p "$at/analysis" "$at/hooks" "$at/templates/plans/features" "$repo/plans/features"
  for f in feature-start.sh plan-runner-roots.sh env-profile.sh; do
    cp "$HERE/$f" "$at/$f"
  done
  cp "$HERE/hooks/env_profile.py" "$at/hooks/env_profile.py"
  for f in roots.py manifest.py pricing.py litellm_prices.py rates_history.json transcript.py routing.py; do
    cp "$HERE/analysis/$f" "$at/analysis/$f"
  done
  cp "$HERE/templates/plans/features/TEMPLATE.md" "$at/templates/plans/features/TEMPLATE.md"
  setup_copy "$repo/plans/cloud-setup.sh" "$2"
  # The hook records whether the slow step had finished when it ran
  printf '#!/usr/bin/env bash\nif [[ -e "$(git rev-parse --absolute-git-dir)/%s" ]]; then echo done; else echo early; fi > "$(git rev-parse --absolute-git-dir)/hook-saw"\n' \
    "$DONE_MARKER_NAME" > "$repo/plans/worktree-setup.sh"
  # The gate is green only once the slow step has finished — the venv the real one needs
  printf '#!/usr/bin/env bash\nH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\nif [[ -e "$(git -C "$H" rev-parse --absolute-git-dir)/%s" ]]; then v="all checks passed"; else v="1 check failed"; fi\n{ echo "# VERDICT"; echo "$v"; } > "$H/plans/gate-report.txt"\n' \
    "$DONE_MARKER_NAME" > "$repo/plans/gate.sh"
  printf 'plans/gate-report*.txt\nplans/gate-state/\n' > "$repo/.gitignore"
  chmod +x "$at"/*.sh "$repo/plans/"*.sh
  git init -q "$repo"
  git -C "$repo" symbolic-ref HEAD refs/heads/main
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name "cloud setup wait test"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m init
  git init -q --bare "$repo-origin.git"
  git -C "$repo" remote add origin "$repo-origin.git"
  git -C "$repo" push -q -u origin main 2>/dev/null
  echo "$repo"
}

# The step every scenario but W3 runs: slow, then the marker
STEP_OK="sleep $SLOW_STEP_SECONDS; touch \"\$STATE_DIR/$DONE_MARKER_NAME\";"
STEP_FAILS="sleep 1; return 3;"

setup() { ( cd "$1" && AGENTTOOLING_PROFILE="$2" bash "$1/plans/cloud-setup.sh" "${@:3}" ); }
start() {
  ( cd "$TMP" && HOME="$FAKE_HOME" AGENTTOOLING_PROFILE="$2" "$1/agentTooling/feature-start.sh" "${@:3}" 2>&1 )
}
git_dir() { git -C "$1" rev-parse --absolute-git-dir; }

echo "cloud setup wait"

# ── W1. the template's contract on its own ────────────────────────────────────
R="$(consumer w1 "$STEP_OK")"
setup "$R" cloud --wait; rc=$?
check "W1a. --wait with nothing started exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
out1="$(setup "$R" cloud)"
pid1="$(cat "$(git_dir "$R")/cloud-setup.pid")"
out2="$(setup "$R" cloud)"
check "W1b. the step starts in the background and says --wait waits for it" \
  'grep -qF "slow_step started in the background" <<<"$out1" && grep -qF "plans/cloud-setup.sh --wait waits for it" <<<"$out1"'
check "W1c. a second session start while it runs starts nothing (same pid $pid1)" \
  'grep -qF "still running from an earlier start (pid $pid1)" <<<"$out2" && [[ "$(cat "$(git_dir "$R")/cloud-setup.pid")" == "$pid1" ]]'
setup "$R" cloud --wait; rc=$?
check "W1d. --wait returns 0 once the step has finished (got $rc)" \
  '[[ $rc -eq 0 && -e "$(git_dir "$R")/$DONE_MARKER_NAME" ]]'
check "W1e. the setup left the tree clean" '[[ -z "$(git -C "$R" status --porcelain)" ]]'
# A step that ended with no exit code recorded (killed): a pid file whose pid is gone, no rc
rm -f "$(git_dir "$R")/cloud-setup.rc"
out="$(setup "$R" cloud --wait 2>&1)"; rc=$?
check "W1f. a step that recorded no exit code fails --wait (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -qF "without recording an exit code" <<<"$out"'
# A step that outlasts the timeout: the copy's WAIT_TIMEOUT_SECONDS below the step's length
R="$(consumer w1g "$STEP_OK")"
cp "$R/plans/cloud-setup.sh" "$TMP/full-timeout"
awk -v t="$SHORT_TIMEOUT_SECONDS" '/^WAIT_TIMEOUT_SECONDS=/ { print "WAIT_TIMEOUT_SECONDS=" t; next } { print }' \
  "$R/plans/cloud-setup.sh" > "$TMP/short-timeout" && cat "$TMP/short-timeout" > "$R/plans/cloud-setup.sh"
setup "$R" cloud >/dev/null
out="$(setup "$R" cloud --wait 2>&1)"; rc=$?
check "W1g. a step still running at the timeout fails --wait (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -qF "still running after" <<<"$out"'
# Let the step end before the next scenario: under the shortened timeout this --wait could
# itself time out with the step still alive, so restore the template's own timeout first
cat "$TMP/full-timeout" > "$R/plans/cloud-setup.sh"
setup "$R" cloud --wait >/dev/null 2>&1
# Outside the cloud profile, --wait included, nothing runs and nothing is written
R="$(consumer w1h "$STEP_OK")"
setup "$R" local >/dev/null
setup "$R" local --wait; rc=$?
check "W1h. under the local profile the setup and --wait exit 0 and write nothing (got $rc)" \
  '[[ $rc -eq 0 ]] && ! ls "$(git_dir "$R")"/cloud-setup.* >/dev/null 2>&1'

# ── W2. the start waits, then hooks and gates ─────────────────────────────────
R="$(consumer w2 "$STEP_OK")"
setup "$R" cloud >/dev/null
out="$(start "$R" cloud wait-test --branch "$BRANCH")"; rc=$?
check "W2a. the start exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "W2a2. ... having really waited: the step was still running when the start reached it" \
  'grep -q "^  setup     waited [1-9][0-9]*s" <<<"$out"'
check "W2b. ... printing one setup line that says it waited" \
  '[[ "$(grep -c "^  setup     waited [0-9]*s for plans/cloud-setup.sh --wait" <<<"$out")" == 1 ]]'
check "W2c. ... before the hook, which ran after the step had finished" \
  '[[ "$(cat "$(git_dir "$R")/hook-saw" 2>/dev/null)" == done ]]'
check "W2d. ... and the base gate was green, recorded as such" \
  'grep -qF "  gate      all checks passed" <<<"$out" && [[ "$(fence "$R/plans/features/wait-test/README.md" "d[\"gate\"]")" == green ]]'
check "W2e. ... and S: start is committed" '[[ "$(git -C "$R" log -1 --format=%s)" == "wait-test: start" ]]'

# ── W3. a failed setup refuses the start ──────────────────────────────────────
R="$(consumer w3 "$STEP_FAILS")"
setup "$R" cloud >/dev/null
out="$(start "$R" cloud wait-test --branch "$BRANCH")"; rc=$?
check "W3a. the start refuses (got $rc)" '[[ $rc -eq 1 ]]'
check "W3b. ... naming plans/cloud-setup.sh --wait, and the setup's own reason" \
  'grep -qF "refused  plans/cloud-setup.sh --wait exited non-zero" <<<"$out" && grep -qF "the background setup exited 3" <<<"$out"'
check "W3c. ... with nothing committed and the hook never run" \
  '[[ "$(git -C "$R" log -1 --format=%s)" == init && ! -e "$(git_dir "$R")/hook-saw" ]]'

# ── W4. a copy that predates --wait ───────────────────────────────────────────
R="$(consumer w4 "$STEP_OK")"
printf '#!/usr/bin/env bash\necho "  cloud-setup  an old copy"\n' > "$R/plans/cloud-setup.sh"
touch "$(git_dir "$R")/$DONE_MARKER_NAME"
git -C "$R" commit -q -am "an old cloud-setup.sh"
git -C "$R" push -q origin main 2>/dev/null
out="$(start "$R" cloud wait-test --branch "$BRANCH")"; rc=$?
check "W4a. the start goes on (got $rc)" '[[ $rc -eq 0 ]]'
check "W4b. ... with one line saying it cannot wait, naming template-version 3" \
  '[[ "$(grep -c "^  setup     plans/cloud-setup.sh has no --wait (template-version < 3)" <<<"$out")" == 1 ]]'

# ── W5. the local profile is unchanged ────────────────────────────────────────
R="$(consumer w5 "$STEP_OK")"
# --no-gate: locally the start gates a new worktree, whose git dir carries no marker
out="$(start "$R" local wait-test --no-gate)"; rc=$?
check "W5a. a local start exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "W5b. ... with no setup line, and the setup never run" \
  '! grep -q "^  setup " <<<"$out" && [[ ! -e "$(git_dir "$R")/cloud-setup.pid" ]]'

if (( fails )); then echo "cloud-setup-wait: $fails check(s) failed"; exit 1; fi
echo "cloud-setup-wait: all checks passed"
