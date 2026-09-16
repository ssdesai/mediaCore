#!/usr/bin/env bash
set -uo pipefail

# Self-test for the session-share arithmetic — a session claimed by more than one
# feature is priced and timed by *concurrent share* instead of counted in full by every
# claimant. Run by self/gate.sh, or by hand: bash self/tests/session-share.sh
#
# Same scaffolding as capture-guard.sh — copies of `analysis/{pricing,roots,transcript,
# capture_planning}.py` into a throwaway agentTooling checkout under mktemp -d, and,
# under a redirected $HOME, the `~/.claude/projects/*/<session_id>.jsonl` transcripts
# capture reads. No model, no network.
#
# The rule under test: for each response in a claimed session, every claimant whose
# manifest window covers that response's timestamp owns an equal share of it; a response
# before every claimant's `from` goes to the earliest claimant alone; a response after
# every claimant's `to` is unclaimed. Cost and duration are both partitioned this way —
# duration over the timeline `[first line, last line]`, cost over each response's tokens.
# `started_at`/`ended_at` stay the session's own bounds throughout; only `duration_s` (and
# the analogous `cost_usd.total`) is apportioned. A session with exactly one claimant is
# untouched — no share fields appear at all, and it is priced and timed exactly as it
# always was.
#
# Asserts, in order:
#   1. the four shares plus the unclaimed remainder equal the session's own cost — the
#      assertion the whole feature exists for;
#   2. each of the four features' cost_usd.total matches its predicted token-ratio share;
#   3. the earliest claimant alone owns the response before every window opens (the
#      "head"): its total strictly exceeds what its share would be without that response,
#      and the other three carry none of it;
#   4. `share_basis` on the earliest claimant's entry names all four claimants — itself
#      first with source "self", the other three with source "manifest" and their own
#      manifests' from/to;
#   5. duration_s is apportioned by the same rule, session_duration_s is the session's
#      whole span on every entry, the four apportioned spans plus the unclaimed remainder
#      sum to that whole span, and started_at/ended_at stay the session's own first and
#      last instants throughout;
#   6. a session with a single claimant carries none of the share fields at all, and is
#      priced and timed exactly as an unshared session always was;
#   7. a response whose several lines straddle a claim boundary (the same API response
#      written across two timestamps, in two different ownership stretches) is still
#      billed once and to the owners of its *first* line — the sum invariant from (1)
#      still holds, and the two boundary features' totals are unchanged from (2), which
#      is false both for a walk that buckets by window and for one that dates a response
#      by its last line;
#   8. the unclaimed remainder is reported on stdout, naming the session, and
#      unclaimed_usd is exactly that remainder's own share of the session cost;
#   9. a fifth claimant whose own window is empty (`from` later than `to`) owns nothing —
#      not even the head stretch its early `from` would otherwise win it — the other four
#      shares are unchanged by its arrival, and the sum invariant still holds;
#  10. the same defect from its other side: an empty window opening *before* the session's
#      first response must not strand the head in the unclaimed remainder either;
#  11. and its costliest shape: an empty claim on a session with one real claimant must not
#      be counted as a claimant at all, or the unshared path is lost and a whole feature's
#      session is silently sliced;
#  12. a SINGLE-claimant session that outruns its window says how much lies outside it —
#      the `may span the window boundary` warning names the dollars and the seconds at or
#      after `to` and that they are counted in full, while the same warning on the share
#      path says they are not counted. Prose only: `cost_usd.total` is unchanged, which is
#      what phase 6 pins from the other side;
#  13. a claimant whose `to` is moved EARLIER loses the responses past it —
#      `manifest.py set-window-to --tighten` is the repair path for a bound already
#      written, and the sum invariant from (1) survives it;
#  14. and the same warning as (12) discloses no quantity when there is none to disclose:
#      a session whose only line past `to` is an unbilled user line, under a second out,
#      keeps the qualitative sentence and says no billable response falls past `to`
#      rather than printing `$0.0000 and 0s`.
#  15. the opening stretch the earliest claimant is paid is BOUNDED by that claimant's own
#      window length: on a fresh session, `head-a` (10:00-11:00, one hour) is paid the
#      response 30 minutes before its `from` and NOT the one two hours before it, which
#      falls to the unclaimed remainder in both dollars and seconds; the warning names
#      that head's dollars and seconds apart from the rest of the remainder and names the
#      remedies for it (pin the session; move `from` back by hand, there being no
#      `set-window-to` for `from`); and an earliest claimant whose `to` is still null
#      keeps the unbounded head, since a window with no end has no length to bound by —
#      and the seconds follow the dollars there, 16200 to `head-a` and 1800 to `head-b`
#      with nothing unclaimed, on the one path that adds no cut point;
#  16. a remainder that is ALL head names no rest: two claimants whose windows chain end
#      to end over everything after the earliest `from` leave only the opening stretch
#      unowned, and the warning then drops the "and $0.0000 (0s) is the rest" clause and
#      the "For the rest" sentence rather than offering a remedy for nothing;
#  17. and the bound's edge is inclusive — a response landing exactly ON `head_bound` is
#      paid to the earliest claimant, in its cost_usd.total and in the `[bound, from)`
#      segment of its duration_s. Ruling 1 is `<=`; nothing else pins which side of the
#      edge the instant falls on.
#
# Phases 1-5 and 7-8 are RED until analysis/capture_planning.py learns to share a
# multiply-claimed session — a run against today's code is expected to FAIL them, not
# crash. Phase 6 is GREEN today and must stay green: it is the no-change half of the
# contract, pinning that an unshared session is never touched by this feature.
#
# In phase 15, 15a, 15b, 15d and 15e were RED against the unbounded fallback (the
# `capture_planning.py` on `main` before `bounded-opening-stretch`), which pays `head-a`
# the 08:00 response and 08:00-11:00 of the span. 15c and 15f are GREEN on both sides and
# are the guard: the bound must move nothing on a later claimant and nothing at all while
# the earliest claimant is still in flight. Phase 3 is the same guard on the dollars —
# `share-a`'s eight-hour window still reaches its head response two hours out.
#
# Of the rework's checks (the review's four escalations), 16c and 16d were RED against the
# first build's warning, which always emitted both halves of the sentence pair; 17a, 17b
# and 17c are red only under a mutation, since the code was already right — flip either
# `moment < bound` to `<=` and all three move. 8c, 15f-duration*, 16a, 16b and 16e are
# guards, green before and after, and 16a is what keeps 16c/16d from passing vacuously on
# a session that simply has no head.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Physical path, not the symlinked one — see capture-guard.sh for why: roots.py resolves
# AGENT_TOOLING_DIR with Path.resolve(), so on macOS an unresolved /var/... fixture path
# matches no transcript and every assertion below passes or fails vacuously.
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

for f in pricing.py roots.py transcript.py capture_planning.py manifest.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done

# session_root() walks up for the nearest ancestor holding .git; without one it would
# escape the sandbox and resolve to a real repo above /tmp.
mkdir -p "$AT/.git"

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# field PLANNING_JSON PY_EXPR — evaluates PY_EXPR against `d`, the parsed planning.json.
# Errors (a missing key, most often — the RED state before the share walk exists) are
# swallowed and read back as an empty string, so a check against them fails cleanly
# instead of crashing this script.
field() {
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null
}

# close_enough A B — true (exit 0) when the two floats differ by less than 1e-9.
close_enough() {
  python3 -c "import sys; a=float(sys.argv[1]); b=float(sys.argv[2]); sys.exit(0 if abs(a - b) < 1e-9 else 1)" \
    "$1" "$2" 2>/dev/null
}

echo "session share arithmetic"

SESSION="11111111-0000-0000-0000-000000000001"
SESSION_SOLO="22222222-0000-0000-0000-000000000002"
MODEL="claude-sonnet-5"
BRANCH="unclaimedBranch"        # in no manifest's `branches`: selection is by pin alone
MANIFEST_BRANCH="pinnedOnlyBranch"  # every pinning manifest's own declared branch — matches no transcript

FAKE_HOME="$TMP/home"
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/.' '--')"
mkdir -p "$PROJECTS"

# write_manifest SLUG FROM TO SESSION_ID — the feature README whose last ```json fence
# capture reads. `branches` names a branch no transcript carries, so SESSION_ID's pin in
# `sessions` is the only route in.
# A `to` of the literal string `null` is written as the JSON null a manifest carries while
# its feature is still in flight — `feature-close.sh` stamps a real bound at close. Phase
# 15f needs one; every other caller passes an instant.
write_manifest() {
  local slug="$1" frm="$2" to="$3" session_id="$4"
  local to_json="\"$to\""
  if [ "$to" = null ]; then to_json=null; fi
  local dir="$AT/self/features/$slug"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<EOF
# $slug

Fixture feature for self/tests/session-share.sh.

\`\`\`json
{
  "slug": "$slug",
  "branches": ["$MANIFEST_BRANCH"],
  "session_window": {"from": "$frm", "to": $to_json},
  "sessions": ["$session_id"],
  "exclude_sessions": []
}
\`\`\`
EOF
}

capture()   { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self "$1" 2>&1; }
recapture() { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self "$1" --recapture 2>&1; }

PLANNING_A="$AT/self/features/share-a/planning.json"
PLANNING_B="$AT/self/features/share-b/planning.json"
PLANNING_C="$AT/self/features/share-c/planning.json"
PLANNING_D="$AT/self/features/share-d/planning.json"
PLANNING_SOLO="$AT/self/features/share-solo/planning.json"

# ── the fixture: one session, six responses, all input/cache-read/cache-creation 0 so
# cost is proportional to output tokens alone ──────────────────────────────────────────
{
  session_line "$SESSION" "$AT" "$BRANCH" "r0" "$MODEL" "2026-06-01T08:00:00.000Z" 0 1000 0 0 0
  session_line "$SESSION" "$AT" "$BRANCH" "r1" "$MODEL" "2026-06-01T10:30:00.000Z" 0 2000 0 0 0
  session_line "$SESSION" "$AT" "$BRANCH" "r2" "$MODEL" "2026-06-01T12:30:00.000Z" 0 4000 0 0 0
  session_line "$SESSION" "$AT" "$BRANCH" "r3" "$MODEL" "2026-06-01T14:30:00.000Z" 0 6000 0 0 0
  session_line "$SESSION" "$AT" "$BRANCH" "r4" "$MODEL" "2026-06-01T16:30:00.000Z" 0 12000 0 0 0
  session_line "$SESSION" "$AT" "$BRANCH" "r5" "$MODEL" "2026-06-01T20:30:00.000Z" 0 800 0 0 0
} > "$PROJECTS/$SESSION.jsonl"

# share-solo's own session, claimed by nobody else.
session_line "$SESSION_SOLO" "$AT" "$BRANCH" "s0" "$MODEL" "2026-06-01T09:00:00.000Z" 0 500 0 0 0 \
  > "$PROJECTS/$SESSION_SOLO.jsonl"

write_manifest share-a "2026-06-01T10:00:00Z" "2026-06-01T18:00:00Z" "$SESSION"
write_manifest share-b "2026-06-01T12:00:00Z" "2026-06-01T18:00:00Z" "$SESSION"
write_manifest share-c "2026-06-01T14:00:00Z" "2026-06-01T18:00:00Z" "$SESSION"
write_manifest share-d "2026-06-01T16:00:00Z" "2026-06-01T18:00:00Z" "$SESSION"
write_manifest share-solo "2026-06-01T00:00:00Z" "2026-06-01T23:59:59Z" "$SESSION_SOLO"

# Capture in order a, b, c, d, then re-capture a so its record sees the other three
# claims — a claimant not yet captured is still found through its manifest alone, and
# phase 4 is what pins that.
capture share-a   > "$TMP/capture-a.txt"
capture share-b   > "$TMP/capture-b.txt"
capture share-c   > "$TMP/capture-c.txt"
capture share-d   > "$TMP/capture-d.txt"
recapture share-a > "$TMP/capture-a2.txt"

# ── 1. the four shares plus the unclaimed remainder equal the session's own cost ──────
cost_a="$(field "$PLANNING_A" "d['cost_usd']['total']")"
cost_b="$(field "$PLANNING_B" "d['cost_usd']['total']")"
cost_c="$(field "$PLANNING_C" "d['cost_usd']['total']")"
cost_d="$(field "$PLANNING_D" "d['cost_usd']['total']")"
session_cost="$(field "$PLANNING_A" "d['sessions'][0]['session_cost_usd']")"
unclaimed="$(field "$PLANNING_A" "d['sessions'][0]['unclaimed_usd']")"
shares_sum="$(python3 -c "print(float('$cost_a')+float('$cost_b')+float('$cost_c')+float('$cost_d')+float('$unclaimed'))" 2>/dev/null)"
check "1. the four shares plus the unclaimed remainder equal the session's own cost" \
  "close_enough '$shares_sum' '$session_cost'"

# ── 2. each share is the predicted one ─────────────────────────────────────────────────
exp_a="$(python3 -c "print(10000/25800*float('$session_cost'))" 2>/dev/null)"
exp_b="$(python3 -c "print(7000/25800*float('$session_cost'))" 2>/dev/null)"
exp_c="$(python3 -c "print(5000/25800*float('$session_cost'))" 2>/dev/null)"
exp_d="$(python3 -c "print(3000/25800*float('$session_cost'))" 2>/dev/null)"
check "2a. share-a's total is its predicted share (10000/25800 of session cost)" "close_enough '$cost_a' '$exp_a'"
check "2b. share-b's total is its predicted share (7000/25800 of session cost)" "close_enough '$cost_b' '$exp_b'"
check "2c. share-c's total is its predicted share (5000/25800 of session cost)" "close_enough '$cost_c' '$exp_c'"
check "2d. share-d's total is its predicted share (3000/25800 of session cost)" "close_enough '$cost_d' '$exp_d'"

# ── 3. the head belongs to the earliest claimant ───────────────────────────────────────
without_r0_a="$(python3 -c "print(9000/25800*float('$session_cost'))" 2>/dev/null)"
check "3a. share-a's total strictly exceeds what its share would be without r0 (the head)" \
  "python3 -c \"import sys; sys.exit(0 if float('$cost_a') > float('$without_r0_a') else 1)\" 2>/dev/null"
check "3b. share-b carries no part of r0 (matches its own ratio exactly)" "close_enough '$cost_b' '$exp_b'"
check "3c. share-c carries no part of r0 (matches its own ratio exactly)" "close_enough '$cost_c' '$exp_c'"
check "3d. share-d carries no part of r0 (matches its own ratio exactly)" "close_enough '$cost_d' '$exp_d'"

# ── 4. share_basis names every claimant, this feature first, with its source ──────────
src_a="$(field "$PLANNING_A" "next(e['source'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-a')")"
src_b="$(field "$PLANNING_A" "next(e['source'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-b')")"
src_c="$(field "$PLANNING_A" "next(e['source'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-c')")"
src_d="$(field "$PLANNING_A" "next(e['source'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-d')")"
check "4a. share-a's own claim in its share_basis has source 'self'" "[ \"$src_a\" = self ]"
check "4b. share-b's claim in share-a's share_basis has source 'manifest'" "[ \"$src_b\" = manifest ]"
check "4c. share-c's claim in share-a's share_basis has source 'manifest'" "[ \"$src_c\" = manifest ]"
check "4d. share-d's claim in share-a's share_basis has source 'manifest'" "[ \"$src_d\" = manifest ]"

basis_set_ok="$(field "$PLANNING_A" "sorted(e['feature'] for e in d['sessions'][0]['share_basis']) == ['agentTooling/share-a','agentTooling/share-b','agentTooling/share-c','agentTooling/share-d']")"
check "4e. share_basis names exactly the four claimants (as a set, order not asserted)" "[ \"$basis_set_ok\" = True ]"

from_a="$(field "$PLANNING_A" "next(e['from'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-a')")"
to_a="$(field "$PLANNING_A" "next(e['to'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-a')")"
from_b="$(field "$PLANNING_A" "next(e['from'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-b')")"
to_b="$(field "$PLANNING_A" "next(e['to'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-b')")"
from_c="$(field "$PLANNING_A" "next(e['from'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-c')")"
to_c="$(field "$PLANNING_A" "next(e['to'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-c')")"
from_d="$(field "$PLANNING_A" "next(e['from'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-d')")"
to_d="$(field "$PLANNING_A" "next(e['to'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/share-d')")"
check "4f. share-a's own from/to in share_basis are its own manifest's bounds" \
  "[ \"$from_a\" = '2026-06-01T10:00:00Z' ] && [ \"$to_a\" = '2026-06-01T18:00:00Z' ]"
check "4g. share-b's from/to in share_basis are share-b's own manifest's bounds" \
  "[ \"$from_b\" = '2026-06-01T12:00:00Z' ] && [ \"$to_b\" = '2026-06-01T18:00:00Z' ]"
check "4h. share-c's from/to in share_basis are share-c's own manifest's bounds" \
  "[ \"$from_c\" = '2026-06-01T14:00:00Z' ] && [ \"$to_c\" = '2026-06-01T18:00:00Z' ]"
check "4i. share-d's from/to in share_basis are share-d's own manifest's bounds" \
  "[ \"$from_d\" = '2026-06-01T16:00:00Z' ] && [ \"$to_d\" = '2026-06-01T18:00:00Z' ]"

# ── 5. durations are shared by the same rule ───────────────────────────────────────────
dur_a="$(field "$PLANNING_A" "d['sessions'][0]['duration_s']")"
dur_b="$(field "$PLANNING_B" "d['sessions'][0]['duration_s']")"
dur_c="$(field "$PLANNING_C" "d['sessions'][0]['duration_s']")"
dur_d="$(field "$PLANNING_D" "d['sessions'][0]['duration_s']")"
check "5a. share-a's apportioned duration_s is 22200" "[ \"$dur_a\" = 22200 ]"
check "5b. share-b's apportioned duration_s is 7800" "[ \"$dur_b\" = 7800 ]"
check "5c. share-c's apportioned duration_s is 4200" "[ \"$dur_c\" = 4200 ]"
check "5d. share-d's apportioned duration_s is 1800" "[ \"$dur_d\" = 1800 ]"

sdur_a="$(field "$PLANNING_A" "d['sessions'][0]['session_duration_s']")"
sdur_b="$(field "$PLANNING_B" "d['sessions'][0]['session_duration_s']")"
sdur_c="$(field "$PLANNING_C" "d['sessions'][0]['session_duration_s']")"
sdur_d="$(field "$PLANNING_D" "d['sessions'][0]['session_duration_s']")"
check "5e. session_duration_s is 45000 on all four entries" \
  "[ \"$sdur_a\" = 45000 ] && [ \"$sdur_b\" = 45000 ] && [ \"$sdur_c\" = 45000 ] && [ \"$sdur_d\" = 45000 ]"

# Read from the record, never hardcoded. An earlier cut asserted the unclaimed 9000 as a
# literal, which made this check green by construction: `unclaimed_duration_s` did not
# exist, so a session that leaked time — its `unclaimed_usd` and warning were both gated
# on unclaimed *dollars*, which are zero whenever the trailing lines are non-billable —
# had nothing in the record to give it away, and this line supplied the missing seconds
# itself rather than catching their absence.
undur="$(field "$PLANNING_A" "d['sessions'][0]['unclaimed_duration_s']")"
check "5f. the unclaimed span is recorded as unclaimed_duration_s, not inferred (got ${undur:-<absent>})" \
  "[ \"$undur\" = 9000 ]"
dur_sum="$(python3 -c "print(int('$dur_a')+int('$dur_b')+int('$dur_c')+int('$dur_d')+int('$undur'))" 2>/dev/null)"
check "5g. the four apportioned durations plus the recorded unclaimed span sum to 45000" "[ \"$dur_sum\" = 45000 ]"

exp_started="$(python3 -c "from datetime import datetime, timezone; print(datetime(2026,6,1,8,0,0,tzinfo=timezone.utc).isoformat())")"
exp_ended="$(python3 -c "from datetime import datetime, timezone; print(datetime(2026,6,1,20,30,0,tzinfo=timezone.utc).isoformat())")"
st_a="$(field "$PLANNING_A" "d['sessions'][0]['started_at']")"
st_b="$(field "$PLANNING_B" "d['sessions'][0]['started_at']")"
st_c="$(field "$PLANNING_C" "d['sessions'][0]['started_at']")"
st_d="$(field "$PLANNING_D" "d['sessions'][0]['started_at']")"
en_a="$(field "$PLANNING_A" "d['sessions'][0]['ended_at']")"
en_b="$(field "$PLANNING_B" "d['sessions'][0]['ended_at']")"
en_c="$(field "$PLANNING_C" "d['sessions'][0]['ended_at']")"
en_d="$(field "$PLANNING_D" "d['sessions'][0]['ended_at']")"
check "5h. started_at is the session's own first instant on all four entries, not the share's" \
  "[ \"$st_a\" = '$exp_started' ] && [ \"$st_b\" = '$exp_started' ] && [ \"$st_c\" = '$exp_started' ] && [ \"$st_d\" = '$exp_started' ]"
check "5i. ended_at is the session's own last instant on all four entries, not the share's" \
  "[ \"$en_a\" = '$exp_ended' ] && [ \"$en_b\" = '$exp_ended' ] && [ \"$en_c\" = '$exp_ended' ] && [ \"$en_d\" = '$exp_ended' ]"

# ── 6. a session with one claimant is untouched (GREEN today, must stay green) ────────
capture share-solo > "$TMP/capture-solo.txt"

has_share_basis="$(field "$PLANNING_SOLO" "'share_basis' in d['sessions'][0]")"
has_session_cost="$(field "$PLANNING_SOLO" "'session_cost_usd' in d['sessions'][0]")"
has_session_duration="$(field "$PLANNING_SOLO" "'session_duration_s' in d['sessions'][0]")"
has_unclaimed="$(field "$PLANNING_SOLO" "'unclaimed_usd' in d['sessions'][0]")"
check "6a. a solo session's entry has no share_basis" "[ \"$has_share_basis\" = False ]"
check "6b. a solo session's entry has no session_cost_usd" "[ \"$has_session_cost\" = False ]"
check "6c. a solo session's entry has no session_duration_s" "[ \"$has_session_duration\" = False ]"
check "6d. a solo session's entry has no unclaimed_usd" "[ \"$has_unclaimed\" = False ]"

no_share_fields_in_priced="$(field "$PLANNING_SOLO" "all('share' not in p and 'full_cost_usd' not in p for p in d['priced'])")"
check "6e. no priced[] row carries share or full_cost_usd" "[ \"$no_share_fields_in_priced\" = True ]"

solo_dur="$(field "$PLANNING_SOLO" "d['sessions'][0]['duration_s']")"
check "6f. duration_s equals ended_at - started_at (a single-response session spans 0s)" "[ \"$solo_dur\" = 0 ]"

solo_total="$(field "$PLANNING_SOLO" "d['cost_usd']['total']")"
solo_priced_sum="$(field "$PLANNING_SOLO" "sum(p['cost_usd'] for p in d['priced'])")"
check "6g. cost_usd.total is the whole transcript's cost — no share subtracted" "close_enough '$solo_total' '$solo_priced_sum'"

# ── 7. a response straddling a claim boundary is billed once, to its first line's owners ─
# 58% of real responses span more than one timestamp (several content-block lines for one
# API response). r2's first line — first in *file* order, which is what
# `iter_billable_messages_at` keys on — is the 12:30 one written in the fixture above, and
# 12:30 is inside share-b's window, so r2 belongs to {share-a, share-b}. This appended
# second line lands at 11:59:59.500, before share-b's `from` of 12:00, where the ownership
# set is {share-a} alone. The two lines therefore sit in *different* ownership stretches,
# which is the whole point: an implementation that buckets lines by window and dedups
# within each bucket bills r2 once per bucket (share-a gains a whole extra 4000 tokens),
# and one that dates a response by its *last* line instead of its first hands all 4000 to
# share-a and none to share-b. Both show up as a change in 7b/7c, whose expected values
# are phase 2's — a correct walk bills r2 exactly once, split between a and b, so nothing
# moves at all.
session_line "$SESSION" "$AT" "$BRANCH" "r2" "$MODEL" "2026-06-01T11:59:59.500Z" 0 4000 0 0 0 \
  >> "$PROJECTS/$SESSION.jsonl"

recapture share-a > "$TMP/capture-a3.txt"
recapture share-b > "$TMP/capture-b3.txt"
recapture share-c > "$TMP/capture-c3.txt"
recapture share-d > "$TMP/capture-d3.txt"

cost_a2="$(field "$PLANNING_A" "d['cost_usd']['total']")"
cost_b2="$(field "$PLANNING_B" "d['cost_usd']['total']")"
cost_c2="$(field "$PLANNING_C" "d['cost_usd']['total']")"
cost_d2="$(field "$PLANNING_D" "d['cost_usd']['total']")"
session_cost2="$(field "$PLANNING_A" "d['sessions'][0]['session_cost_usd']")"
unclaimed2="$(field "$PLANNING_A" "d['sessions'][0]['unclaimed_usd']")"
shares_sum2="$(python3 -c "print(float('$cost_a2')+float('$cost_b2')+float('$cost_c2')+float('$cost_d2')+float('$unclaimed2'))" 2>/dev/null)"
check "7a. the sum invariant from (1) still holds after a boundary-straddling duplicate line" \
  "close_enough '$shares_sum2' '$session_cost2'"
check "7b. share-a is not billed r2 twice, nor billed all of it by its later line" "close_enough '$cost_a2' '$cost_a'"
check "7c. share-b keeps its half of r2 — the first line's owners, not the last line's" "close_enough '$cost_b2' '$cost_b'"

# ── 8. the unclaimed remainder is reported, not silently dropped ──────────────────────
# Reads the phase-1 capture output — the unclaimed remainder (r5, always after every
# claimant's `to`) is unaffected by phase 7's duplicate r2 line, so nothing here needs a
# fresh capture; see the header note in each phase above about not re-running one.
check "8a. capture output names the session in an unclaimed-remainder warning" \
  "grep -q '$SESSION' \"$TMP\"/capture-a.txt \"$TMP\"/capture-b.txt \"$TMP\"/capture-c.txt \"$TMP\"/capture-d.txt \"$TMP\"/capture-a2.txt"

exp_unclaimed="$(python3 -c "print(800/25800*float('$session_cost'))" 2>/dev/null)"
check "8b. unclaimed_usd is the 800/25800 share of the session cost" "close_enough '$unclaimed' '$exp_unclaimed'"

# 8c. and when there is no head, that warning is the sentence it always was. Ruling 3:
# "the tail's sentence stays as it is when the remainder is all tail". Phase 1's session
# has no head to name — share-a's window is eight hours, so its bound (02:00) is four
# hours before r0 and r0 is paid — and its whole remainder is r5, past every `to`. The
# head branch must not fire on it, and the `elif`'s wording must be byte-for-byte the
# pre-bound one. Nothing above reads it; without this, that branch could say anything.
check "8c. with no head the warning is the old tail sentence and carries no head clause" \
  "grep -q 'unclaimed by any feature — widen a claimant' \"$TMP/capture-a.txt\" \
     && grep -q 'to have it counted' \"$TMP/capture-a.txt\" \
     && ! grep -q 'opening stretch' \"$TMP/capture-a.txt\""

# ── 9. a claimant whose own window is empty is never paid the head ────────────────────
# `share-empty`'s window runs backwards (09:00 -> 03:00), so `check_empty_window` calls it
# proven to match nothing and promises it captures $0.00. It pins the session by id, which
# admits it past window matching entirely — so its window is never asked to select
# anything. Its `from` (09:00) sorts earliest of the five claims and still falls after r0
# (08:00), which is exactly the shape the head-stretch fallback pays: ranking on `from`
# alone, it hands r0 and the 08:00-09:00 opening span to a claim proven to own none of it.
# Compared against phase 7's figures because the duplicate r2 line is still in the
# transcript.
write_manifest share-empty "2026-06-01T09:00:00Z" "2026-06-01T03:00:00Z" "$SESSION"
PLANNING_EMPTY="$AT/self/features/share-empty/planning.json"

capture   share-empty > "$TMP/capture-empty.txt"
recapture share-a     > "$TMP/capture-a4.txt"
recapture share-b     > "$TMP/capture-b4.txt"
recapture share-c     > "$TMP/capture-c4.txt"
recapture share-d     > "$TMP/capture-d4.txt"

cost_empty="$(field "$PLANNING_EMPTY" "d['cost_usd']['total']")"
check "9a. an empty-window claimant's cost_usd.total is 0.00 — it owns no part of the session"   "close_enough '$cost_empty' '0'"

cost_a4="$(field "$PLANNING_A" "d['cost_usd']['total']")"
check "9b. share-a still owns the head — its total is unchanged by the empty claimant"   "close_enough '$cost_a4' '$cost_a2'"

cost_b4="$(field "$PLANNING_B" "d['cost_usd']['total']")"
cost_c4="$(field "$PLANNING_C" "d['cost_usd']['total']")"
cost_d4="$(field "$PLANNING_D" "d['cost_usd']['total']")"
check "9c. share-b is unchanged by the empty claimant" "close_enough '$cost_b4' '$cost_b2'"
check "9d. share-c is unchanged by the empty claimant" "close_enough '$cost_c4' '$cost_c2'"
check "9e. share-d is unchanged by the empty claimant" "close_enough '$cost_d4' '$cost_d2'"

session_cost4="$(field "$PLANNING_A" "d['sessions'][0]['session_cost_usd']")"
unclaimed4="$(field "$PLANNING_A" "d['sessions'][0]['unclaimed_usd']")"
shares_sum4="$(python3 -c "print(float('$cost_a4')+float('$cost_b4')+float('$cost_c4')+float('$cost_d4')+float('$cost_empty')+float('$unclaimed4'))" 2>/dev/null)"
check "9f. the sum invariant still holds with a fifth, empty-window claimant"   "close_enough '$shares_sum4' '$session_cost4'"

dur_empty="$(field "$PLANNING_EMPTY" "d['sessions'][0]['duration_s'] if d['sessions'] else 0")"
check "9g. an empty-window claimant's apportioned duration_s is 0 — no part of the head span"   "[ \"$dur_empty\" = 0 ] || [ \"$dur_empty\" = 0.0 ]"

check "9h. capture output warns that the empty window matches nothing" \
  "grep -q 'session_window is empty' \"$TMP/capture-empty.txt\""

# ── 10. an empty window earlier than the session itself does not destroy the head ─────
# The same defect from its other side. `share-empty-2` opens at 05:00, before the session's
# own first response — so with it in the ranking pool no instant is "before every `from`"
# any more, the fallback matches nothing, and the head it should have handed share-a falls
# to the unclaimed remainder instead. Nobody is overpaid here; the legitimate earliest
# claimant is silently underpaid, which is the harder failure to notice.
write_manifest share-empty-2 "2026-06-01T05:00:00Z" "2026-06-01T03:00:00Z" "$SESSION"
PLANNING_EMPTY2="$AT/self/features/share-empty-2/planning.json"

capture   share-empty-2 > "$TMP/capture-empty2.txt"
recapture share-a       > "$TMP/capture-a5.txt"
recapture share-empty   > "$TMP/capture-empty-b.txt"

cost_empty2="$(field "$PLANNING_EMPTY2" "d['cost_usd']['total']")"
check "10a. the second empty-window claimant's cost_usd.total is 0.00" \
  "close_enough '$cost_empty2' '0'"

cost_a5="$(field "$PLANNING_A" "d['cost_usd']['total']")"
check "10b. share-a still owns the head — an empty window opening before the session does not strand it" \
  "close_enough '$cost_a5' '$cost_a2'"

unclaimed5="$(field "$PLANNING_A" "d['sessions'][0]['unclaimed_usd']")"
check "10c. the unclaimed remainder is unchanged — the head did not fall into it" \
  "close_enough '$unclaimed5' '$unclaimed4'"

# ── 11. an empty claim elsewhere does not flip a solo session onto the share path ──────
# The costliest shape of the same defect. `share-solo`'s session has exactly one real
# claimant, so it must be priced whole and carry no share fields at all (phase 6). A
# second feature pinning it with a backwards window can own no part of it — but if it is
# counted as a claimant anyway, `len(intervals) <= 1` is false, the share path engages,
# and share-solo silently loses everything past its own `to` to the unclaimed remainder.
# A single malformed manifest anywhere in either corpus would do it, to any feature.
write_manifest share-solo-empty "2026-06-01T07:00:00Z" "2026-06-01T06:00:00Z" "$SESSION_SOLO"
capture   share-solo-empty > "$TMP/capture-solo-empty.txt"
recapture share-solo       > "$TMP/capture-solo2.txt"

solo_basis2="$(field "$PLANNING_SOLO" "'share_basis' in d['sessions'][0]")"
check "11a. share-solo is still unshared — an empty claim elsewhere is not a claimant" \
  "[ \"$solo_basis2\" = False ]"
solo_total2="$(field "$PLANNING_SOLO" "d['cost_usd']['total']")"
check "11b. ...and it still carries the whole session's cost, not a share of it" \
  "close_enough '$solo_total2' '$solo_total'"
solo_dur2="$(field "$PLANNING_SOLO" "d['sessions'][0]['duration_s']")"
check "11c. ...and its duration is untouched" "[ \"$solo_dur2\" = \"$solo_dur\" ]"
check "11d. capture names the offending claim rather than dropping it silently" \
  "grep -q 'empty window' \"$TMP/capture-solo2.txt\""

# ── 12. what lies outside a single-claimant session's window is quantified ────────────
# `shared-session-share` deliberately left a session nobody else claims priced in full,
# however far it outran its `to` — slicing it would trade a disclosed over-count for a
# silent under-count. The disclosure was `may span the window boundary` and it said
# nothing about size. `share-outside` is that shape: two responses, 1000 tokens inside
# the window and 3000 after it, so the dollars past `to` are exactly three quarters of
# the session's cost and a warning that named the whole session, or only the part inside,
# would print a different figure.
SESSION_OUT="44444444-0000-0000-0000-000000000004"
{
  session_line "$SESSION_OUT" "$AT" "$BRANCH" "o0" "$MODEL" "2026-06-01T10:00:00.000Z" 0 1000 0 0 0
  session_line "$SESSION_OUT" "$AT" "$BRANCH" "o1" "$MODEL" "2026-06-01T14:00:00.000Z" 0 3000 0 0 0
} > "$PROJECTS/$SESSION_OUT.jsonl"
write_manifest share-outside "2026-06-01T09:00:00Z" "2026-06-01T12:00:00Z" "$SESSION_OUT"
PLANNING_OUT="$AT/self/features/share-outside/planning.json"
capture share-outside > "$TMP/capture-outside.txt"

out_total="$(field "$PLANNING_OUT" "d['cost_usd']['total']")"
out_shared="$(field "$PLANNING_OUT" "'share_basis' in d['sessions'][0]")"
check "12a. share-outside's session has exactly one claimant — the unshared path" "[ \"$out_shared\" = False ]"
check "12b. the boundary warning fires and names the session" \
  "grep -q 'may span the window boundary' \"$TMP/capture-outside.txt\" && grep -q '$SESSION_OUT' \"$TMP/capture-outside.txt\""
# The printed figure, read back numerically rather than as a formatted string, so a
# rounding difference in the last place is not a failure and an absent figure is.
got_dollars="$(sed -n 's/.*); \$\([0-9][0-9.]*\) and .*/\1/p' "$TMP/capture-outside.txt" | head -1)"
check "12c. ... quantifying the dollars at or after to (3/4 of the session; got \$${got_dollars:-<none>})" \
  "python3 -c \"import sys; sys.exit(0 if abs(float('${got_dollars:-nan}') - 0.75*float('$out_total')) < 1e-4 else 1)\" 2>/dev/null"
check "12d. ... and the seconds, 14:00 less the 12:00 bound" "grep -q '7200s' \"$TMP/capture-outside.txt\""
check "12e. ... and that they were counted in full, this feature being the only claimant" \
  "grep -q 'counted in full' \"$TMP/capture-outside.txt\""
# The figure is prose: the session is still priced whole, so cost_usd.total strictly
# exceeds the part past `to`. Priced any other way this comparison flips.
check "12f. cost_usd.total still counts them — the single-claimant path is not sliced" \
  "python3 -c \"import sys; sys.exit(0 if float('$out_total') > float('${got_dollars:-nan}') else 1)\" 2>/dev/null"
# The other branch of the same sentence: on the share path those responses are already
# excluded by the split, so the warning must not claim they were counted. share-a's
# window closes at 18:00 and the session runs to 20:30.
check "12g. on the share path the same warning says they are not counted" \
  "grep -q 'may span the window boundary' \"$TMP/capture-a2.txt\" && grep -q 'not counted' \"$TMP/capture-a2.txt\""

# ── 13. a claimant whose `to` moves earlier loses the responses past it ───────────────
# `feature-close.sh` now stamps `to` from evidence instead of from its own wall clock,
# and `manifest.py set-window-to --tighten` is the repair for a bound already written.
# share-d's window is 16:00-18:00 and its only response is r4 at 16:30; tightening the
# bound to 16:15 must leave it owning nothing, with the session's own cost still whole
# and the part it gave up going to the claimants that still cover 16:30.
python3 -B "$AT/analysis/manifest.py" --self share-d set-window-to --tighten "2026-06-01T16:15:00Z" \
  > "$TMP/tighten-d.txt" 2>&1
check "13a. set-window-to --tighten moves share-d's bound earlier, printing old then new" \
  "grep -q '2026-06-01T18:00:00Z -> 2026-06-01T16:15:00Z' \"$TMP/tighten-d.txt\""

recapture share-a > "$TMP/capture-a6.txt"
recapture share-b > "$TMP/capture-b6.txt"
recapture share-c > "$TMP/capture-c6.txt"
recapture share-d > "$TMP/capture-d6.txt"

cost_a6="$(field "$PLANNING_A" "d['cost_usd']['total']")"
cost_b6="$(field "$PLANNING_B" "d['cost_usd']['total']")"
cost_c6="$(field "$PLANNING_C" "d['cost_usd']['total']")"
cost_d6="$(field "$PLANNING_D" "d['cost_usd']['total']")"
check "13b. share-d owns nothing once its bound precedes its only response" "close_enough '$cost_d6' '0'"
check "13c. share-c picks up the part share-d gave up — the tighten really moved money" \
  "python3 -c \"import sys; sys.exit(0 if float('$cost_c6') > float('$cost_c4') else 1)\" 2>/dev/null"

session_cost6="$(field "$PLANNING_A" "d['sessions'][0]['session_cost_usd']")"
unclaimed6="$(field "$PLANNING_A" "d['sessions'][0]['unclaimed_usd']")"
shares_sum6="$(python3 -c "print(float('$cost_a6')+float('$cost_b6')+float('$cost_c6')+float('$cost_d6')+float('$unclaimed6'))" 2>/dev/null)"
check "13d. the sum invariant from (1) survives the tightened bound" "close_enough '$shares_sum6' '$session_cost6'"

# ── 14. a quantity of nothing is not a disclosure ─────────────────────────────────────
# The boundary warning fires on the session's last LINE being past `to`, while the
# quantity counts billable RESPONSES at or after it. A trailing user line — the shape the
# last instant of a real transcript has more often than not — puts the two out of step:
# nothing billable is out there and the overrun is under a second, so the quantified
# sentence would assert a measurement of nothing ($0.0000 and 0s) where the qualitative
# one it replaced said something true. `share-quiet` is exactly that shape: one response
# well inside the window, and half a second past `to` an unbilled user line.
SESSION_QUIET="55555555-0000-0000-0000-000000000005"
{
  session_line "$SESSION_QUIET" "$AT" "$BRANCH" "q0" "$MODEL" "2026-06-01T10:00:00.000Z" 0 1000 0 0 0
  user_line "2026-06-01T12:00:00.500Z"
} > "$PROJECTS/$SESSION_QUIET.jsonl"
write_manifest share-quiet "2026-06-01T09:00:00Z" "2026-06-01T12:00:00Z" "$SESSION_QUIET"
PLANNING_QUIET="$AT/self/features/share-quiet/planning.json"
capture share-quiet > "$TMP/capture-quiet.txt"

quiet_shared="$(field "$PLANNING_QUIET" "'share_basis' in d['sessions'][0]")"
check "14a. share-quiet's session has exactly one claimant — the unshared path, as in 12" "[ \"$quiet_shared\" = False ]"
check "14b. the boundary warning still fires and names the session — its last line IS past to" \
  "grep -q 'may span the window boundary' \"$TMP/capture-quiet.txt\" && grep -q '$SESSION_QUIET' \"$TMP/capture-quiet.txt\""
# Read back the way 12c reads the figure it wants present; here its absence is the
# assertion, so a formatted $0.0000 fails rather than passing as "zero is zero anyway".
quiet_dollars="$(sed -n 's/.*); \$\([0-9][0-9.]*\) and .*/\1/p' "$TMP/capture-quiet.txt" | head -1)"
check "14c. ... with no dollar figure at all (got \$${quiet_dollars:-<none>})" '[[ -z "$quiet_dollars" ]]'
check "14d. ... saying instead that no billable response falls past to" \
  "grep -q 'no billable response' \"$TMP/capture-quiet.txt\""
quiet_total="$(field "$PLANNING_QUIET" "d['cost_usd']['total']")"
check "14e. ... and the session is still priced whole, the warning being prose (got \$${quiet_total:-<none>})" \
  "python3 -c \"import sys; sys.exit(0 if float('${quiet_total:-nan}') > 0 else 1)\" 2>/dev/null"

# ── 15. the opening stretch is bounded by the earliest claimant's own window length ───
# A fresh session and two fresh claimants, so nothing above is re-run or disturbed. The
# fallback in `share_owners` hands every instant before the earliest `from` to the
# earliest claimant, however far back that reaches — measured on the real session
# `2d8b1236`, a 25-minute feature was paid a 45-hour head. `head_bound` bounds it by that
# claimant's own window length: an instant no further before its `from` than its window
# is long is still the planning that led to it; earlier than that, nobody owns it and it
# falls to the unclaimed remainder exactly as the tail does.
#
# head-a's window is one hour (10:00-11:00), so its bound is 09:00. r0 at 08:00 is two
# hours out and unowned; r1 at 09:30 is inside the hour and still head-a's. Phase 3 above
# is the no-change half: share-a's window is eight hours and its head response two hours
# out, so it is still paid.
SESSION_HEAD="66666666-0000-0000-0000-000000000006"
{
  session_line "$SESSION_HEAD" "$AT" "$BRANCH" "h0" "$MODEL" "2026-06-01T08:00:00.000Z" 0 1000 0 0 0
  session_line "$SESSION_HEAD" "$AT" "$BRANCH" "h1" "$MODEL" "2026-06-01T09:30:00.000Z" 0 2000 0 0 0
  session_line "$SESSION_HEAD" "$AT" "$BRANCH" "h2" "$MODEL" "2026-06-01T10:30:00.000Z" 0 4000 0 0 0
  session_line "$SESSION_HEAD" "$AT" "$BRANCH" "h3" "$MODEL" "2026-06-01T13:00:00.000Z" 0 3000 0 0 0
} > "$PROJECTS/$SESSION_HEAD.jsonl"

write_manifest head-a "2026-06-01T10:00:00Z" "2026-06-01T11:00:00Z" "$SESSION_HEAD"
write_manifest head-b "2026-06-01T12:00:00Z" "2026-06-01T18:00:00Z" "$SESSION_HEAD"
PLANNING_HEAD_A="$AT/self/features/head-a/planning.json"
PLANNING_HEAD_B="$AT/self/features/head-b/planning.json"

capture head-a > "$TMP/capture-head-a.txt"
capture head-b > "$TMP/capture-head-b.txt"

head_session_cost="$(field "$PLANNING_HEAD_A" "d['sessions'][0]['session_cost_usd']")"
cost_head_a="$(field "$PLANNING_HEAD_A" "d['cost_usd']['total']")"
cost_head_b="$(field "$PLANNING_HEAD_B" "d['cost_usd']['total']")"
unclaimed_head="$(field "$PLANNING_HEAD_A" "d['sessions'][0]['unclaimed_usd']")"

# r1 + r2, and not r0: 6000 of the session's 10000 output tokens.
exp_head_a="$(python3 -c "print(6000/10000*float('$head_session_cost'))" 2>/dev/null)"
check "15a. head-a's total is r1 + r2 — r0, two hours before a one-hour window, is not in it" \
  "close_enough '$cost_head_a' '$exp_head_a'"

exp_head_unclaimed="$(python3 -c "print(1000/10000*float('$head_session_cost'))" 2>/dev/null)"
check "15b. unclaimed_usd is exactly r0's share of the session cost (got \$${unclaimed_head:-<absent>})" \
  "close_enough '$unclaimed_head' '$exp_head_unclaimed'"
head_shares_sum="$(python3 -c "print(float('$cost_head_a')+float('$cost_head_b')+float('$unclaimed_head'))" 2>/dev/null)"
check "15b-sum. the two totals plus the remainder equal session_cost_usd" \
  "close_enough '$head_shares_sum' '$head_session_cost'"

exp_head_b="$(python3 -c "print(3000/10000*float('$head_session_cost'))" 2>/dev/null)"
check "15c. head-b's total is r3 alone — the bound moves nothing on the later claimant" \
  "close_enough '$cost_head_b' '$exp_head_b'"

# 08:00-09:00 unowned (before head-a's bound) plus the uncovered 11:00-12:00 gap between
# the two windows; head-a's own share of the span is 09:00-11:00.
dur_head_a="$(field "$PLANNING_HEAD_A" "d['sessions'][0]['duration_s']")"
dur_head_b="$(field "$PLANNING_HEAD_B" "d['sessions'][0]['duration_s']")"
undur_head="$(field "$PLANNING_HEAD_A" "d['sessions'][0]['unclaimed_duration_s']")"
sdur_head="$(field "$PLANNING_HEAD_A" "d['sessions'][0]['session_duration_s']")"
check "15d. head-a's apportioned duration_s is 09:00-11:00 = 7200 (got ${dur_head_a:-<absent>})" \
  "[ \"$dur_head_a\" = 7200 ]"
check "15d-unclaimed. unclaimed_duration_s is the 3600 before head-a's bound plus the 3600 gap (got ${undur_head:-<absent>})" \
  "[ \"$undur_head\" = 7200 ]"
head_dur_sum="$(python3 -c "print(int('$dur_head_a')+int('$dur_head_b')+int('$undur_head'))" 2>/dev/null)"
check "15d-sum. the apportioned spans plus the remainder sum to session_duration_s (18000)" \
  "[ \"$head_dur_sum\" = 18000 ] && [ \"$sdur_head\" = 18000 ]"

# 15e. the disclosure. The head is not the tail and its remedies are not the tail's:
# widening a `to` bound cannot reach backwards, and `from` has no `set-window-to`.
head_warn_dollars="$(sed -n 's/.*of which \$\([0-9][0-9.]*\) (.*/\1/p' "$TMP/capture-head-a.txt" | head -1)"
check "15e. the unclaimed warning quantifies the head's dollars, r0's share (got \$${head_warn_dollars:-<none>})" \
  "python3 -c \"import sys; sys.exit(0 if abs(float('${head_warn_dollars:-nan}') - float('$exp_head_unclaimed')) < 1e-4 else 1)\" 2>/dev/null"
check "15e-seconds. ... and the head's seconds, separately from the rest's" \
  "grep -q '(3600s) is the opening stretch' \"$TMP/capture-head-a.txt\""
check "15e-rest. ... and what is left after it, the 3600s gap that is not head" \
  "grep -q '(3600s) is the rest' \"$TMP/capture-head-a.txt\""
check "15e-remedy-pin. ... naming the pin remedy for the head" \
  "grep -q 'pin the session to the feature that planning belongs to' \"$TMP/capture-head-a.txt\""
check "15e-remedy-from. ... and that the earliest claimant's from must be moved by hand, there being no set-window-to for it" \
  "grep -q 'back by hand' \"$TMP/capture-head-a.txt\" && grep -q 'set-window-to' \"$TMP/capture-head-a.txt\""

# 15f. an earliest claimant still in flight keeps the unbounded head. Its `to` is null
# until `feature-close.sh` stamps it, and a window with no end has no length to bound by;
# the recapture that follows the close applies the bound. head-a then owns r0 and r1
# outright, r2, and half of r3 (which head-b's window also covers): 8500 of 10000.
write_manifest head-a "2026-06-01T10:00:00Z" null "$SESSION_HEAD"
recapture head-a > "$TMP/capture-head-a2.txt"
recapture head-b > "$TMP/capture-head-b2.txt"

head_session_cost_f="$(field "$PLANNING_HEAD_A" "d['sessions'][0]['session_cost_usd']")"
cost_head_a_f="$(field "$PLANNING_HEAD_A" "d['cost_usd']['total']")"
has_unclaimed_f="$(field "$PLANNING_HEAD_A" "'unclaimed_usd' in d['sessions'][0]")"
exp_head_a_f="$(python3 -c "print(8500/10000*float('$head_session_cost_f'))" 2>/dev/null)"
check "15f. an in-flight earliest claimant is still paid r0 — the unbounded head is today's behaviour" \
  "close_enough '$cost_head_a_f' '$exp_head_a_f'"
check "15f-unclaimed. ... and unclaimed_usd holds none of it" "[ \"$has_unclaimed_f\" = False ]"

# The seconds side of the same exemption. This is the branch where `partition_seconds`
# gets `head_edge = None` and adds no cut point at all, so it is where "the dollars and
# the seconds cannot disagree" is least protected — and 15f above asserts only dollars.
# Derived from the same fixture: 08:00-10:00 (the unbounded head) and 10:00-12:00 (its own
# open-ended window) are head-a's whole, and the 12:00-13:00 stretch head-b's window also
# covers is halved — 7200 + 7200 + 1800 = 16200, against head-b's 1800 and nothing left.
dur_head_a_f="$(field "$PLANNING_HEAD_A" "d['sessions'][0]['duration_s']")"
dur_head_b_f="$(field "$PLANNING_HEAD_B" "d['sessions'][0]['duration_s']")"
has_undur_f="$(field "$PLANNING_HEAD_A" "'unclaimed_duration_s' in d['sessions'][0]")"
check "15f-duration. ... and the seconds follow the dollars: head-a's duration_s is the unbounded 16200 (got ${dur_head_a_f:-<absent>})" \
  "[ \"$dur_head_a_f\" = 16200 ]"
check "15f-duration-b. ... head-b's is its half of the 12:00-13:00 overlap alone, 1800 (got ${dur_head_b_f:-<absent>})" \
  "[ \"$dur_head_b_f\" = 1800 ]"
check "15f-duration-unclaimed. ... and no unclaimed_duration_s at all, as no unclaimed_usd" \
  "[ \"$has_undur_f\" = False ]"

# ── 16. a remainder that is ALL head names no rest, and offers no remedy for one ───────
# The mirror of ruling 3's tail-only sentence, which the head branch did not have: when
# the claimants' windows chain over everything after the earliest `from`, the whole
# remainder is the opening stretch, `rest` is $0.0000 and 0s, and the reader was handed
# the "widen a `to` bound" remedy for nothing at all — the remedy that provably cannot
# reach a head, since no `to` grows backwards. That shape is not exotic: one claimant
# whose window covers the session's last instant is the common case.
#
# A fresh session and two fresh claimants, chained end to end at 11:00 (`in_window` is
# half-open, so `to == from` leaves no gap) and running past the last response, so the
# only unowned instants in the span are the 08:00-09:00 before allhead-a's bound.
SESSION_ALLHEAD="77777777-0000-0000-0000-000000000007"
{
  session_line "$SESSION_ALLHEAD" "$AT" "$BRANCH" "n0" "$MODEL" "2026-06-01T08:00:00.000Z" 0 1000 0 0 0
  session_line "$SESSION_ALLHEAD" "$AT" "$BRANCH" "n1" "$MODEL" "2026-06-01T10:30:00.000Z" 0 2000 0 0 0
  session_line "$SESSION_ALLHEAD" "$AT" "$BRANCH" "n2" "$MODEL" "2026-06-01T13:00:00.000Z" 0 3000 0 0 0
} > "$PROJECTS/$SESSION_ALLHEAD.jsonl"

write_manifest allhead-a "2026-06-01T10:00:00Z" "2026-06-01T11:00:00Z" "$SESSION_ALLHEAD"
write_manifest allhead-b "2026-06-01T11:00:00Z" "2026-06-01T14:00:00Z" "$SESSION_ALLHEAD"
PLANNING_ALLHEAD_A="$AT/self/features/allhead-a/planning.json"

capture allhead-a > "$TMP/capture-allhead-a.txt"
capture allhead-b > "$TMP/capture-allhead-b.txt"

allhead_session_cost="$(field "$PLANNING_ALLHEAD_A" "d['sessions'][0]['session_cost_usd']")"
allhead_unclaimed="$(field "$PLANNING_ALLHEAD_A" "d['sessions'][0]['unclaimed_usd']")"
allhead_undur="$(field "$PLANNING_ALLHEAD_A" "d['sessions'][0]['unclaimed_duration_s']")"
# The fixture's own premise, asserted before the wording is: the remainder is 08:00-09:00
# and nothing else. Without this the two negative greps below could pass on a session that
# simply has no head, and the whole phase would be vacuous.
check "16a. the remainder really is all head — unclaimed_duration_s is the 3600 before the bound (got ${allhead_undur:-<absent>})" \
  "[ \"$allhead_undur\" = 3600 ]"
exp_allhead_unclaimed="$(python3 -c "print(1000/6000*float('$allhead_session_cost'))" 2>/dev/null)"
check "16a-usd. ... and unclaimed_usd is n0's share alone" \
  "close_enough '$allhead_unclaimed' '$exp_allhead_unclaimed'"

check "16b. the warning still names the opening stretch and its seconds" \
  "grep -q '(3600s) is the opening stretch' \"$TMP/capture-allhead-a.txt\""
check "16c. ... and does not report a rest of nothing" \
  "! grep -q 'is the rest' \"$TMP/capture-allhead-a.txt\""
check "16d. ... nor hand the reader the remedy for that nothing" \
  "! grep -q 'For the rest' \"$TMP/capture-allhead-a.txt\""
check "16e. ... while the head's own two remedies are named as before" \
  "grep -q 'the session to the feature that planning belongs to' \"$TMP/capture-allhead-a.txt\" \
     && grep -q 'back by hand' \"$TMP/capture-allhead-a.txt\""

# ── 17. the bound's edge is inclusive: an instant exactly ON it is still paid ──────────
# Ruling 1 is `min_from - moment <= to - from`, so `head_bound` is the earliest payable
# instant and not the first unpayable one. Nothing pinned that: flipping either `<` to
# `<=` (in `share_owners` or in `is_unpaid_head`) moved both the dollars and the seconds
# and left every check above green — the classic off-by-one on the one boundary this
# whole feature is about.
#
# A fresh session again, since a fifth response on the phase-15 session would re-base
# every token fraction in 15a-15f. edge-a's window is one hour (10:00-11:00), so its bound
# is 09:00 exactly, and e0 sits on it. The bound is also the session's start, so
# `partition_seconds` adds no cut point for it (`start < head_edge < end` is false) and
# the 09:00-10:00 segment is judged at 09:00 by the fallback itself.
SESSION_EDGE="88888888-0000-0000-0000-000000000008"
{
  session_line "$SESSION_EDGE" "$AT" "$BRANCH" "e0" "$MODEL" "2026-06-01T09:00:00.000Z" 0 1000 0 0 0
  session_line "$SESSION_EDGE" "$AT" "$BRANCH" "e1" "$MODEL" "2026-06-01T10:30:00.000Z" 0 2000 0 0 0
  session_line "$SESSION_EDGE" "$AT" "$BRANCH" "e2" "$MODEL" "2026-06-01T13:00:00.000Z" 0 3000 0 0 0
} > "$PROJECTS/$SESSION_EDGE.jsonl"

write_manifest edge-a "2026-06-01T10:00:00Z" "2026-06-01T11:00:00Z" "$SESSION_EDGE"
write_manifest edge-b "2026-06-01T11:00:00Z" "2026-06-01T18:00:00Z" "$SESSION_EDGE"
PLANNING_EDGE_A="$AT/self/features/edge-a/planning.json"
PLANNING_EDGE_B="$AT/self/features/edge-b/planning.json"

capture edge-a > "$TMP/capture-edge-a.txt"
capture edge-b > "$TMP/capture-edge-b.txt"

edge_session_cost="$(field "$PLANNING_EDGE_A" "d['sessions'][0]['session_cost_usd']")"
cost_edge_a="$(field "$PLANNING_EDGE_A" "d['cost_usd']['total']")"
dur_edge_a="$(field "$PLANNING_EDGE_A" "d['sessions'][0]['duration_s']")"
has_unclaimed_e="$(field "$PLANNING_EDGE_A" "'unclaimed_usd' in d['sessions'][0]")"
has_undur_e="$(field "$PLANNING_EDGE_A" "'unclaimed_duration_s' in d['sessions'][0]")"

# e0 + e1: 3000 of the session's 6000 output tokens. Under a `<=` bound e0 falls to the
# remainder and this reads 2000/6000.
exp_edge_a="$(python3 -c "print(3000/6000*float('$edge_session_cost'))" 2>/dev/null)"
check "17a. a response landing exactly on head_bound is paid to the earliest claimant" \
  "close_enough '$cost_edge_a' '$exp_edge_a'"
# [09:00, 10:00) — the segment the bound opens — plus edge-a's own window. Under a `<=`
# bound the first of those two is unclaimed and this reads 3600.
check "17b. ... and the segment from the bound to its from is in its duration_s: 7200 (got ${dur_edge_a:-<absent>})" \
  "[ \"$dur_edge_a\" = 7200 ]"
check "17c. ... so nothing on this session is unclaimed, in dollars or in seconds" \
  "[ \"$has_unclaimed_e\" = False ] && [ \"$has_undur_e\" = False ]"

echo
if [ "$fails" -eq 0 ]; then
  echo "session-share: all checks passed"
else
  echo "session-share: $fails check(s) failed"
fi
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
