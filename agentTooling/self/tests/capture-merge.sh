#!/usr/bin/env bash
set -uo pipefail

# Self-test for capture_planning.py's merge into the committed record
# (self/features/capture-merges-committed-record/). Run by self/gate.sh, or by hand:
# bash self/tests/capture-merge.sh
#
# Same scaffolding as capture-guard.sh — copies of `analysis/{pricing,litellm_prices,
# roots,transcript,capture_planning,report,routing}.py` and `rates_history.json` into a
# throwaway agentTooling checkout under mktemp -d, one synthesized feature manifest, and
# under a redirected $HOME the `~/.claude/projects/*/<session_id>.jsonl` transcripts the
# capture selects on. No model, no network; a few seconds.
#
# What it pins. A committed `planning.json` is the BASELINE every later capture merges
# into: a row this scan can reach is re-priced from its transcript, a row it cannot reach
# is kept from the committed record, stamped `carried_from` with the date it was
# ORIGINALLY captured. In a Claude Code cloud container that is the normal case from
# round 2 on — each round runs in a new container and the previous container's
# transcripts are gone, so a capture that refused on an unreachable row (the old
# `check_frozen_cost` guard, which needed a hand `--carry-lost`) refused at every
# multi-round cloud close. The merge can never lower the figure to zero, so it has
# nothing left to protect; `--force` stays as the explicit rebuild from what this scan
# reaches.
#
# Asserts, in order:
#   A. a prior record with an unreachable session: a plain --recapture WRITES (exit 0, no
#      REFUSING), keeps the lost row stamped `carried_from` = the capture it came from,
#      adds the session this scan reaches (no stamp), totals the two, sets the top-level
#      `carried_from`, and prints one WARN naming the carried id;
#   B. a row already carried once keeps its FIRST `carried_from` through a second and a
#      third capture — it is never re-stamped with a later capture's `captured_at` — and
#      a row lost later is stamped with the last capture that priced it from its
#      transcript, the top-level field being the earliest of the stamps;
#   C. merge keeps only what cannot be seen: a reachable session deselected by a narrowed
#      `session_window` is dropped, not carried, and one reclassified as runner cost by
#      a usage.json (`excluded_ids`) is dropped even though its transcript is gone;
#   D. --force rebuilds from what this scan reaches alone: no carried row, no top-level
#      `carried_from`, the carried dollars gone from the total;
#   E. report.py prints one line — on stdout and in report.md — saying how many rows were
#      carried and from which capture date(s), and `report.json` carries the same under
#      `carried`; a record with no carried row prints none and carries no key;
#   F. --carry-lost is still accepted, as a no-op alias of the default, and its help text
#      says so;
#   G. a carried PINNED session stays pinned: its carried row keeps `selected_by: pinned`
#      and so does its claim in the session-claims ledger — the old fallback ledgered
#      every carried session as `branch` — while a re-priced branch session's claim says
#      `branch`. A7 asserts the ledger for the branch-selected carried row of phase A.
#
# All RED until the merge landed in analysis/capture_planning.py and report.py; A7 and G
# (round 2) RED until the carried row's `selected_by` reached `session_selected_by`.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Physical path — roots.py resolves through Path.resolve(); see capture-guard.sh.
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
for f in pricing.py litellm_prices.py rates_history.json roots.py transcript.py capture_planning.py report.py routing.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done
mkdir -p "$AT/.git"

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

SLUG="capture-merge"
FEATURE_DIR="$AT/self/features/$SLUG"
PLANNING="$FEATURE_DIR/planning.json"
REPORT_MD="$FEATURE_DIR/report.md"
REPORT_JSON="$FEATURE_DIR/report.json"
BRANCH="someFeatureBranch"
MODEL="claude-sonnet-5"
# Three rounds' coordinators, each in a container of its own: A in the first, B in the
# second, C in the third. A container sees its own transcript and nobody else's.
SESSION_A="aaaaaaaa-0000-0000-0000-000000000001"
SESSION_B="bbbbbbbb-0000-0000-0000-000000000002"
SESSION_C="cccccccc-0000-0000-0000-000000000003"
FAR_TO="2099-01-01T00:00:00.000Z"

FAKE_HOME="$TMP/home"
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/.' '--')"
mkdir -p "$PROJECTS" "$FEATURE_DIR"

# write_manifest [TO] [SESSIONS_JSON] — the feature README whose last ```json fence
# capture reads. The default `to` is a far bound, so every session below is in the window
# until phase C narrows it; SESSIONS_JSON is the `sessions` pin list, empty by default.
write_manifest() {
  local to="${1:-$FAR_TO}" pins="${2:-[]}"
  cat > "$FEATURE_DIR/README.md" <<EOF
# $SLUG

Fixture feature for self/tests/capture-merge.sh.

\`\`\`json
{
  "slug": "$SLUG",
  "branches": ["$BRANCH"],
  "session_window": {"from": null, "to": "$to"},
  "exclude_sessions": [],
  "sessions": $pins,
  "plans": []
}
\`\`\`
EOF
}

# write_transcript SESSION_ID TIMESTAMP OUTPUT_TOKENS
write_transcript() {
  session_line "$1" "$AT" "$BRANCH" "msg-$1" "$MODEL" "$2" 100 "$3" 0 0 0 \
    > "$PROJECTS/$1.jsonl"
}

capture()   { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self "$SLUG" "$@" 2>&1; }
recapture() { capture --recapture "$@"; }
report()    { HOME="$FAKE_HOME" python3 "$AT/analysis/report.py" --self "$SLUG" 2>&1; }

field() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$PLANNING" "$1"; }
total_of() { field "d['cost_usd']['total']"; }
near()  { python3 -c "import sys; sys.exit(0 if abs(float(sys.argv[1]) - float(sys.argv[2])) < 1e-9 else 1)" "$1" "$2"; }
# carried_from_of SESSION_ID — the row's stamp, or None when the row is not carried.
carried_from_of() { field "next((s.get('carried_from') for s in d['sessions'] if s['session_id']=='$1'), 'absent')"; }
# sessions_of — the session ids in sessions[], sorted.
sessions_of() { field "sorted(s['session_id'] for s in d['sessions'])"; }
# selected_by_of SESSION_ID — the row's `selected_by`.
selected_by_of() { field "next((s.get('selected_by') for s in d['sessions'] if s['session_id']=='$1'), 'absent')"; }

# The claims ledger under the fake HOME (`~/.claude/subagent-claims.json`): its `sessions`
# section maps a session id to a LIST of claims. session_claims SESSION_ID prints the
# sorted (slug, selected_by) pairs claimed for it — what a carried row must still hold.
LEDGER="$FAKE_HOME/.claude/subagent-claims.json"
session_claims() { python3 -c "import json,sys; d=json.load(open(sys.argv[1]))['sessions']; print(sorted((c['slug'], c['selected_by']) for c in d.get(sys.argv[2]) or []))" "$LEDGER" "$1"; }

echo "capture_planning merge into the committed record"

# ── A. round 1 captured in container 1; round 2 runs in container 2 ───────────
write_manifest
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000
capture > "$TMP/outA0.txt"
rcA0=$?
at1="$(field "d['captured_at']")"
cost_a="$(total_of)"
check "A0. the premise: round 1's capture priced its session" \
  "[ $rcA0 -eq 0 ] && python3 -c \"import sys; sys.exit(0 if float('$cost_a') > 0 else 1)\""

# Container 2: A's transcript is gone, B's is here, and planning.json rode the branch.
rm "$PROJECTS/$SESSION_A.jsonl"
write_transcript "$SESSION_B" "2026-07-02T10:00:00.000Z" 7000
recapture > "$TMP/outA.txt"
rcA=$?
check "A1. a plain --recapture with an unreachable priced session WRITES (exit 0)" "[ $rcA -eq 0 ]"
check "A1b. and nothing says REFUSING or --carry-lost" \
  "! grep -q 'REFUSING' '$TMP/outA.txt' && ! grep -q -- '--carry-lost' '$TMP/outA.txt'"
check "A2. the record holds both rounds' sessions" \
  "[ \"\$(sessions_of)\" = \"['$SESSION_A', '$SESSION_B']\" ]"
check "A3. the lost row is carried, stamped with the capture it came from" \
  "[ \"\$(carried_from_of '$SESSION_A')\" = '$at1' ]"
check "A3b. the reachable row carries no stamp" \
  "[ \"\$(carried_from_of '$SESSION_B')\" = None ]"
cost_b="$(field "sum(p['cost_usd'] for p in d['priced'] if p['session_id']=='$SESSION_B')")"
check "A4. the total is round 1's figure plus round 2's" \
  "near '$(total_of)' \"\$(python3 -c 'print($cost_a + $cost_b)')\""
check "A5. the top-level carried_from is the capture the carried row came from" \
  "[ \"\$(field \"d['carried_from']\")\" = '$at1' ]"
check "A6. one WARN names the carried row" \
  "[ \"\$(grep -c 'carried' '$TMP/outA.txt')\" = 1 ] && grep 'carried' '$TMP/outA.txt' | grep -q 'WARN' && grep 'carried' '$TMP/outA.txt' | grep -q '$SESSION_A'"
check "A6b. and the WARN is in planning.json's warnings[] too" \
  "[ \"\$(field \"any('carried' in w and '$SESSION_A' in w for w in d['warnings'])\")\" = True ]"
# A carried row is as claimed as a re-priced one: the ledger names this feature for it.
check "A7. the carried session is claimed by this feature in the ledger, as branch-selected" \
  "[ \"\$(session_claims '$SESSION_A')\" = \"[('$SLUG', 'branch')]\" ]"
check "A7b. beside the session this scan priced" \
  "[ \"\$(session_claims '$SESSION_B')\" = \"[('$SLUG', 'branch')]\" ]"
at_merge1="$(field "d['captured_at']")"

# ── B. a carried row keeps its first stamp ────────────────────────────────────
# Still container 2: a re-run after more work (the close's capture replacing the
# round's own) must not re-stamp A with this capture's date — that is the provenance
# the old `carry_lost_entries` lost.
recapture > "$TMP/outB.txt"
rcB=$?
check "B1. a second merge still writes" "[ $rcB -eq 0 ]"
check "B2. the row carried once keeps its FIRST carried_from" \
  "[ \"\$(carried_from_of '$SESSION_A')\" = '$at1' ]"
check "B2b. not the previous capture's captured_at" "[ '$at1' != '$at_merge1' ]"
check "B3. the reachable row is still unstamped and the total unchanged" \
  "[ \"\$(carried_from_of '$SESSION_B')\" = None ] && near '$(total_of)' \"\$(python3 -c 'print($cost_a + $cost_b)')\""
# The capture that last priced B from its transcript is this one, so it is the stamp B
# gets once it is lost — provenance is the last measurement, not the first appearance.
at2="$(field "d['captured_at']")"

# Container 3: B's transcript is gone too, C's is here.
rm "$PROJECTS/$SESSION_B.jsonl"
write_transcript "$SESSION_C" "2026-07-03T10:00:00.000Z" 9000
recapture > "$TMP/outB4.txt"
rcB4=$?
cost_c="$(field "sum(p['cost_usd'] for p in d['priced'] if p['session_id']=='$SESSION_C')")"
check "B4. the third container's capture writes all three rounds" \
  "[ $rcB4 -eq 0 ] && [ \"\$(sessions_of)\" = \"['$SESSION_A', '$SESSION_B', '$SESSION_C']\" ]"
check "B5. A keeps its first stamp; B is stamped with ITS original capture" \
  "[ \"\$(carried_from_of '$SESSION_A')\" = '$at1' ] && [ \"\$(carried_from_of '$SESSION_B')\" = '$at2' ]"
check "B6. the top-level carried_from is the earliest stamp" \
  "[ \"\$(field \"d['carried_from']\")\" = '$at1' ]"
check "B7. the total chains all three" \
  "near '$(total_of)' \"\$(python3 -c 'print($cost_a + $cost_b + $cost_c)')\""
check "B8. the WARN names both carried rows and both capture dates" \
  "grep 'carried' '$TMP/outB4.txt' | grep -q '$SESSION_A' && grep 'carried' '$TMP/outB4.txt' | grep -q '$SESSION_B' && grep 'carried' '$TMP/outB4.txt' | grep -qF '$at1' && grep 'carried' '$TMP/outB4.txt' | grep -qF '$at2'"
cp "$PLANNING" "$TMP/planning.three.json"

# ── C. merge keeps only what cannot be seen ───────────────────────────────────
# C is reachable and the window is narrowed in front of it: a deliberate deselection,
# dropped and not carried. A and B stay carried — they are still unreachable.
write_manifest "2026-07-03T00:00:00.000Z"
recapture > "$TMP/outC.txt"
rcC=$?
check "C1. a reachable session deselected by a narrowed window is dropped, not carried" \
  "[ $rcC -eq 0 ] && [ \"\$(sessions_of)\" = \"['$SESSION_A', '$SESSION_B']\" ]"
check "C1b. the rows that cannot be seen are still carried, stamps intact" \
  "[ \"\$(carried_from_of '$SESSION_A')\" = '$at1' ] && [ \"\$(carried_from_of '$SESSION_B')\" = '$at2' ]"
check "C1c. and the total drops by exactly the deselected session" \
  "near '$(total_of)' \"\$(python3 -c 'print($cost_a + $cost_b)')\""

# B's transcript is gone AND a usage.json now claims it as a runner session: its dollars
# live in that sidecar, so it is reclassified, not lost, and leaves the record.
write_manifest
mkdir -p "$FEATURE_DIR/auto/complete"
printf '{"plan":"01-x","attempts":[{"session_id":"%s","outcome":"complete","total_cost_usd":1.0}]}\n' \
  "$SESSION_B" > "$FEATURE_DIR/auto/complete/01-x.usage.json"
recapture > "$TMP/outC2.txt"
rcC2=$?
check "C2. a vanished session a usage.json now claims is dropped, not carried" \
  "[ $rcC2 -eq 0 ] && [ \"\$(sessions_of)\" = \"['$SESSION_A', '$SESSION_C']\" ]"
check "C2b. the other unreachable row is still carried" \
  "[ \"\$(carried_from_of '$SESSION_A')\" = '$at1' ]"
rm -rf "$FEATURE_DIR/auto"

# ── D. --force rebuilds from what this scan reaches ───────────────────────────
cp "$TMP/planning.three.json" "$PLANNING"
capture --force > "$TMP/outD.txt"
rcD=$?
check "D1. --force writes" "[ $rcD -eq 0 ]"
check "D2. with only the session this scan reaches" "[ \"\$(sessions_of)\" = \"['$SESSION_C']\" ]"
check "D3. no carried row and no top-level carried_from" \
  "[ \"\$(field \"[s for s in d['sessions'] if s.get('carried_from')]\")\" = '[]' ] && [ \"\$(field \"'carried_from' in d\")\" = False ]"
check "D4. and the carried dollars are gone from the total" "near '$(total_of)' '$cost_c'"
check "D5. nothing was carried, so nothing says so" "! grep -q 'carried' '$TMP/outD.txt'"

# ── E. report.py says the figure is a chain ───────────────────────────────────
cp "$TMP/planning.three.json" "$PLANNING"
report > "$TMP/outE.txt"
rcE=$?
check "E1. report.py renders a record with carried rows" "[ $rcE -eq 0 ] && [ -f '$REPORT_MD' ]"
check "E2. stdout has one line with the count of carried rows and both capture dates" \
  "[ \"\$(grep -c 'carried' '$TMP/outE.txt')\" = 1 ] && grep 'carried' '$TMP/outE.txt' | grep -q '2 ' && grep 'carried' '$TMP/outE.txt' | grep -qF '${at1:0:10}' && grep 'carried' '$TMP/outE.txt' | grep -qF '${at2:0:10}'"
check "E3. report.md carries the same line" \
  "grep -q 'carried' '$REPORT_MD' && grep 'carried' '$REPORT_MD' | grep -qF '${at1:0:10}' && grep 'carried' '$REPORT_MD' | grep -qF '${at2:0:10}'"
check "E4. report.json records the rows and the dates under carried" \
  "[ \"\$(python3 -c \"import json; d=json.load(open('$REPORT_JSON'))['carried']; print(d['rows'], sorted(d['captured_at']))\")\" = \"2 ['$at1', '$at2']\" ]"
# A record with no carried row: no line, no key.
capture --force > /dev/null
report > "$TMP/outE5.txt"
check "E5. a record with no carried row prints no such line and report.json has no key" \
  "! grep -q 'carried' '$TMP/outE5.txt' && ! grep -q 'carried' '$REPORT_MD' && [ \"\$(python3 -c \"import json; print('carried' in json.load(open('$REPORT_JSON')))\")\" = False ]"

# ── F. --carry-lost is a no-op alias ──────────────────────────────────────────
cp "$TMP/planning.three.json" "$PLANNING"
rm -f "$PROJECTS/$SESSION_C.jsonl"
write_transcript "$SESSION_C" "2026-07-03T10:00:00.000Z" 9000
capture --carry-lost > "$TMP/outF.txt"
rcF=$?
check "F1. --carry-lost is still accepted and merges like the default" \
  "[ $rcF -eq 0 ] && [ \"\$(sessions_of)\" = \"['$SESSION_A', '$SESSION_B', '$SESSION_C']\" ] && [ \"\$(carried_from_of '$SESSION_A')\" = '$at1' ]"
HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --help > "$TMP/outF2.txt" 2>&1
check "F2. its help text says it is deprecated and the default" \
  "grep -A3 -- '--carry-lost' '$TMP/outF2.txt' | grep -qi 'deprecated'"

# ── G. a carried PINNED session stays pinned, in the record and in the ledger ─
# A session pinned in the manifest's `sessions` — launched on `main`, so only the pin
# selects it — is carried like any other once its transcript is gone, and its claim in
# the ledger keeps `selected_by: pinned` from the carried row. Before this feature a
# carried session's claim fell back to `branch`; a pin that read as a branch selection is
# what tells the fix from the fallback.
SESSION_D="dddddddd-0000-0000-0000-000000000004"
rm -f "$PLANNING" "$PROJECTS"/*.jsonl
write_manifest "$FAR_TO" "[\"$SESSION_D\"]"
write_transcript "$SESSION_C" "2026-07-03T10:00:00.000Z" 9000
session_line "$SESSION_D" "$AT" "main" "msg-$SESSION_D" "$MODEL" "2026-07-04T10:00:00.000Z" 100 4000 0 0 0 \
  > "$PROJECTS/$SESSION_D.jsonl"
capture > "$TMP/outG0.txt"
rcG0=$?
check "G0. the premise: the pinned session on main is captured as pinned, the branch one as branch" \
  "[ $rcG0 -eq 0 ] && [ \"\$(selected_by_of '$SESSION_D')\" = pinned ] && [ \"\$(selected_by_of '$SESSION_C')\" = branch ]"
atG="$(field "d['captured_at']")"
rm "$PROJECTS/$SESSION_D.jsonl"
recapture > "$TMP/outG.txt"
rcG=$?
check "G1. with its transcript gone the pinned session is carried, still pinned" \
  "[ $rcG -eq 0 ] && [ \"\$(carried_from_of '$SESSION_D')\" = '$atG' ] && [ \"\$(selected_by_of '$SESSION_D')\" = pinned ]"
check "G2. and the ledger's claim for it keeps selected_by pinned, not the branch fallback" \
  "[ \"\$(session_claims '$SESSION_D')\" = \"[('$SLUG', 'pinned')]\" ]"
check "G3. the re-priced session's claim is branch-selected beside it" \
  "[ \"\$(session_claims '$SESSION_C')\" = \"[('$SLUG', 'branch')]\" ]"

echo ""
if (( fails > 0 )); then
  echo "capture-merge: $fails assertion(s) failed"
  exit 1
fi
echo "capture-merge: all assertions passed"
