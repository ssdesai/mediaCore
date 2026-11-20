#!/usr/bin/env bash
set -uo pipefail

# Self-test for the orchestrator role guard (self/features/orchestrator-role-guard): once a
# session's id is the `session` of an orchestration record, the lifecycle scripts refuse to
# build in it, and an orchestration cannot be started mid-feature. Run by self/gate.sh, or
# by hand: bash self/tests/orchestrator-role.sh
#
# The rule lives once, in hooks/orchestrator_role.py; the shell reads it through
# plan-runner-roots.sh's orchestrator_record_for_session / refuse_orchestrator_session.
#
# Fixtures, under mktemp -d: a throwaway agentTooling checkout (a real git repo with a bare
# origin) carrying the real scripts, a stub gate, a stub worktree hook and stub `claude` and
# `gh` on PATH; the profile is `cloud`, the record `self/orchestrations/wave/README.md` is
# written by the real orchestration-start.sh for session S and committed on main, and the
# checkout is on `claude/feat-x` cut from origin/main.
#
# Asserts:
#   U1. the module's CLI prints the record path for S and nothing for another id, an empty
#       id, a missing self/orchestrations/, a record whose fences name only other sessions
#       (an id S is a prefix of included) and an unparseable fence; a broken neighbour never
#       hides the match; and EVERY fence counts (self/features/hook-role-hardening/): a
#       record whose earlier fence names S is S's, whatever later fence follows it;
#   U2. the shell reader agrees (orchestrator_record_for_session, sourced from
#       plan-runner-roots.sh), prints nothing for an empty id, and `--reason` names the
#       slug, the record path and templates/plans/ORCHESTRATOR_BRIEF.md; and a broken install
#       is never "no record" (self/features/hook-silent-allow-sweep/, item 7): a copy without
#       hooks/shared_rules.py or hooks/orchestrator_role.py, a module that crashes on import
#       and a rule that raises at run time (RULE_FAILED) each refuse, naming the module, in
#       the reader and in run-plans.sh (U2d-U2k); an empty id is still no record (U2i);
#   U3. the two record roots (U3b: a record under the consuming repo's plans/orchestrations is
#       the role; U3c: a legacy record in the vendored self/orchestrations keeps its role,
#       found first). That the roots are analysis/roots.py's is not asserted here: they have
#       one definition, hooks/shared_rules.py (shared-rules.sh);
#   G1-G6. each of the six scripts run as S (feature-start.sh both through --session and
#       through $CLAUDE_CODE_SESSION_ID alone; run-plans.sh, run-verify.sh, run-review.sh,
#       run-batch.sh, feature-close.sh through the environment) exits 1, prints the
#       `  refused  ` line naming `wave` and the record, and writes nothing: a clean tree,
#       no lock, no new branch, no feature directory, no timing.jsonl;
#   G7. as another id the start proceeds (`feat-x: start` committed) and run-plans.sh
#       --self finds nothing to do and exits 0;
#   G9. (self/features/hook-role-hardening/) orchestration-start.sh appended `<S> wave` to the
#       ledger in the git dir, and S stays refused with its record rewritten in place to a
#       featureless coordinator, or deleted;
#   G11. (round 2, the record as first committed) with no ledger, the committed record edited
#       in the working tree to a featureless coordinator, or deleted, still names S; an
#       uncommitted record answers from the working tree, and nothing once deleted; git off
#       PATH in a checkout fails closed with the unreadable reason;
#   G12. (round 3, R4–R6) git off PATH with the ledger naming the session: the role, not
#       'unreadable'; a record added only in a merge commit is read as first committed; a
#       shallow clone's boundary is never read as the add; 300 committed records are read
#       by one bounded call in under 2 s;
#   G10. (security audit round 1, F11–F13) the ledger: read when self/orchestrations/ cannot be
#       listed; an append after a line with no newline keeps both; a line of bad bytes and a
#       third word lose nothing else; an unknown id is nothing; a `.git` file naming no
#       directory fails closed with the ledger reason; a linked worktree reads the common
#       dir's ledger; after `--` an id spelled `--reason` is looked up; orchestration-start.sh
#       refuses `--reason`, `-x`, `-` and a 129-character id, and accepts 128;
#   G8. orchestration-capture.sh and manifest.py --orchestration wave get session still
#       work as S — the record's own tools are not guarded;
#   V1. orchestration-start.sh in a checkout whose tracked manifest names the current branch
#       refuses, naming the manifest, and writes nothing;
#   V2. the same when the manifest's `sessions` holds the id, on another branch;
#   V3. on another branch with another id it proceeds;
#   V4. (self/features/orchestration-start-branch-v2/) a manifest whose directory git C-quotes
#       (non-ASCII) still refuses: held_feature reads `ls-files -z`;
#   B1. (the same feature, cloud profile) on a detached HEAD or main with no --branch the
#       start is refused naming `--branch claude/<slug>` and writes nothing; --branch under the
#       local profile, and with --coordinator, is refused;
#   B2. with --branch the branch is cut off origin/main, the record is its one commit (the
#       record only), the ledger holds the session, and the branch is pushed;
#   B3. a branch on origin is refused in a single-branch clone that has no tracking ref for
#       it (git ls-remote asks origin), writing nothing; B4. an unreachable origin URL refuses
#       ("cannot ask origin");
#   B5. a branch a manifest on origin/main names (its directory C-quoted: ls-tree -z) is
#       refused, naming the manifest;
#   B6. the consumer layout: a vendored copy refuses a detached HEAD, refuses a branch the
#       consuming repo's plans/features manifest names, and commits the record in
#       plans/orchestrations on the cut branch;
#   B7. (rounds 2–4) a --branch that is not `claude/<slug>` — `origin/main`, `origin/HEAD`,
#       `origin/claude/x`, `+main`, `main`, `claude/Bad_Name`, `+refs/heads/main`,
#       `refs/heads/…`, `heads/…`, one holding `..`, an empty or nested slug — is refused
#       before any write, naming `--branch claude/<slug>`, and origin's refs (its main newer
#       than a stale local main) and the checkout's own refs are unchanged.
#
# No model, no network. $HOME is a scratch directory and the profile is pinned.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/orchestrator-role.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
# AGENTTOOLING_PROFILE too: a cloud feature-start.sh exports it (env-profile.sh) and runs the
# gate under it, and the fixture's own setup must not inherit the caller's profile
# (self/features/pull-round-cleanups/). The export first stands in for that caller on every
# run, standalone included, so dropping the variable from the unset fails 21 checks here.
export AGENTTOOLING_PROFILE=cloud
unset CLAUDE_CODE_SESSION_ID GATE_RESUME CLAUDE_CODE_REMOTE AGENTTOOLING_PROFILE

BASE="main"
FEATURE_BRANCH="claude/feat-x"
SLUG="feat-x"
RECORD_SLUG="wave"
RECORD_REL="self/orchestrations/$RECORD_SLUG/README.md"
SESSION_S="5e5e5e5e-0000-0000-0000-000000000001"
SESSION_T="7a7a7a7a-0000-0000-0000-000000000002"
SESSION_U="8b8b8b8b-0000-0000-0000-000000000003"
REFUSED_LINE="  refused  "
BRIEF_PATH="templates/plans/ORCHESTRATOR_BRIEF.md"
LOCK_NAME="feature-start.lock"
MODEL="claude-sonnet-5"
# The orchestrator's branch (B, V4): the record slug, the cloud branch prefix, and a manifest
# directory whose name git C-quotes without -z
BRANCH_SLUG="cut-wave"
CLOUD_PREFIX="claude/"
QUOTED_SLUG="café-feat"
QUOTED_BRANCH="claude/feat-q"
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects" "$TMP/bin"
# Stub claude and gh: a guarded script must never reach either; an unguarded one in the
# fixture would otherwise try the real binaries.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/claude"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/claude" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export HOOK_CWD_OUT="$TMP/hook-cwd"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

fence() {
  python3 -c "import json,re,sys; t=open(sys.argv[1]).read(); m=re.findall(r'\`\`\`json\n(.*?)\n\`\`\`', t, re.S); d=json.loads(m[-1]); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null
}

# container <name> — a fresh checkout at $TMP/<name>/agentTooling on main, bare origin beside.
container() {
  local root="$TMP/$1" at origin f
  at="$root/agentTooling"; origin="$root/origin.git"
  mkdir -p "$at/analysis" "$at/self/features" "$at/templates/plans/features" "$at/hooks"
  mkdir -p "$at/hooks" && cp "$HERE/hooks/shared_rules.py" "$at/hooks/"  # roots.py imports it
  for f in feature-start.sh feature-close.sh run-plans.sh run-verify.sh run-review.sh run-batch.sh \
           plan-runner-lib.sh plan-runner-roots.sh env-profile.sh stamp-timing.sh \
           orchestration-start.sh orchestration-capture.sh; do
    cp "$HERE/$f" "$at/$f"
  done
  cp "$HERE/hooks/env_profile.py" "$HERE/hooks/orchestrator_role.py" "$at/hooks/" 2>/dev/null || true
  cp "$HERE"/analysis/*.py "$HERE/analysis/rates_history.json" "$at/analysis/"
  cp "$HERE/templates/plans/features/TEMPLATE.md" "$at/templates/plans/features/TEMPLATE.md"
  printf '#!/usr/bin/env bash\npwd > "${HOOK_CWD_OUT:?}"\n' > "$at/self/worktree-setup.sh"
  printf '#!/usr/bin/env bash\nH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\n{ echo "# VERDICT"; echo "all checks passed"; } > "$H/self/gate-report.txt"\n' > "$at/self/gate.sh"
  printf 'self/gate-report*.txt\n' > "$at/.gitignore"
  chmod +x "$at"/*.sh "$at/self/"*.sh
  git init -q "$at"
  git -C "$at" symbolic-ref HEAD "refs/heads/$BASE"
  git -C "$at" config user.email test@example.invalid
  git -C "$at" config user.name "orchestrator role test"
  git -C "$at" add -A
  git -C "$at" commit -q -m init
  git init -q --bare "$origin"
  git -C "$origin" symbolic-ref HEAD "refs/heads/$BASE"
  git -C "$at" remote add origin "$origin"
  git -C "$at" push -q -u origin "$BASE" 2>/dev/null
  echo "$at"
}
# with_record <checkout> <session> — the real orchestration-start.sh writes the record on main,
# which is committed and pushed so a branch cut from origin/main carries it.
with_record() {
  ( cd "$TMP" && HOME="$FAKE_HOME" "$1/orchestration-start.sh" --self "$RECORD_SLUG" --session "$2" >/dev/null 2>&1 )
  git -C "$1" add -A
  git -C "$1" commit -q -m "record: $RECORD_SLUG"
  git -C "$1" push -q origin "$BASE" 2>/dev/null
}
assigned() { git -C "$1" checkout -q -b "$2" "origin/$BASE"; }
# manifest_text <slug> <branch> — a feature manifest whose fence's branches[0] is <branch>
manifest_text() { printf '# %s\n\n```json\n{"slug": "%s", "plans": [], "branches": ["%s"], "sessions": []}\n```\n' "$1" "$1" "$2"; }
# run_as <checkout> <session|-> <script> args... — a script of that checkout under the cloud
# profile, from outside it, as that session (the environment variable only).
run_as() {
  local at="$1" sid="$2" script="$3"; shift 3
  if [[ "$sid" == "-" ]]; then
    ( cd "$TMP" && env -u CLAUDE_CODE_REMOTE -u CLAUDE_CODE_SESSION_ID HOME="$FAKE_HOME" AGENTTOOLING_PROFILE=cloud "$at/$script" "$@" 2>&1 )
  else
    ( cd "$TMP" && env -u CLAUDE_CODE_REMOTE HOME="$FAKE_HOME" AGENTTOOLING_PROFILE=cloud CLAUDE_CODE_SESSION_ID="$sid" "$at/$script" "$@" 2>&1 )
  fi
}
heads() { git -C "$1" for-each-ref --format='%(refname)' refs/heads | sort | tr '\n' ' '; }
timing_files() { find "$1/self" -name timing.jsonl 2>/dev/null | wc -l | tr -d ' '; }

echo "orchestrator-role"

# ── U. the module and the shell reader ────────────────────────────────────────
UNIT="$TMP/unit/agentTooling"
mkdir -p "$UNIT/hooks" "$UNIT/self/orchestrations/$RECORD_SLUG" "$UNIT/self/orchestrations/broken" "$UNIT/self/orchestrations/earlier"
cp "$HERE/hooks/orchestrator_role.py" "$HERE/hooks/shared_rules.py" "$UNIT/hooks/"
cp "$HERE/plan-runner-roots.sh" "$UNIT/"
printf '# wave\n\n```json\n{"slug": "wave", "session": "%s"}\n```\n' "$SESSION_S" > "$UNIT/self/orchestrations/$RECORD_SLUG/README.md"
printf '# broken\n\n```json\n{not json\n```\n' > "$UNIT/self/orchestrations/broken/README.md"
# Fences naming other sessions, one of them an id S is a prefix of: no match
printf '# earlier\n\n```json\n{"session": "someone-else"}\n```\n\ntext\n\n```json\n{"session": "%s-last"}\n```\n' "$SESSION_S" > "$UNIT/self/orchestrations/earlier/README.md"
# EVERY fence counts (self/features/hook-role-hardening/, F1): a record whose earlier fence
# names S is S's even when a later fence — appended `{}` or another session — follows it.
# In a tooling dir of its own, so U1a's answer stays the one record.
FENCES="$TMP/unit-fences/agentTooling"
mkdir -p "$FENCES/self/orchestrations/stale" "$FENCES/self/orchestrations/empty-tail"
printf '# stale\n\n```json\n{"session": "%s"}\n```\n\ntext\n\n```json\n{"session": "someone-else"}\n```\n' "$SESSION_S" > "$FENCES/self/orchestrations/stale/README.md"
printf '# empty-tail\n\n```json\n{"session": "%s-x"}\n```\n\n```json\n{"session": "%s"}\n```\n\n```json\n{}\n```\n' "$SESSION_S" "$SESSION_U" > "$FENCES/self/orchestrations/empty-tail/README.md"
MODULE=(python3 -B "$UNIT/hooks/orchestrator_role.py")
EXPECT_RECORD="$UNIT/self/orchestrations/$RECORD_SLUG/README.md"
check "U1a. the CLI prints the record path for S, despite a broken neighbour" '[[ "$("${MODULE[@]}" "$UNIT" "$SESSION_S")" == "$EXPECT_RECORD" ]]'
check "U1b. another id prints nothing, exit 0" '[[ -z "$("${MODULE[@]}" "$UNIT" "other-id")" ]] && "${MODULE[@]}" "$UNIT" "other-id" >/dev/null'
check "U1c. an empty id prints nothing, exit 0" '[[ -z "$("${MODULE[@]}" "$UNIT" "")" ]] && "${MODULE[@]}" "$UNIT" "" >/dev/null'
check "U1d. a missing self/orchestrations/ prints nothing, exit 0" '[[ -z "$("${MODULE[@]}" "$TMP" "$SESSION_S")" ]] && "${MODULE[@]}" "$TMP" "$SESSION_S" >/dev/null'
check "U1e. an id S is a prefix of is not a match" \
  '[[ "$("${MODULE[@]}" "$UNIT" "$SESSION_S")" != *earlier* ]]'
check "U1g. every fence counts: an earlier fence naming S makes the record S's, whatever follows it" \
  '[[ "$("${MODULE[@]}" "$FENCES" "$SESSION_S")" == "$FENCES/self/orchestrations/stale/README.md" ]]'
check "U1h. ... and a role fence followed by an appended {} fence is still the role (U's record)" \
  '[[ "$("${MODULE[@]}" "$FENCES" "$SESSION_U")" == "$FENCES/self/orchestrations/empty-tail/README.md" ]]'
check "U1f. --reason for another id prints nothing" '[[ -z "$("${MODULE[@]}" "$UNIT" "other-id" --reason)" ]]'
# shellcheck disable=SC1091
reader() { ( source "$UNIT/plan-runner-roots.sh"; orchestrator_record_for_session "$1" ); }
check "U2a. the shell reader agrees: the record for S" '[[ "$(reader "$SESSION_S")" == "$EXPECT_RECORD" ]]'
check "U2b. ... nothing for another id and nothing for an empty id" '[[ -z "$(reader other-id)" && -z "$(reader "")" ]]'
reason="$("${MODULE[@]}" "$UNIT" "$SESSION_S" --reason)"
check "U2c. --reason names the slug, the record path and the implementer brief" \
  '[[ "$reason" == *"$RECORD_SLUG"* && "$reason" == *"$EXPECT_RECORD"* && "$reason" == *"$BRIEF_PATH"* ]]'
# The consuming repo's root is the parent of the tooling directory: a record under
# <repo>/plans/orchestrations is a role too, and a self record is found first
CONSUMER_UNIT="$TMP/consumer-unit"
mkdir -p "$CONSUMER_UNIT/agentTooling/hooks" "$CONSUMER_UNIT/plans/orchestrations/$RECORD_SLUG"
cp "$HERE/hooks/orchestrator_role.py" "$HERE/hooks/shared_rules.py" "$CONSUMER_UNIT/agentTooling/hooks/"
printf '# wave\n\n```json\n{"slug": "wave", "session": "%s"}\n```\n' "$SESSION_S" > "$CONSUMER_UNIT/plans/orchestrations/$RECORD_SLUG/README.md"
check "U3b. a record under the consuming repo's plans/orchestrations is the role" \
  '[[ "$(python3 -B "$CONSUMER_UNIT/agentTooling/hooks/orchestrator_role.py" "$CONSUMER_UNIT/agentTooling" "$SESSION_S")" == "$CONSUMER_UNIT/plans/orchestrations/$RECORD_SLUG/README.md" ]]'
mkdir -p "$CONSUMER_UNIT/agentTooling/self/orchestrations/legacy"
printf '# legacy\n\n```json\n{"slug": "legacy", "session": "%s"}\n```\n' "$SESSION_S" > "$CONSUMER_UNIT/agentTooling/self/orchestrations/legacy/README.md"
check "U3c. a legacy record in the vendored self/orchestrations keeps its role, and is found first" \
  '[[ "$(python3 -B "$CONSUMER_UNIT/agentTooling/hooks/orchestrator_role.py" "$CONSUMER_UNIT/agentTooling" "$SESSION_S")" == "$CONSUMER_UNIT/agentTooling/self/orchestrations/legacy/README.md" ]]'
# A broken install is never "no record" (self/features/hook-silent-allow-sweep/, item 7): a
# copy without either module, or with a module that crashes, refuses the build and names it.
refuser() { ( source "$UNIT/plan-runner-roots.sh"; refuse_orchestrator_session "$1" ) 2>&1; }
cp "$HERE/run-plans.sh" "$HERE/plan-runner-lib.sh" "$UNIT/"
chmod +x "$UNIT/run-plans.sh"
build_refusal() { ( cd "$UNIT" && CLAUDE_CODE_SESSION_ID="$1" ./run-plans.sh --self no-such-feature 2>&1 ); }
rm "$UNIT/hooks/shared_rules.py"
out="$(refuser other-id)"; rc=$?
check "U2d. without hooks/shared_rules.py the reader refuses, naming it (rc $rc)" \
  '[[ $rc -ne 0 && "$out" == *"refused"* && "$out" == *"hooks/shared_rules.py"* ]]'
out="$(build_refusal other-id)"; rc=$?
check "U2e. ... and so does a build script (run-plans.sh, rc $rc)" \
  '[[ $rc -ne 0 && "$out" == *"refused"* && "$out" == *"hooks/shared_rules.py"* ]]'
cp "$HERE/hooks/shared_rules.py" "$UNIT/hooks/"
printf 'raise SystemExit(7)\n' > "$UNIT/hooks/orchestrator_role.py"
out="$(refuser other-id)"; rc=$?
check "U2f. a role module that crashes refuses, naming it (rc $rc)" \
  '[[ $rc -ne 0 && "$out" == *"refused"* && "$out" == *"hooks/orchestrator_role.py"* ]]'
# A rule that RAISES at run time, after a clean import: only main()'s own guard stands
# between the raise and "no record", so it must exit RULE_FAILED and the reader refuse
ROLE_RULE_FAILED_RC=3   # hooks/orchestrator_role.py's RULE_FAILED
cp "$HERE/hooks/orchestrator_role.py" "$UNIT/hooks/"
python3 - "$UNIT/hooks/orchestrator_role.py" <<'PY'
import sys
path = sys.argv[1]
marker = 'if __name__ == "__main__":'
src = open(path).read()
assert marker in src, "the module's main guard moved: update U2j's planted raise"
planted = 'def record_for_session(*_args):\n    raise RuntimeError("planted")\n\n\n'
open(path, "w").write(src.replace(marker, planted + marker, 1))
PY
python3 -B "$UNIT/hooks/orchestrator_role.py" -- "$UNIT" other-id >/dev/null 2>&1; rc=$?
check "U2j. a rule that raises at run time exits RULE_FAILED (rc $rc)" \
  '[[ $rc -eq $ROLE_RULE_FAILED_RC ]]'
out="$(refuser other-id)"; rc=$?
check "U2k. ... and the reader refuses, naming hooks/orchestrator_role.py (rc $rc)" \
  '[[ $rc -ne 0 && "$out" == *"refused"* && "$out" == *"hooks/orchestrator_role.py"* ]]'
rm -rf "$UNIT/hooks"
out="$(refuser other-id)"; rc=$?
check "U2g. a copy with no hooks/ at all refuses, naming hooks/orchestrator_role.py (rc $rc)" \
  '[[ $rc -ne 0 && "$out" == *"refused"* && "$out" == *"hooks/orchestrator_role.py"* ]]'
out="$(build_refusal other-id)"; rc=$?
check "U2h. ... and so does a build script (run-plans.sh, rc $rc)" \
  '[[ $rc -ne 0 && "$out" == *"refused"* && "$out" == *"hooks/orchestrator_role.py"* ]]'
check "U2i. an empty session id is still no record, even without the module" \
  '( source "$UNIT/plan-runner-roots.sh"; refuse_orchestrator_session "" )'

# ── G. the six scripts, as the orchestrator ───────────────────────────────────
AT="$(container g)"
with_record "$AT" "$SESSION_S"
assigned "$AT" "$FEATURE_BRANCH"
heads_before="$(heads "$AT")"; head_before="$(git -C "$AT" rev-parse HEAD)"

# guarded <label> <session|-> <script> args... — runs it, then asserts the refusal and that nothing was written
guarded() {
  local label="$1" sid="$2"; shift 2
  local out rc
  out="$(run_as "$AT" "$sid" "$@")"; rc=$?
  check "$label exits 1, with the refused line naming $RECORD_SLUG and the record (got $rc)" \
    '[[ $rc -eq 1 && "$out" == *"$REFUSED_LINE"* && "$out" == *"$RECORD_SLUG"* && "$out" == *"$RECORD_REL"* ]]'
  check "$label wrote nothing: clean tree, same HEAD and branches, no lock, no $SLUG directory, no timing.jsonl" \
    '[[ -z "$(git -C "$AT" status --porcelain)" && "$(git -C "$AT" rev-parse HEAD)" == "$head_before" && "$(heads "$AT")" == "$heads_before" && ! -e "$AT/.git/$LOCK_NAME" && ! -e "$AT/self/features/$SLUG" && "$(timing_files "$AT")" == 0 ]]'
}
guarded "G1a. feature-start.sh --session S" "-" feature-start.sh --self "$SLUG" --method direct --branch "$FEATURE_BRANCH" --session "$SESSION_S"
guarded "G1b. feature-start.sh with \$CLAUDE_CODE_SESSION_ID=S and no flag" "$SESSION_S" feature-start.sh --self "$SLUG" --method direct --branch "$FEATURE_BRANCH"
guarded "G2. run-plans.sh" "$SESSION_S" run-plans.sh --self "$SLUG"
guarded "G3. run-verify.sh" "$SESSION_S" run-verify.sh --self "$SLUG"
guarded "G4. run-review.sh" "$SESSION_S" run-review.sh --self "$SLUG"
guarded "G5. run-batch.sh" "$SESSION_S" run-batch.sh --self "$SLUG"
guarded "G6. feature-close.sh" "$SESSION_S" feature-close.sh --self "$SLUG"

# ── G7. another session is not refused ────────────────────────────────────────
out="$(run_as "$AT" "$SESSION_T" feature-start.sh --self "$SLUG" --method direct --branch "$FEATURE_BRANCH" --no-gate)"; rc=$?
check "G7a. as another session the start proceeds and commits '$SLUG: start' (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$AT" log -1 --format=%s)" == "$SLUG: start" && "$out" != *"$REFUSED_LINE"* ]]'
out="$(run_as "$AT" "$SESSION_T" run-plans.sh --self)"; rc=$?
check "G7b. run-plans.sh --self as another session is not refused and exits 0 (got $rc)" \
  '[[ $rc -eq 0 && "$out" != *"$REFUSED_LINE"* && "$out" != *"orchestrator of"* ]]'

# ── G8. the record's own tools are not guarded ────────────────────────────────
mkdir -p "$FAKE_HOME/.claude/projects/-wave"
NOW_ISO="$(date -u '+%Y-%m-%dT%H:%M:%S').000Z"
session_line "$SESSION_S" "$AT" "$FEATURE_BRANCH" "msg-s-1" "$MODEL" "$NOW_ISO" 100 3000 0 0 0 > "$FAKE_HOME/.claude/projects/-wave/$SESSION_S.jsonl"
out="$(run_as "$AT" "$SESSION_S" orchestration-capture.sh --self "$RECORD_SLUG")"; rc=$?
check "G8a. orchestration-capture.sh as S is not refused by the role (got $rc)" \
  '[[ "$out" != *"orchestrator of"* && "$out" != *"a feature is built in a session of its own"* ]]'
out="$(python3 -B "$AT/analysis/manifest.py" --self --orchestration "$RECORD_SLUG" get session 2>&1)"; rc=$?
check "G8b. manifest.py --orchestration $RECORD_SLUG get session still prints S (got $rc)" '[[ $rc -eq 0 && "$out" == "$SESSION_S" ]]'

# ── G9. the ledger (self/features/hook-role-hardening/) ───────────────────────
LEDGER="$(git -C "$AT" rev-parse --absolute-git-dir)/agenttooling-orchestrators"
check "G9a. orchestration-start.sh appended '<S> $RECORD_SLUG' to the ledger in the git dir" \
  'grep -qx "$SESSION_S $RECORD_SLUG" "$LEDGER"'
# The edit the record alone cannot see: its one fence rewritten in place to a coordinator
# with no features. The ledger still names S, so the role holds.
printf '# Coordination: %s\n\n```json\n{"slug": "%s", "kind": "coordinator", "session": "%s", "features": []}\n```\n' \
  "$RECORD_SLUG" "$RECORD_SLUG" "$SESSION_S" > "$AT/$RECORD_REL"
out="$(run_as "$AT" "$SESSION_S" run-plans.sh --self "$SLUG")"; rc=$?
check "G9b. the record rewritten to a featureless coordinator in place: run-plans.sh as S is still refused (got $rc)" \
  '[[ $rc -eq 1 && "$out" == *"$REFUSED_LINE"* && "$out" == *"$RECORD_SLUG"* ]]'
rm -f "$AT/$RECORD_REL"
check "G9c. ... and with the record deleted outright" \
  '[[ -n "$(python3 -B "$AT/hooks/orchestrator_role.py" "$AT" "$SESSION_S")" ]]'
git -C "$AT" checkout -q -- "$RECORD_REL"

# ── G11. the record as first committed (round 2, owner-approved) ─────────────
# The record wave, committed on main by with_record, names S. With the ledger gone, a
# working-tree edit to a featureless coordinator, or the record deleted, still leaves S the
# orchestrator: the history read by `git log --diff-filter=A` + `git show` answers.
rm -f "$LEDGER"
printf '# Coordination: %s\n\n```json\n{"slug": "%s", "kind": "coordinator", "session": "%s", "features": []}\n```\n' \
  "$RECORD_SLUG" "$RECORD_SLUG" "$SESSION_S" > "$AT/$RECORD_REL"
check "G11a. no ledger, the committed record edited to a coordinator in the working tree: S is still the orchestrator" \
  '[[ "$(python3 -B "$AT/hooks/orchestrator_role.py" -- "$AT" "$SESSION_S")" == "$AT/$RECORD_REL" ]]'
rm -f "$AT/$RECORD_REL"
check "G11b. ... and with the record deleted" '[[ "$(python3 -B "$AT/hooks/orchestrator_role.py" -- "$AT" "$SESSION_S")" == "$AT/$RECORD_REL" ]]'
git -C "$AT" checkout -q -- "$RECORD_REL"
# A record never committed answers from the working tree alone, and nothing once deleted
mkdir -p "$AT/self/orchestrations/fresh"
printf '# x\n\n```json\n{"slug": "fresh", "session": "%s", "features": []}\n```\n' "$SESSION_U" > "$AT/self/orchestrations/fresh/README.md"
check "G11c. an uncommitted record names its session from the working tree" \
  '[[ "$(python3 -B "$AT/hooks/orchestrator_role.py" -- "$AT" "$SESSION_U")" == "$AT/self/orchestrations/fresh/README.md" ]]'
rm -rf "$AT/self/orchestrations/fresh"
check "G11d. ... and, never committed and with no ledger line, nothing once deleted" \
  '[[ -z "$(python3 -B "$AT/hooks/orchestrator_role.py" -- "$AT" "$SESSION_U")" ]]'
# git unavailable in a checkout: fail closed, with the unreadable reason
check "G11e. git off PATH in a checkout: the lookup fails closed" \
  '[[ "$(env PATH=/nonexistent "$(command -v python3)" -B "$AT/hooks/orchestrator_role.py" --reason -- "$AT" "$SESSION_T")" == *"could not be read"* ]]'

# ── G10. the ledger, hardened (security audit round 1, F11–F13) ───────────────
LG="$TMP/ledger/agentTooling"
mkdir -p "$LG/hooks"
cp "$HERE/hooks/orchestrator_role.py" "$HERE/hooks/shared_rules.py" "$LG/hooks/"
cp "$HERE/orchestration-start.sh" "$HERE/plan-runner-roots.sh" "$LG/"
# The start decides the profile through env-profile.sh (orchestration-start-branch-v2)
cp "$HERE/env-profile.sh" "$LG/"; cp "$HERE/hooks/env_profile.py" "$LG/hooks/"
# A --self start asks analysis/roots.py whether it may write here and refuses when it cannot
# ask (self/features/consumer-record-guard/)
mkdir -p "$LG/analysis" && cp "$HERE/analysis/roots.py" "$LG/analysis/"
git init -q "$LG"
LMOD=(python3 -B "$LG/hooks/orchestrator_role.py")
# F11: no self/orchestrations/ that can be listed (a FILE in its place) still reads the ledger
mkdir -p "$LG/self"; : > "$LG/self/orchestrations"
printf 'aaa111 one\n' > "$LG/.git/agenttooling-orchestrators"
check "G10a. records that cannot be listed: the ledger is still read" '[[ "$("${LMOD[@]}" -- "$LG" aaa111)" == *"/one/README.md" ]]'
rm -f "$LG/self/orchestrations"
# F12: a last line with no newline is not swallowed by the next append; an undecodable byte
# costs one line; a third word does not discard the line
printf 'bbb222 two' > "$LG/.git/agenttooling-orchestrators"
( cd "$TMP" && env -u CLAUDE_CODE_SESSION_ID "$LG/orchestration-start.sh" --self three --session ccc333 >/dev/null 2>&1 )
check "G10b. an append after a line with no newline keeps both" \
  '[[ "$("${LMOD[@]}" -- "$LG" bbb222)" == *"/two/README.md" && "$("${LMOD[@]}" -- "$LG" ccc333)" == *"/three/README.md" ]]'
printf '\xff\xfe junk\nddd444 four extra-word\n' >> "$LG/.git/agenttooling-orchestrators"
check "G10c. a line of bad bytes, then a line with a third word: the role still holds" '[[ "$("${LMOD[@]}" -- "$LG" ddd444)" == *"/four/README.md" ]]'
check "G10d. an id the ledger does not name: nothing" '[[ -z "$("${LMOD[@]}" -- "$LG" zzz999)" ]]'
# F12: a `.git` that cannot be resolved fails closed — for every session — with its own reason
BROKEN="$TMP/broken/agentTooling"
mkdir -p "$BROKEN/hooks"; cp "$HERE/hooks/orchestrator_role.py" "$HERE/hooks/shared_rules.py" "$BROKEN/hooks/"
printf 'gitdir: %s/nowhere\n' "$TMP" > "$BROKEN/.git"
check "G10e. a .git file naming no directory: every session reads as an orchestrator, with the ledger reason" \
  '[[ -n "$(python3 -B "$BROKEN/hooks/orchestrator_role.py" -- "$BROKEN" anyone)" && "$(python3 -B "$BROKEN/hooks/orchestrator_role.py" --reason -- "$BROKEN" anyone)" == *"ledger"*"could not be read"* ]]'
# F12: a linked worktree's `.git` file resolves to the common dir's ledger, without git
git -C "$LG" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
git -C "$LG" worktree add -q "$TMP/ledger-wt" >/dev/null 2>&1
mkdir -p "$TMP/ledger-wt/hooks"; cp "$HERE/hooks/orchestrator_role.py" "$HERE/hooks/shared_rules.py" "$TMP/ledger-wt/hooks/"
check "G10f. from a linked worktree the common dir's ledger is read" '[[ "$(python3 -B "$TMP/ledger-wt/hooks/orchestrator_role.py" -- "$TMP/ledger-wt" ccc333)" == *"/three/README.md" ]]'
# F13: after `--` an id is positional even when it looks like the flag
printf -- '--reason five\n' >> "$LG/.git/agenttooling-orchestrators"
check "G10g. after --, an id spelled --reason is looked up, not read as the flag" '[[ "$("${LMOD[@]}" -- "$LG" --reason)" == *"/five/README.md" ]]'
for bad in --reason -x - "$(printf 'a%.0s' $(seq 1 129))"; do
  ( cd "$TMP" && env -u CLAUDE_CODE_SESSION_ID "$LG/orchestration-start.sh" --self "bad-$RANDOM" --session "$bad" >/dev/null 2>&1 ); rc=$?
  check "G10h. orchestration-start.sh refuses the session id '${bad:0:12}' (len ${#bad}) (1)" '[[ $rc -eq 1 ]]'
done
( cd "$TMP" && env -u CLAUDE_CODE_SESSION_ID "$LG/orchestration-start.sh" --self max-len --session "$(printf 'b%.0s' $(seq 1 128))" >/dev/null 2>&1 ); rc=$?
check "G10i. ... and accepts one of exactly 128 characters (0)" '[[ $rc -eq 0 ]]'
# Round 2, N12: a `.git` directory with no HEAD is no checkout — fail closed; and a nested
# checkout does not hide the ledger of the one around it (the union)
NOHEAD="$TMP/nohead/agentTooling"
mkdir -p "$NOHEAD/hooks" "$NOHEAD/.git"; cp "$HERE/hooks/orchestrator_role.py" "$HERE/hooks/shared_rules.py" "$NOHEAD/hooks/"
check "G10j. a .git directory without HEAD fails closed" \
  '[[ "$(python3 -B "$NOHEAD/hooks/orchestrator_role.py" --reason -- "$NOHEAD" anyone)" == *"could not be read"* ]]'
OUTER="$TMP/outer"; INNER="$OUTER/vendored/agentTooling"
mkdir -p "$INNER/hooks"; cp "$HERE/hooks/orchestrator_role.py" "$HERE/hooks/shared_rules.py" "$INNER/hooks/"
git init -q "$OUTER"; git init -q "$INNER"
printf 'eee555 outerslug\n' > "$OUTER/.git/agenttooling-orchestrators"
check "G10k. the ledger of an enclosing checkout is read past a nested .git" \
  '[[ "$(python3 -B "$INNER/hooks/orchestrator_role.py" -- "$INNER" eee555)" == *"/outerslug/README.md" ]]'

# ── G12. security audit round 3: R4–R6 ───────────────────────────────────────
PY3="$(command -v python3)"
gitc() { git -C "$1" -c user.name=t -c user.email=t@example.com "${@:2}"; }
record_text() {  # record_text <slug> <session> [coordinator]
  if [[ -n "${3:-}" ]]; then
    printf '# x\n\n```json\n{"slug": "%s", "kind": "coordinator", "session": "%s", "features": []}\n```\n' "$1" "$2"
  else
    printf '# x\n\n```json\n{"slug": "%s", "session": "%s", "features": []}\n```\n' "$1" "$2"
  fi
}
# R4: git off PATH makes the history unreadable, but the ledger still names bbb222 — a source
# that names the session wins over one that cannot be read
check "G12a. history unreadable (git off PATH), the ledger names the session: the role, not 'unreadable'" \
  '[[ "$(env PATH=/nonexistent "$PY3" -B "$LG/hooks/orchestrator_role.py" -- "$LG" bbb222)" == *"/two/README.md" ]]'
# R5: a record added only in a merge commit is seen as first committed
MG="$TMP/merge-only/agentTooling"
mkdir -p "$MG/hooks"; cp "$HERE/hooks/orchestrator_role.py" "$HERE/hooks/shared_rules.py" "$MG/hooks/"
git init -q -b main "$MG"; gitc "$MG" commit -q --allow-empty -m base
gitc "$MG" checkout -q -b side; gitc "$MG" commit -q --allow-empty -m side; gitc "$MG" checkout -q main
gitc "$MG" merge -q --no-ff --no-commit side >/dev/null 2>&1
mkdir -p "$MG/self/orchestrations/merged"; record_text merged mmm111 > "$MG/self/orchestrations/merged/README.md"
gitc "$MG" add -A; gitc "$MG" commit -q -m "merge side, adding the record"
record_text merged mmm111 coordinator > "$MG/self/orchestrations/merged/README.md"
check "G12b. a record added only in a merge commit holds the role after a working-tree edit to coordinator" \
  '[[ "$(python3 -B "$MG/hooks/orchestrator_role.py" -- "$MG" mmm111)" == *"/merged/README.md" ]]'
# R5: a shallow clone's boundary commit only appears to add the record: never read as the add
SRC="$TMP/shallow-src"
mkdir -p "$SRC/self/orchestrations/deep"; git init -q -b main "$SRC"
record_text deep sss111 > "$SRC/self/orchestrations/deep/README.md"
gitc "$SRC" add -A; gitc "$SRC" commit -q -m "add the record"
gitc "$SRC" commit -q --allow-empty -m later
SH="$TMP/shallow"
git clone -q --depth 1 "file://$SRC" "$SH" 2>/dev/null
mkdir -p "$SH/hooks"; cp "$HERE/hooks/orchestrator_role.py" "$HERE/hooks/shared_rules.py" "$SH/hooks/"
record_text deep sss111 coordinator > "$SH/self/orchestrations/deep/README.md"
check "G12c. the shallow clone's premise: its boundary commit lists the record as added" \
  '[[ -s "$SH/.git/shallow" && -n "$(git -C "$SH" log --diff-filter=A --format=%H -- self/orchestrations/deep/README.md)" ]]'
check "G12d. ... and that boundary is never read as the record's first commit (the working tree, a coordinator now, answers)" \
  '[[ -z "$(python3 -B "$SH/hooks/orchestrator_role.py" -- "$SH" sss111)" ]]'
# R6: one bounded git call, whatever the number of records
PERF="$TMP/perf/agentTooling"
mkdir -p "$PERF/hooks"; cp "$HERE/hooks/orchestrator_role.py" "$HERE/hooks/shared_rules.py" "$PERF/hooks/"; git init -q "$PERF"
for n in $(seq 1 300); do
  mkdir -p "$PERF/self/orchestrations/rec-$n"; record_text "rec-$n" "perf-$n" > "$PERF/self/orchestrations/rec-$n/README.md"
done
gitc "$PERF" add -A; gitc "$PERF" commit -q -m "300 records"
rm -rf "$PERF/self/orchestrations"
started="$(date +%s%N)"
found="$(python3 -B "$PERF/hooks/orchestrator_role.py" -- "$PERF" perf-299)"
elapsed_ms=$(( ($(date +%s%N) - started) / 1000000 ))
check "G12e. 300 committed records, all deleted: the history still names perf-299, in under 2 s (took ${elapsed_ms} ms)" \
  '[[ "$found" == *"/rec-299/README.md" && $elapsed_ms -lt 2000 ]]'

# ── V. the reverse guard: a coordinator cannot become an orchestrator mid-feature ──
AT="$(container v)"
assigned "$AT" "$FEATURE_BRANCH"
out="$(run_as "$AT" "$SESSION_T" feature-start.sh --self "$SLUG" --method direct --branch "$FEATURE_BRANCH" --no-gate)"; rc=$?
check "V0. the fixture's feature starts (got $rc)" '[[ $rc -eq 0 && -f "$AT/self/features/$SLUG/README.md" ]]'
before="$(git -C "$AT" status --porcelain)"
out="$(run_as "$AT" "$SESSION_U" orchestration-start.sh --self other --session "$SESSION_U")"; rc=$?
check "V1a. a tracked manifest naming the current branch refuses the orchestration (got $rc)" '[[ $rc -eq 1 && "$out" == *"$REFUSED_LINE"* ]]'
check "V1b. ... naming the manifest and the feature" '[[ "$out" == *"self/features/$SLUG/README.md"* && "$out" == *"$SLUG"* ]]'
check "V1c. ... and writing nothing" '[[ ! -e "$AT/self/orchestrations/other" && "$(git -C "$AT" status --porcelain)" == "$before" ]]'
git -C "$AT" checkout -q -b scratch-branch
check "V3a. on another branch with another id the manifest does not stand in the way" 'run_as "$AT" "-" orchestration-start.sh --self other --session "$SESSION_U" >/dev/null; [[ -f "$AT/self/orchestrations/other/README.md" ]]'
python3 -B "$AT/analysis/manifest.py" --self "$SLUG" pin-session "$SESSION_T" >/dev/null
git -C "$AT" add -A
git -C "$AT" commit -q -m "pin"
out="$(run_as "$AT" "-" orchestration-start.sh --self second --session "$SESSION_T")"; rc=$?
check "V2a. a manifest whose sessions holds the id refuses, on another branch (got $rc)" '[[ $rc -eq 1 && "$out" == *"$REFUSED_LINE"* && "$out" == *"self/features/$SLUG/README.md"* ]]'
check "V2b. ... and writes nothing" '[[ ! -e "$AT/self/orchestrations/second" ]]'
out="$(run_as "$AT" "-" orchestration-start.sh --self third --session "$SESSION_U")"; rc=$?
check "V3b. another id on another branch proceeds (got $rc)" '[[ $rc -eq 0 && -f "$AT/self/orchestrations/third/README.md" ]]'
# V4 (self/features/orchestration-start-branch-v2/): a manifest directory git would C-quote
# (non-ASCII) is read, not silently skipped — held_feature enumerates with `ls-files -z`
AT="$(container vq)"
assigned "$AT" "$QUOTED_BRANCH"
mkdir -p "$AT/self/features/$QUOTED_SLUG"
manifest_text "$QUOTED_SLUG" "$QUOTED_BRANCH" > "$AT/self/features/$QUOTED_SLUG/README.md"
git -C "$AT" add -A; git -C "$AT" commit -q -m "a manifest whose directory git quotes"
check "V4a. the premise: git C-quotes the manifest's path without -z" \
  '[[ "$(git -C "$AT" ls-files -- "self/features/*/README.md")" == \"* ]]'
out="$(run_as "$AT" "-" orchestration-start.sh --self quoted --session "$SESSION_U")"; rc=$?
check "V4b. that manifest naming the current branch refuses the orchestration, naming it (got $rc)" \
  '[[ $rc -eq 1 && "$out" == *"self/features/$QUOTED_SLUG/README.md"* && ! -e "$AT/self/orchestrations/quoted" ]]'

# ── B. the orchestrator's branch (self/features/orchestration-start-branch-v2/) ──
# Under the cloud profile (run_as pins it) an orchestrator record needs a branch of its own:
# refused on a detached HEAD or main without --branch, cut off origin/main with it.
AT="$(container b)"
git -C "$AT" checkout -q --detach "origin/$BASE"
out="$(run_as "$AT" "-" orchestration-start.sh --self "$BRANCH_SLUG" --session "$SESSION_U")"; rc=$?
check "B1a. on a detached HEAD without --branch the start is refused, naming --branch $CLOUD_PREFIX$BRANCH_SLUG (got $rc)" \
  '[[ $rc -eq 1 && "$out" == *"--branch $CLOUD_PREFIX$BRANCH_SLUG"* ]]'
check "B1b. ... and writes nothing: no record, no ledger line, still detached" \
  '[[ ! -e "$AT/self/orchestrations/$BRANCH_SLUG" && -z "$(git -C "$AT" branch --show-current)" && -z "$(git -C "$AT" status --porcelain)" ]] && ! grep -q "$SESSION_U" "$(git -C "$AT" rev-parse --absolute-git-dir)/agenttooling-orchestrators" 2>/dev/null'
git -C "$AT" checkout -q "$BASE"
out="$(run_as "$AT" "-" orchestration-start.sh --self "$BRANCH_SLUG" --session "$SESSION_U")"; rc=$?
check "B1c. on $BASE without --branch it is refused the same way (got $rc)" \
  '[[ $rc -eq 1 && "$out" == *"--branch $CLOUD_PREFIX$BRANCH_SLUG"* && ! -e "$AT/self/orchestrations/$BRANCH_SLUG" ]]'
out="$( ( cd "$TMP" && env -u CLAUDE_CODE_REMOTE HOME="$FAKE_HOME" AGENTTOOLING_PROFILE=local "$AT/orchestration-start.sh" --self "$BRANCH_SLUG" --session "$SESSION_U" --branch "$CLOUD_PREFIX$BRANCH_SLUG" 2>&1 ) )"; rc=$?
check "B1d. under the local profile --branch is refused, and nothing is written (got $rc)" \
  '[[ $rc -eq 1 && "$out" == *"drop --branch"* && ! -e "$AT/self/orchestrations/$BRANCH_SLUG" ]]'
out="$(run_as "$AT" "-" orchestration-start.sh --self "$BRANCH_SLUG" --session "$SESSION_U" --coordinator --branch "$CLOUD_PREFIX$BRANCH_SLUG")"; rc=$?
check "B1e. --branch with --coordinator is refused (got $rc)" '[[ $rc -eq 1 && ! -e "$AT/self/orchestrations/$BRANCH_SLUG" ]]'
git -C "$AT" checkout -q --detach "origin/$BASE"
out="$(run_as "$AT" "-" orchestration-start.sh --self "$BRANCH_SLUG" --session "$SESSION_U" --branch "$CLOUD_PREFIX$BRANCH_SLUG")"; rc=$?
check "B2a. with --branch the start succeeds and the checkout is on that branch (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$AT" branch --show-current)" == "$CLOUD_PREFIX$BRANCH_SLUG" ]]'
check "B2b. ... cut off origin/$BASE, the record committed on it as its one commit, the record only" \
  '[[ "$(git -C "$AT" rev-parse HEAD~1)" == "$(git -C "$AT" rev-parse "origin/$BASE")" && "$(git -C "$AT" log -1 --format=%s)" == "orchestration $BRANCH_SLUG: start" && "$(git -C "$AT" show --name-only --format= HEAD)" == "self/orchestrations/$BRANCH_SLUG/README.md" && -z "$(git -C "$AT" status --porcelain)" ]]'
check "B2c. ... the record names the session and the ledger holds it" \
  '[[ "$(fence "$AT/self/orchestrations/$BRANCH_SLUG/README.md" "d[\"session\"]")" == "$SESSION_U" ]] && grep -qx "$SESSION_U $BRANCH_SLUG" "$(git -C "$AT" rev-parse --absolute-git-dir)/agenttooling-orchestrators"'
check "B2d. ... and the branch was pushed to origin as a checkpoint" \
  'git -C "$AT" ls-remote --exit-code --heads origin "refs/heads/$CLOUD_PREFIX$BRANCH_SLUG" >/dev/null'
# B3: a clone that fetches only main does not see the branch on origin; ls-remote does
CLONE="$TMP/single/agentTooling"
git clone -q --single-branch --branch "$BASE" "$TMP/b/origin.git" "$CLONE" 2>/dev/null
git -C "$CLONE" checkout -q --detach "origin/$BASE"
check "B3a. the premise: the single-branch clone has no tracking ref for the branch" \
  '! git -C "$CLONE" show-ref --verify --quiet "refs/remotes/origin/$CLOUD_PREFIX$BRANCH_SLUG"'
out="$(run_as "$CLONE" "-" orchestration-start.sh --self other-wave --session "$SESSION_T" --branch "$CLOUD_PREFIX$BRANCH_SLUG")"; rc=$?
check "B3b. a branch that exists on origin is refused in a clone that fetches only $BASE (got $rc)" \
  '[[ $rc -eq 1 && "$out" == *"already exists on origin"* ]]'
check "B3c. ... and nothing is written: no local branch, no record, still detached" \
  '[[ ! -e "$CLONE/self/orchestrations/other-wave" && -z "$(git -C "$CLONE" branch --show-current)" ]] && ! git -C "$CLONE" show-ref --verify --quiet "refs/heads/$CLOUD_PREFIX$BRANCH_SLUG"'
# B4: an origin that cannot be asked refuses
git -C "$CLONE" remote set-url origin "$TMP/nowhere.git"
out="$(run_as "$CLONE" "-" orchestration-start.sh --self other-wave --session "$SESSION_T" --branch "${CLOUD_PREFIX}fresh-name")"; rc=$?
check "B4. an unreachable origin URL refuses ('cannot ask origin') and writes nothing (got $rc)" \
  '[[ $rc -eq 1 && "$out" == *"cannot ask origin"* && ! -e "$CLONE/self/orchestrations/other-wave" && -z "$(git -C "$CLONE" branch --show-current)" ]]'
# B5: a branch a manifest on origin/main names (its directory C-quoted, read with ls-tree -z)
AT="$(container bm)"
mkdir -p "$AT/self/features/$QUOTED_SLUG"
manifest_text "$QUOTED_SLUG" "${CLOUD_PREFIX}merged-feat" > "$AT/self/features/$QUOTED_SLUG/README.md"
git -C "$AT" add -A; git -C "$AT" commit -q -m "a merged feature"; git -C "$AT" push -q origin "$BASE" 2>/dev/null
git -C "$AT" checkout -q --detach "origin/$BASE"
out="$(run_as "$AT" "-" orchestration-start.sh --self "$BRANCH_SLUG" --session "$SESSION_U" --branch "${CLOUD_PREFIX}merged-feat")"; rc=$?
check "B5. a branch a manifest on origin/$BASE names is refused, naming that manifest (got $rc)" \
  '[[ $rc -eq 1 && "$out" == *"self/features/$QUOTED_SLUG/README.md"* && ! -e "$AT/self/orchestrations/$BRANCH_SLUG" && -z "$(git -C "$AT" branch --show-current)" ]]'
# B6: the consumer layout — a vendored copy, the consuming repo's plans/features corpus, and
# the record in its plans/orchestrations
CONS="$TMP/consumer-repo"
mkdir -p "$CONS/plans/features/merged-x"
cp -R "$(container cv)" "$CONS/agentTooling"; rm -rf "$CONS/agentTooling/.git"
manifest_text merged-x "${CLOUD_PREFIX}merged-x" > "$CONS/plans/features/merged-x/README.md"
git init -q "$CONS"; git -C "$CONS" symbolic-ref HEAD "refs/heads/$BASE"
git -C "$CONS" config user.email test@example.invalid; git -C "$CONS" config user.name "orchestrator role test"
git -C "$CONS" add -A; git -C "$CONS" commit -q -m init
git init -q --bare "$TMP/consumer-origin.git"; git -C "$TMP/consumer-origin.git" symbolic-ref HEAD "refs/heads/$BASE"
git -C "$CONS" remote add origin "$TMP/consumer-origin.git"; git -C "$CONS" push -q -u origin "$BASE" 2>/dev/null
git -C "$CONS" checkout -q --detach "origin/$BASE"
out="$(run_as "$CONS/agentTooling" "-" orchestration-start.sh "$BRANCH_SLUG" --session "$SESSION_U")"; rc=$?
check "B6a. vendored, on a detached HEAD without --branch: refused naming --branch $CLOUD_PREFIX$BRANCH_SLUG (got $rc)" \
  '[[ $rc -eq 1 && "$out" == *"--branch $CLOUD_PREFIX$BRANCH_SLUG"* && ! -e "$CONS/plans/orchestrations/$BRANCH_SLUG" ]]'
out="$(run_as "$CONS/agentTooling" "-" orchestration-start.sh "$BRANCH_SLUG" --session "$SESSION_U" --branch "${CLOUD_PREFIX}merged-x")"; rc=$?
check "B6b. vendored: a branch the consuming repo's plans/features manifest names is refused, naming it (got $rc)" \
  '[[ $rc -eq 1 && "$out" == *"plans/features/merged-x/README.md"* && -z "$(git -C "$CONS" branch --show-current)" ]]'
out="$(run_as "$CONS/agentTooling" "-" orchestration-start.sh "$BRANCH_SLUG" --session "$SESSION_U" --branch "$CLOUD_PREFIX$BRANCH_SLUG")"; rc=$?
check "B6c. vendored, with --branch: the record is committed on that branch in plans/orchestrations (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$CONS" branch --show-current)" == "$CLOUD_PREFIX$BRANCH_SLUG" && "$(git -C "$CONS" show --name-only --format= HEAD)" == "plans/orchestrations/$BRANCH_SLUG/README.md" && -z "$(git -C "$CONS" status --porcelain)" ]]'
# B7 (rounds 2–4): --branch takes only claude/<slug> (owner ruling, round 4); anything else is
# refused before any write. `+main` would have been the force-push refspec of main, rewinding
# origin's main to a stale local one (round 2); `origin/main` a local branch shadowing the
# remote-tracking ref (round 3). Origin's refs and the checkout's own are compared whole.
AT="$(container bp)"
git -C "$AT" commit -q --allow-empty -m newer; git -C "$AT" push -q origin "$BASE" 2>/dev/null
git -C "$AT" checkout -q --detach "origin/$BASE"
git -C "$AT" branch -f "$BASE" HEAD~1
ORIGIN_REFS="$(git -C "$AT" ls-remote origin)"
LOCAL_REFS="$(git -C "$AT" for-each-ref --format='%(refname) %(objectname)')"
for bad in "origin/$BASE" "origin/HEAD" "origin/${CLOUD_PREFIX}x" "+$BASE" "$BASE" "${CLOUD_PREFIX}Bad_Name" \
    "+refs/heads/$BASE" "refs/heads/${CLOUD_PREFIX}x" "heads/${CLOUD_PREFIX}x" "${CLOUD_PREFIX}a..b" \
    "${CLOUD_PREFIX}" "${CLOUD_PREFIX}x/y" "x${CLOUD_PREFIX}y"; do
  out="$(run_as "$AT" "-" orchestration-start.sh --self "$BRANCH_SLUG" --session "$SESSION_U" --branch "$bad")"; rc=$?
  check "B7. --branch '$bad' is refused naming --branch ${CLOUD_PREFIX}<slug>; nothing written, origin's and the local refs unchanged (got $rc)" \
    '[[ $rc -eq 1 && "$out" == *"--branch $CLOUD_PREFIX$BRANCH_SLUG"* && ! -e "$AT/self/orchestrations/$BRANCH_SLUG" && -z "$(git -C "$AT" branch --show-current)" && "$(git -C "$AT" ls-remote origin)" == "$ORIGIN_REFS" && "$(git -C "$AT" for-each-ref --format="%(refname) %(objectname)")" == "$LOCAL_REFS" ]]'
done

echo ""
if (( fails )); then
  echo "orchestrator-role: $fails check(s) FAILED"
  exit 1
fi
echo "orchestrator-role: all checks passed"
