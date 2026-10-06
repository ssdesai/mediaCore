#!/usr/bin/env bash
set -uo pipefail

# Self-test for feature-start.sh under the cloud profile — the container is the worktree
# (self/DESIGN-2026-10-05-cloud-execution.md §2), the router is derived from the launch
# branch (§3), and a coordinator's window opens at its own first instant
# (self/features/execution-profiles/README.md, "Rulings taken before the build"). Run by
# self/gate.sh, or by hand: bash self/tests/cloud-start.sh
#
# Each scenario is a fresh "container": a throwaway agentTooling checkout that is a real
# git repo with a bare origin beside it, carrying the real feature-start.sh,
# plan-runner-roots.sh, env-profile.sh, self/open-session.sh and analysis/*.py, a stub
# hook and a stub gate. The profile is forced with AGENTTOOLING_PROFILE and
# CLAUDE_CODE_REMOTE is cleared, so the result is the same on a laptop and in a container.
#
# Asserts, in order:
#   B1. on the base with no --branch the start refuses, naming --branch, and creates
#       nothing: no branch, no feature directory, no commit;
#   A1. on an assigned branch (`claude/…`, at origin/main) the start uses the primary
#       itself — no .worktrees/ — stays on that branch, prints the `profile` line naming
#       AGENTTOOLING_PROFILE, runs the hook in the primary, commits `S: start` there, and
#       writes branches [that branch], profile "cloud", no pin and NO routing record: the
#       session that ran it was launched on the feature's branch, so it is the coordinator;
#   A2. the window opens at that session's first transcript instant EXACTLY, its
#       millisecond fraction kept — before the start ran (the #82 ruling,
#       self/features/session-start-precision: truncated to the millisecond, where it was
#       floored to the second and so earlier than the session);
#   A3. a capture then selects that coordinator by branch, with no set-window-from;
#   A4. report.py shows the profile;
#   A5. a coordinator whose transcript cannot be read gets the clock, with one warning
#       naming set-window-from;
#   A6. the remedy that warning names works (#82): once that coordinator's transcript is
#       there — its first line two hours before the clock-stamped `from`, with a `.500`
#       fraction — `set-window-from "$(manifest.py session-start <id>)" --session <id>`
#       exits 0 and moves `from` to exactly that instant, and a capture then selects the
#       session by branch;
#   G1-G5. the fence's `gate` key (design §7): "green" when the start's gate ran green, and
#       report.py shows it; "skipped" under --no-gate and when the repo has no gate script;
#       and the start hands its gate GATE_RESUME=1 (design §8);
#   S1. a second start in the same container is refused, naming the feature already
#       there, with nothing new written;
#   R1. a branch carrying a commit not on origin/main is refused, the commit still there;
#   R2. a dirty tree is refused, the file still there;
#   R3. a refused start (the hook fails) leaves the branch and a lock; a hand fix in the
#       tree survives the re-run, which resumes at the hook, commits `S: start`, and does
#       not sweep the fix into that commit;
#   N1. --branch from the base: the start checks out that new branch off origin/main, and
#       the session — launched on main — is a router: a routing record is written;
#   N2. ... and a refused --branch start re-run from the branch it made is still the
#       router (the lock remembers where it was launched);
#   N3. an existing branch that is not checked out is refused as --branch;
#   U1. a branch strictly behind origin/main with no commits of its own is fast-forwarded,
#       the run exits 3 with the rerun command and starts nothing; the rerun starts;
#   O1. --open under the cloud runs open-session.sh, which says the session is already in
#       the checkout and runs no osascript;
#   P1. the local profile is unchanged by all this: a .worktrees/<slug> worktree on branch
#       <slug>, profile "local" in the fence and on the `profile` line, gate "skipped"
#       under --no-gate; and --branch under local is refused.
#
# No model, no network. $HOME is a scratch directory for every start and capture, so no
# test reads the machine's own ~/.claude.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cloud-start.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)

BASE="main"
WORKTREES_DIR=".worktrees"
MODEL="claude-sonnet-5"
LOCK_NAME="feature-start.lock"
UPDATED_RC=3
# How far before the start the coordinator's transcript begins, and the sub-second part
# its first instant carries, which the window's `from` must keep (the #82 ruling).
COORDINATOR_HEAD_SECONDS=7200
FIRST_INSTANT_FRACTION=".500"

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects" "$TMP/bin"
# Stub osascript: records that it ran. Under the cloud profile nothing may call it.
OSASCRIPT_OUT="$TMP/osascript-called"
cat > "$TMP/bin/osascript" <<STUB
#!/usr/bin/env bash
touch "$OSASCRIPT_OUT"
STUB
chmod +x "$TMP/bin/osascript"
export PATH="$TMP/bin:$PATH"
export HOOK_CWD_OUT="$TMP/hook-cwd"
export GATE_RESUME_OUT="$TMP/gate-resume"
unset CLAUDE_CODE_SESSION_ID GATE_RESUME

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

fence() {
  python3 -c "import json,re,sys; t=open(sys.argv[1]).read(); m=re.findall(r'\`\`\`json\n(.*?)\n\`\`\`', t, re.S); d=json.loads(m[-1]); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null
}
pj() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }
project_dir() { echo "$FAKE_HOME/.claude/projects/$(echo "$1" | tr '/.' '--')"; }
iso_ago() { python3 -c "import sys,datetime as t; print((t.datetime.now(t.timezone.utc)-t.timedelta(seconds=int(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%S'))" "$1"; }

# container <name> — a fresh checkout at $TMP/<name>/agentTooling on main, its bare origin
# beside it. Prints the checkout's path.
container() {
  local root="$TMP/$1" at origin f
  at="$root/agentTooling"; origin="$root/origin.git"
  mkdir -p "$at/analysis" "$at/self/features" "$at/templates/plans/features"
  for f in feature-start.sh plan-runner-roots.sh env-profile.sh; do
    cp "$HERE/$f" "$at/$f" 2>/dev/null || true
  done
  for f in pricing.py litellm_prices.py rates_history.json roots.py transcript.py capture_planning.py report.py manifest.py routing.py recover_attempts.py; do
    cp "$HERE/analysis/$f" "$at/analysis/$f" 2>/dev/null || true
  done
  cp "$HERE/templates/plans/features/TEMPLATE.md" "$at/templates/plans/features/TEMPLATE.md" 2>/dev/null || true
  cp "$HERE/self/open-session.sh" "$at/self/open-session.sh" 2>/dev/null || true
  printf '#!/usr/bin/env bash\npwd > "${HOOK_CWD_OUT:?}"\nexit "${HOOK_STUB_RC:-0}"\n' > "$at/self/worktree-setup.sh"
  # The stub gate also records the GATE_RESUME it was handed (design §8: the start sets it).
  printf '#!/usr/bin/env bash\nH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\n{ echo "# VERDICT"; echo "all checks passed"; } > "$H/self/gate-report.txt"\necho "${GATE_RESUME:-unset}" > "${GATE_RESUME_OUT:?}"\n' > "$at/self/gate.sh"
  # No .claude/ at all: the checkout's policy is tracked (self-cloud-bootstrap), so a
  # --self start generates nothing and needs no generator in this fixture.
  printf 'self/gate-report*.txt\n' > "$at/.gitignore"
  chmod +x "$at"/*.sh "$at/self/"*.sh 2>/dev/null || true
  git init -q "$at"
  git -C "$at" symbolic-ref HEAD "refs/heads/$BASE"
  git -C "$at" config user.email test@example.invalid
  git -C "$at" config user.name "cloud start test"
  git -C "$at" add -A
  git -C "$at" commit -q -m init
  git init -q --bare "$origin"
  git -C "$origin" symbolic-ref HEAD "refs/heads/$BASE"
  git -C "$at" remote add origin "$origin"
  git -C "$at" push -q -u origin "$BASE" 2>/dev/null
  echo "$at"
}
# assigned <checkout> <branch> — the container's session branch, cut at origin/main, as a
# cloud session finds itself on before any start.
assigned() { git -C "$1" checkout -q -b "$2" "origin/$BASE"; }
# transcript <checkout> <session> <branch> — a coordinator's transcript, launched in the
# checkout on that branch, its first line COORDINATOR_HEAD_SECONDS before now.
transcript() {
  local dir first
  dir="$(project_dir "$1")"; mkdir -p "$dir"
  first="$(iso_ago "$COORDINATOR_HEAD_SECONDS")"
  FIRST_INSTANT="$first$FIRST_INSTANT_FRACTION""Z"
  session_line "$2" "$1" "$3" "msg-$2-1" "$MODEL" "$FIRST_INSTANT" 100 3000 0 0 0 > "$dir/$2.jsonl"
  session_line "$2" "$1" "$3" "msg-$2-2" "$MODEL" "$(iso_ago 60).000Z" 100 3000 0 0 0 >> "$dir/$2.jsonl"
}
# cstart <checkout> [session-id] -- <args> — that checkout's start under the cloud profile.
cstart() {
  local at="$1" sid="$2"; shift 2
  if [[ -n "$sid" ]]; then
    ( cd "$TMP" && env -u CLAUDE_CODE_REMOTE HOME="$FAKE_HOME" AGENTTOOLING_PROFILE=cloud CLAUDE_CODE_SESSION_ID="$sid" "$at/feature-start.sh" --self "$@" 2>&1 )
  else
    ( cd "$TMP" && env -u CLAUDE_CODE_REMOTE -u CLAUDE_CODE_SESSION_ID HOME="$FAKE_HOME" AGENTTOOLING_PROFILE=cloud "$at/feature-start.sh" --self "$@" 2>&1 )
  fi
}
heads() { git -C "$1" for-each-ref --format='%(refname)' refs/heads | sort | tr '\n' ' '; }

echo "cloud-start"

# ── B1. on the base, no --branch ──────────────────────────────────────────────
AT="$(container b1)"
heads_before="$(heads "$AT")"; head_before="$(git -C "$AT" rev-parse HEAD)"
out="$(cstart "$AT" "" cs-base --no-gate)"; rc=$?
check "B1a. on $BASE with no --branch the start refuses (got $rc)" '[[ $rc -eq 1 ]] && grep -q "refused" <<<"$out"'
check "B1b. ... naming the --branch flag" 'grep -qF -- "--branch" <<<"$out"'
check "B1c. ... and creates nothing: no branch, no feature directory, no commit" \
  '[[ "$(heads "$AT")" == "$heads_before" && "$(git -C "$AT" rev-parse HEAD)" == "$head_before" && ! -e "$AT/self/features/cs-base" ]]'

# ── A. a start on the assigned branch: the session is the coordinator ─────────
AT="$(container a1)"
BR="claude/cs-one-x1"
SID="c0c0c0c0-0000-0000-0000-000000000001"
assigned "$AT" "$BR"
transcript "$AT" "$SID" "$BR"
FD="$AT/self/features/cs-one"
out="$(cstart "$AT" "$SID" cs-one --method direct)"; rc=$?
check "A1a. the start on $BR exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "A1b. it prints the profile line naming the variable that decided it" \
  'grep -qE "^  profile +cloud \(AGENTTOOLING_PROFILE=cloud\)" <<<"$out"'
check "A1c. the primary itself is the checkout: no $WORKTREES_DIR/, still on $BR" \
  '[[ ! -e "$AT/$WORKTREES_DIR" && "$(git -C "$AT" branch --show-current)" == "$BR" ]]'
check "A1d. the hook ran in the primary" '[[ "$(cat "$HOOK_CWD_OUT" 2>/dev/null)" == "$AT" ]]'
check "A1e. 'cs-one: start' is committed on $BR, directly on origin/$BASE" \
  '[[ "$(git -C "$AT" log -1 --format=%s)" == "cs-one: start" && "$(git -C "$AT" rev-parse HEAD~1)" == "$(git -C "$AT" rev-parse "origin/$BASE")" ]]'
check "A1f. the fence names branches [$BR], base $BASE and profile cloud" \
  '[[ "$(fence "$FD/README.md" "\",\".join(d[\"branches\"])")" == "$BR" && "$(fence "$FD/README.md" "d[\"base\"]")" == "$BASE" && "$(fence "$FD/README.md" "d[\"profile\"]")" == cloud ]]'
check "A1g. no pin, and no routing record: launched on the feature's branch, it is the coordinator" \
  '[[ "$(fence "$FD/README.md" "d[\"sessions\"]")" == "[]" && ! -e "$FD/routing.json" ]] && grep -qi "coordinator" <<<"$out"'
check "A1h. no start lock is left behind" '[[ ! -e "$AT/.git/$LOCK_NAME" ]]'
# A2 expected the floor to the whole second until #82: the floor is earlier than the session,
# so set-window-from refused it. The ruling (self/features/session-start-precision) is the
# instant itself, truncated to the millisecond — which for this transcript is exact.
check "A2. session_window.from is the coordinator's first instant, exactly ($FIRST_INSTANT; got $(fence "$FD/README.md" "d[\"session_window\"][\"from\"]"))" \
  '[[ "$(fence "$FD/README.md" "d[\"session_window\"][\"from\"]")" == "$FIRST_INSTANT" ]]'
outc="$(cd "$TMP" && HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self cs-one 2>&1)"; rcc=$?
check "A3a. a capture of cs-one exits 0 (got $rcc)" '[[ $rcc -eq 0 && -f "$FD/planning.json" ]]'
check "A3b. ... and selects the coordinator by branch, with no set-window-from" \
  '[[ "$(pj "$FD/planning.json" "\",\".join(s.get(\"selected_by\", \"\") for s in d[\"sessions\"] if s[\"session_id\"] == \"$SID\")")" == branch ]]'
outr="$(cd "$TMP" && HOME="$FAKE_HOME" python3 "$AT/analysis/report.py" --self cs-one 2>&1)"
check "A4. report.py shows the profile" 'grep -q "^Profile: cloud" "$FD/report.md" && [[ "$(pj "$FD/report.json" "d[\"profile\"]")" == cloud ]]'
# ── G. the `gate` key (design §7) and GATE_RESUME (design §8) ────────────────────
check "G1. a start whose gate ran green records gate \"green\" in the fence" \
  '[[ "$(fence "$FD/README.md" "d[\"gate\"]")" == green ]]'
check "G2. ... and ran that gate with GATE_RESUME=1 (got $(cat "$GATE_RESUME_OUT" 2>/dev/null))" \
  '[[ "$(cat "$GATE_RESUME_OUT" 2>/dev/null)" == 1 ]]'
check "G3. report.py shows the gate beside the profile" \
  'grep -q "^Gate: green" "$FD/report.md" && [[ "$(pj "$FD/report.json" "d[\"gate\"]")" == green ]]'

AT="$(container a5)"
BR="claude/cs-clock-x5"
CLOCK_SID="c0c0c0c0-0000-0000-0000-00000000000f"
assigned "$AT" "$BR"
before="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
out="$(cstart "$AT" "$CLOCK_SID" cs-clock --no-gate)"; rc=$?
from="$(fence "$AT/self/features/cs-clock/README.md" "d[\"session_window\"][\"from\"]")"
check "A5a. a coordinator with no readable transcript still starts (got $rc)" '[[ $rc -eq 0 ]]'
check "A5b. ... its from is the clock ($from >= $before)" '[[ -n "$from" && ! "$from" < "$before" ]]'
check "A5c. ... with exactly one warning naming set-window-from" \
  '[[ "$(grep -c "^  warn" <<<"$out")" == 1 ]] && grep "^  warn" <<<"$out" | grep -qF "set-window-from"'
check "G4. a start under --no-gate records gate \"skipped\"" \
  '[[ "$(fence "$AT/self/features/cs-clock/README.md" "d[\"gate\"]")" == skipped ]]'

# A6 (#82): the remedy A5c's warning names. The transcript the start could not read is now
# there, its first line hours before the clock-stamped `from`, with a sub-second fraction:
# the refusal path set-window-from took on main, where session-start printed the floor —
# earlier than the session's first line — and the refusal turned it away.
transcript "$AT" "$CLOCK_SID" "$BR"
start_out="$(cd "$TMP" && HOME="$FAKE_HOME" python3 "$AT/analysis/manifest.py" --self cs-clock session-start "$CLOCK_SID" 2>&1)"
out6="$(cd "$TMP" && HOME="$FAKE_HOME" python3 "$AT/analysis/manifest.py" --self cs-clock set-window-from "$start_out" --session "$CLOCK_SID" 2>&1)"; rc6=$?
from6="$(fence "$AT/self/features/cs-clock/README.md" "d[\"session_window\"][\"from\"]")"
check "A6a. set-window-from given session-start's output ($start_out) exits 0 (got $rc6: $out6)" '[[ $rc6 -eq 0 ]]'
check "A6b. ... and moves from back to the session's first instant exactly ($FIRST_INSTANT; got $from6)" \
  '[[ "$from6" == "$FIRST_INSTANT" ]]'
outc6="$(cd "$TMP" && HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self cs-clock 2>&1)"; rcc6=$?
check "A6c. a capture of cs-clock then selects that session by branch (got $rcc6)" \
  '[[ $rcc6 -eq 0 && "$(pj "$AT/self/features/cs-clock/planning.json" "\",\".join(s.get(\"selected_by\", \"\") for s in d[\"sessions\"] if s[\"session_id\"] == \"$CLOCK_SID\")")" == branch ]]'

# A repo with no gate script ran no gate either: the start says so and records skipped,
# never green — a feature started on an unverified base says so in its record.
AT="$(container g5)"
git -C "$AT" rm -q self/gate.sh
git -C "$AT" commit -q -m "no gate"
git -C "$AT" push -q origin "$BASE" 2>/dev/null
assigned "$AT" "claude/cs-nogate-g5"
out="$(cstart "$AT" "" cs-nogate)"; rc=$?
check "G5. a start with no gate script records gate \"skipped\" (got $rc)" \
  '[[ $rc -eq 0 && "$(fence "$AT/self/features/cs-nogate/README.md" "d[\"gate\"]")" == skipped ]]'

# ── S1. a second feature in the same container ───────────────────────────────
AT="$TMP/a1/agentTooling"
heads_before="$(heads "$AT")"; head_before="$(git -C "$AT" rev-parse HEAD)"
out="$(cstart "$AT" "" cs-two --no-gate)"; rc=$?
check "S1a. a second start on a branch that carries cs-one is refused (got $rc)" '[[ $rc -eq 1 ]]'
check "S1b. ... naming cs-one" 'grep -qF "cs-one" <<<"$out"'
check "S1c. ... writing nothing" \
  '[[ "$(heads "$AT")" == "$heads_before" && "$(git -C "$AT" rev-parse HEAD)" == "$head_before" && ! -e "$AT/self/features/cs-two" ]]'

# ── R. somebody's work is refused ─────────────────────────────────────────────
AT="$(container r1)"
assigned "$AT" "claude/cs-foreign"
echo "somebody's work" > "$AT/work.txt"
git -C "$AT" add work.txt
git -C "$AT" commit -q -m "somebody's commit"
work_sha="$(git -C "$AT" rev-parse HEAD)"
out="$(cstart "$AT" "" cs-foreign --no-gate)"; rc=$?
check "R1a. a branch with a commit not on origin/$BASE is refused (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -qF "origin/$BASE" <<<"$out"'
check "R1b. ... the commit still there and nothing started" \
  '[[ "$(git -C "$AT" rev-parse HEAD)" == "$work_sha" && ! -e "$AT/self/features/cs-foreign" ]]'

AT="$(container r2)"
assigned "$AT" "claude/cs-dirty"
echo "uncommitted" > "$AT/dirty.txt"
out="$(cstart "$AT" "" cs-dirty --no-gate)"; rc=$?
check "R2a. a dirty tree is refused (got $rc)" '[[ $rc -eq 1 ]] && grep -qF "dirty.txt" <<<"$out"'
check "R2b. ... the file still there and nothing started" \
  '[[ -f "$AT/dirty.txt" && ! -e "$AT/self/features/cs-dirty" && "$(git -C "$AT" rev-parse HEAD)" == "$(git -C "$AT" rev-parse "origin/$BASE")" ]]'

AT="$(container r3)"
assigned "$AT" "claude/cs-resume"
out="$(HOOK_STUB_RC=1 cstart "$AT" "" cs-resume --no-gate)"; rc=$?
check "R3a. a start whose hook fails is refused (got $rc)" '[[ $rc -eq 1 ]]'
check "R3b. ... leaving the branch checked out and a lock recording the refusal" \
  '[[ "$(git -C "$AT" branch --show-current)" == claude/cs-resume ]] && grep -q "^refused=" "$AT/.git/$LOCK_NAME" 2>/dev/null'
echo "the hand fix" > "$AT/hand-fix.txt"
out="$(cstart "$AT" "" cs-resume --no-gate)"; rc=$?
check "R3c. the re-run, with a hand fix in the tree, resumes and starts (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$AT" log -1 --format=%s)" == "cs-resume: start" ]] && grep -qi "resum" <<<"$out"'
check "R3d. ... the hand fix survives, uncommitted, outside the start commit" \
  '[[ "$(cat "$AT/hand-fix.txt" 2>/dev/null)" == "the hand fix" ]] && ! git -C "$AT" show --name-only --format= HEAD | grep -qF "hand-fix.txt"'
check "R3e. ... and the lock is gone" '[[ ! -e "$AT/.git/$LOCK_NAME" ]]'

# ── N. --branch from the base: a router ───────────────────────────────────────
AT="$(container n1)"
RSID="d0d0d0d0-0000-0000-0000-000000000001"
out="$(cstart "$AT" "$RSID" cs-named --branch claude/cs-named-n1 --no-gate)"; rc=$?
NFD="$AT/self/features/cs-named"
check "N1a. --branch from $BASE starts, on the new branch off origin/$BASE (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$AT" branch --show-current)" == claude/cs-named-n1 && "$(git -C "$AT" rev-parse HEAD~1)" == "$(git -C "$AT" rev-parse "origin/$BASE")" ]]'
check "N1b. ... branches [claude/cs-named-n1] in the fence" \
  '[[ "$(fence "$NFD/README.md" "d[\"branches\"][0]")" == claude/cs-named-n1 ]]'
check "N1c. ... and the session, launched on $BASE, is a router: a routing record, no pin" \
  '[[ -f "$NFD/routing.json" && "$(fence "$NFD/README.md" "d[\"sessions\"]")" == "[]" ]]'

AT="$(container n2)"
out="$(HOOK_STUB_RC=1 cstart "$AT" "$RSID" cs-later --branch claude/cs-later-n2 --no-gate)"; rc=$?
out="$(cstart "$AT" "$RSID" cs-later --branch claude/cs-later-n2 --no-gate)"; rc2=$?
check "N2. a refused --branch start re-run from its branch is still the router (got $rc then $rc2)" \
  '[[ $rc -eq 1 && $rc2 -eq 0 && -f "$AT/self/features/cs-later/routing.json" ]]'

AT="$(container n3)"
git -C "$AT" branch claude/already-there
out="$(cstart "$AT" "" cs-exists --branch claude/already-there --no-gate)"; rc=$?
check "N3. an existing branch that is not checked out is refused as --branch (got $rc)" \
  '[[ $rc -eq 1 && "$(git -C "$AT" branch --show-current)" == "$BASE" && ! -e "$AT/self/features/cs-exists" ]]'

# ── U1. a checkout behind origin/<base> is fast-forwarded, then rerun ─────────
AT="$(container u1)"
assigned "$AT" "claude/cs-behind"
old_head="$(git -C "$AT" rev-parse HEAD)"
UPSTREAM="$TMP/u1/upstream"
git clone -q "$TMP/u1/origin.git" "$UPSTREAM" 2>/dev/null
git -C "$UPSTREAM" config user.email test@example.invalid
git -C "$UPSTREAM" config user.name "cloud start test"
echo "newer" > "$UPSTREAM/newer.txt"
git -C "$UPSTREAM" add newer.txt
git -C "$UPSTREAM" commit -q -m "newer base"
git -C "$UPSTREAM" push -q origin "$BASE" 2>/dev/null
out="$(cstart "$AT" "" cs-behind --no-gate)"; rc=$?
check "U1a. a checkout behind origin/$BASE exits $UPDATED_RC (got $rc)" '[[ $rc -eq $UPDATED_RC ]]'
check "U1b. ... fast-forwarded to origin/$BASE, nothing started, the rerun command printed" \
  '[[ "$(git -C "$AT" rev-parse HEAD)" == "$(git -C "$AT" rev-parse "origin/$BASE")" && "$(git -C "$AT" rev-parse HEAD)" != "$old_head" && ! -e "$AT/self/features/cs-behind" ]] && grep -qF "feature-start.sh" <<<"$out"'
out="$(cstart "$AT" "" cs-behind --no-gate)"; rc=$?
check "U1c. the rerun starts (got $rc)" '[[ $rc -eq 0 && "$(git -C "$AT" log -1 --format=%s)" == "cs-behind: start" ]]'

# ── O1. --open in the cloud ───────────────────────────────────────────────────
AT="$(container o1)"
assigned "$AT" "claude/cs-open"
rm -f "$OSASCRIPT_OUT"
out="$(cstart "$AT" "" cs-open --no-gate --open)"; rc=$?
check "O1. --open says the session is already in the checkout, and runs no osascript (got $rc)" \
  '[[ $rc -eq 0 && ! -e "$OSASCRIPT_OUT" ]] && grep -qi "already in" <<<"$out"'

# ── P1. the local profile is what it was ──────────────────────────────────────
AT="$(container p1)"
out="$( cd "$TMP" && env -u CLAUDE_CODE_REMOTE -u CLAUDE_CODE_SESSION_ID HOME="$FAKE_HOME" AGENTTOOLING_PROFILE=local "$AT/feature-start.sh" --self cs-local --no-gate 2>&1 )"; rc=$?
check "P1a. a local start makes $WORKTREES_DIR/cs-local on branch cs-local (got $rc)" \
  '[[ $rc -eq 0 && "$(git -C "$AT/$WORKTREES_DIR/cs-local" branch --show-current 2>/dev/null)" == cs-local && "$(git -C "$AT" branch --show-current)" == "$BASE" ]]'
check "P1b. ... with profile local in the fence and on the profile line" \
  '[[ "$(fence "$AT/$WORKTREES_DIR/cs-local/self/features/cs-local/README.md" "d[\"profile\"]")" == local ]] && grep -qE "^  profile +local \(AGENTTOOLING_PROFILE=local\)" <<<"$out"'
check "P1d. ... and gate \"skipped\" under --no-gate, as in the cloud" \
  '[[ "$(fence "$AT/$WORKTREES_DIR/cs-local/self/features/cs-local/README.md" "d[\"gate\"]")" == skipped ]]'
out="$( cd "$TMP" && env -u CLAUDE_CODE_REMOTE -u CLAUDE_CODE_SESSION_ID HOME="$FAKE_HOME" AGENTTOOLING_PROFILE=local "$AT/feature-start.sh" --self cs-local-two --branch claude/x --no-gate 2>&1 )"; rc=$?
check "P1c. --branch under local is refused, creating nothing (got $rc)" \
  '[[ $rc -eq 1 && ! -e "$AT/$WORKTREES_DIR/cs-local-two" ]] && ! git -C "$AT" show-ref --verify --quiet refs/heads/claude/x'

echo
if (( fails > 0 )); then echo "cloud-start: $fails assertion(s) FAILED"; exit 1; fi
echo "cloud-start: all assertions passed"
