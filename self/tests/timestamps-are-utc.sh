#!/usr/bin/env bash
set -uo pipefail

# Self-test for the one timestamp convention the analysis scripts run on: every
# instant is normalized to UTC before it is compared, sorted, or turned into a
# pricing date. Run by self/gate.sh, or by hand: bash self/tests/timestamps-are-utc.sh
#
# Why this exists. Session transcripts carry ISO 8601 timestamps that are UTC with a
# `Z` today, but the scripts treated them as *strings* — `timestamp[:10]` for the
# pricing date, `min()`/`max()` for a session's span, and lexicographic `<`/`>=` for
# session_window membership. All three are correct only while every string happens to
# be same-shape UTC, and nothing declared or enforced that:
#
#   - an offset timestamp ("...T23:00:00-04:00") slices to the LOCAL date, which is the
#     previous day in UTC — and the pricing date selects the rate tier, so that is a
#     dollar error, not a cosmetic one;
#   - string min() across mixed formats picks the wrong instant as the session start,
#     and the start is what session_window membership is decided on;
#   - a session_window bound is written by a human, often read off `git log`, which
#     prints LOCAL time — so a bound meaning 20:00 EDT silently filtered at 20:00 UTC,
#     four hours off.
#
# The convention under test: transcript timestamps and window bounds are parsed into
# aware UTC datetimes; a bound with no offset is interpreted as UTC (which is what the
# committed corpus already means, so this preserves it) and one with an explicit offset
# is converted.
#
# Asserts, in order:
#   1. utc_date() on a Z timestamp is its date;
#   2. utc_date() on an offset timestamp that crosses midnight is the UTC date, not the
#      local one ("2026-07-01T23:00:00-04:00" -> 2026-07-02);
#   3. a session's start is the earliest INSTANT, not the lexicographically smallest
#      string, across mixed formats;
#   4. a window bound with an explicit offset selects exactly what its UTC equivalent
#      selects;
#   5. a bound with no offset is interpreted as UTC (the committed corpus's meaning);
#   6. two windows chained at the same instant but written in different formats are
#      disjoint — no false overlap warning;
#   7. the rate tier follows the UTC date: a session at 2026-08-21T23:00:00-04:00 is
#      2026-08-22 UTC and prices at sonnet-5's intro tier, 2/3 of standard. Under the
#      old local-date slicing it priced standard, so this assertion is worth real money;
#   8. pricing.utc_today() is UTC, not local: it returns the same date under TZ=UTC+14
#      and TZ=UTC-11, whose local dates always differ (their offsets span 25 hours);
#   9. a session_window bound with no zone is WARNED about — silently reading it as UTC
#      is what let a bound copied from `git log` (local time) mean something four hours
#      off — while a Z-suffixed or explicit-offset bound is not warned about, and a
#      *sibling* manifest's naive bound is not warned about either (the author can only
#      fix their own manifest, so warning about someone else's is noise).
#
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Physical path — roots.py resolves AGENT_TOOLING_DIR through Path.resolve(), and an
# unresolved /var/... fixture path matches no transcript (see capture-guard.sh).
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features" "$AT/.git"

for f in pricing.py roots.py transcript.py capture_planning.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

SLUG="tz"
FEATURE_DIR="$AT/self/features/$SLUG"
BRANCH="tzBranch"
MODEL="claude-sonnet-5"
FAKE_HOME="$TMP/home"
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/' '-')"
mkdir -p "$PROJECTS" "$FEATURE_DIR"

write_manifest() {
  local frm="${1:-null}" to="${2:-null}"
  [ "$frm" != "null" ] && frm="\"$frm\""
  [ "$to" != "null" ] && to="\"$to\""
  cat > "$FEATURE_DIR/README.md" <<EOF
# $SLUG

\`\`\`json
{
  "slug": "$SLUG",
  "branches": ["$BRANCH"],
  "session_window": {"from": $frm, "to": $to},
  "exclude_sessions": []
}
\`\`\`
EOF
}

# Each phase below starts from no prior capture. Without this the frozen-cost guard
# (capture-guard.sh) correctly refuses the write as soon as an earlier phase's
# transcript is removed, and the assertion then reads the stale file.
reset_capture() { rm -f "$FEATURE_DIR/planning.json"; }
# --recapture on every call: capture skips a feature that already has a planning.json
# (capture-guard.sh covers that), and several phases below capture repeatedly under
# different manifests without a reset in between — each of those must actually re-scan,
# or the assertion reads the previous phase's file.
capture() { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self "$SLUG" --recapture "$@" 2>&1; }
sessions_count() { python3 -c "import json;print(len(json.load(open('$FEATURE_DIR/planning.json'))['sessions']))"; }
total_of() { python3 -c "import json;print(json.load(open('$FEATURE_DIR/planning.json'))['cost_usd']['total'])"; }

echo "timestamps are UTC"

# ── 1-2. utc_date normalizes to the UTC calendar day ──────────────────────────
check "1. utc_date on a Z timestamp is its date" \
  "[ \"\$(cd '$AT/analysis' && python3 -c \"import transcript;print(transcript.utc_date('2026-07-01T10:00:00.000Z'))\" 2>/dev/null)\" = '2026-07-01' ]"
check "2. utc_date on an offset crossing midnight is the UTC date" \
  "[ \"\$(cd '$AT/analysis' && python3 -c \"import transcript;print(transcript.utc_date('2026-07-01T23:00:00-04:00'))\" 2>/dev/null)\" = '2026-07-02' ]"

# ── 3. session start is the earliest instant, not the smallest string ─────────
# "2026-08-21T23:00:00-04:00" is 2026-08-22T03:00Z, LATER than "2026-08-22T01:00:00Z",
# but sorts first as a string. The captured date must come from the instant.
SID_MIX="mixed000-0000-0000-0000-000000000001"
write_manifest
{
  session_line "$SID_MIX" "$AT" "$BRANCH" "m1" "$MODEL" "2026-08-22T01:00:00.000Z" 10 10 0 0 0
  session_line "$SID_MIX" "$AT" "$BRANCH" "m2" "$MODEL" "2026-08-21T23:00:00-04:00" 10 10 0 0 0
} > "$PROJECTS/$SID_MIX.jsonl"
capture > /dev/null
check "3. session start is the earliest instant across mixed formats" \
  "[ \"\$(python3 -c \"import json;print(json.load(open('$FEATURE_DIR/planning.json'))['sessions'][0]['date'])\" 2>/dev/null)\" = '2026-08-22' ]"
rm -f "$PROJECTS/$SID_MIX.jsonl"

# ── 4-5. window bounds are UTC, offset-aware ─────────────────────────────────
# One session at 2026-07-17T22:00:00Z. A `to` bound of 2026-07-17T18:00:00-04:00 is the
# same instant as 2026-07-17T22:00:00Z, so the half-open window must EXCLUDE it either way.
reset_capture
SID_W="window00-0000-0000-0000-000000000002"
write_transcript_w() { session_line "$SID_W" "$AT" "$BRANCH" "w1" "$MODEL" "2026-07-17T22:00:00.000Z" 10 10 0 0 0 > "$PROJECTS/$SID_W.jsonl"; }
write_transcript_w

write_manifest null "2026-07-17T22:00:00Z"; capture > /dev/null; utc_excl="$(sessions_count)"
write_manifest null "2026-07-17T18:00:00-04:00"; capture > /dev/null; off_excl="$(sessions_count)"
check "4. an offset bound selects what its UTC equivalent selects" \
  "[ '$utc_excl' = '$off_excl' ] && [ '$utc_excl' = '0' ]"

write_manifest null "2026-07-17T22:00:00"; capture > /dev/null; naive_excl="$(sessions_count)"
check "5. a bound with no offset is interpreted as UTC" \
  "[ '$naive_excl' = '$utc_excl' ]"
rm -f "$PROJECTS/$SID_W.jsonl"

# ── 6. chained windows in different formats do not overlap ───────────────────
# Sibling feature ends where this one begins, written in the other format.
reset_capture
SIB="$AT/self/features/tz-sibling"; mkdir -p "$SIB"
cat > "$SIB/README.md" <<'EOF'
# tz-sibling

```json
{
  "slug": "tz-sibling",
  "branches": ["tzBranch"],
  "session_window": {"from": null, "to": "2026-07-17T18:00:00-04:00"},
  "exclude_sessions": []
}
```
EOF
write_manifest "2026-07-17T22:00:00Z" null
capture > "$TMP/out6.txt"
check "6. windows chained across formats raise no overlap warning" \
  "! grep -q 'overlap' '$TMP/out6.txt'"
rm -rf "$SIB"

# ── 7. the rate tier follows the UTC date ────────────────────────────────────
# sonnet-5's intro window starts 2026-08-22. A session at 2026-08-21T23:00:00-04:00 is
# 2026-08-22T03:00Z, so it prices intro (2/3 of standard). Slicing the local date gives
# 2026-08-21 and prices standard.
reset_capture
SID_T="tier0000-0000-0000-0000-000000000003"
write_manifest
session_line "$SID_T" "$AT" "$BRANCH" "t1" "$MODEL" "2026-08-21T23:00:00-04:00" 1000000 0 0 0 0 \
  > "$PROJECTS/$SID_T.jsonl"
capture > /dev/null
tier_total="$(total_of)"
check "7. an offset session crossing into the intro window prices intro" \
  "python3 -c \"import sys;sys.exit(0 if abs(float('$tier_total') - 2.0) < 1e-9 else 1)\""
check "7b. the applied tier is recorded as intro" \
  "[ \"\$(python3 -c \"import json;print(json.load(open('$FEATURE_DIR/planning.json'))['priced'][0]['rates_applied']['tier'])\" 2>/dev/null)\" = 'intro' ]"
rm -f "$PROJECTS/$SID_T.jsonl"

# ── 8. utc_today is UTC, not local ───────────────────────────────────────────
# UTC+14 and UTC-11 span 25 hours, so their LOCAL dates differ at every instant. A
# UTC-based answer is identical under both; a date.today()-based one never is.
a="$(cd "$AT/analysis" && TZ=Pacific/Kiritimati python3 -c "import pricing;print(pricing.utc_today())" 2>/dev/null)"
b="$(cd "$AT/analysis" && TZ=Pacific/Midway    python3 -c "import pricing;print(pricing.utc_today())" 2>/dev/null)"
check "8. utc_today is identical under UTC+14 and UTC-11" \
  "[ -n '$a' ] && [ '$a' = '$b' ]"

# ── 9. a bound with no zone is called out ────────────────────────────────────
reset_capture
rm -f "$PROJECTS"/*.jsonl
write_manifest "2026-07-17T22:00:00" null
capture > "$TMP/out9a.txt"
check "9. a naive bound warns that it is being read as UTC" \
  "grep -qi 'no timezone\|without a timezone\|read as UTC' '$TMP/out9a.txt'"
check "9b. the warning names the offending field and value" \
  "grep -q 'session_window.from' '$TMP/out9a.txt' && grep -q '2026-07-17T22:00:00' '$TMP/out9a.txt'"

reset_capture
write_manifest "2026-07-17T22:00:00Z" null
capture > "$TMP/out9b.txt"
check "9c. a Z-suffixed bound is not warned about" \
  "! grep -qi 'no timezone\|without a timezone\|read as UTC' '$TMP/out9b.txt'"

reset_capture
write_manifest "2026-07-17T18:00:00-04:00" null
capture > "$TMP/out9c.txt"
check "9d. an explicit-offset bound is not warned about" \
  "! grep -qi 'no timezone\|without a timezone\|read as UTC' '$TMP/out9c.txt'"

# A sibling manifest's naive bound is that author's to fix, not this capture's noise.
reset_capture
SIB2="$AT/self/features/tz-naive-sibling"; mkdir -p "$SIB2"
cat > "$SIB2/README.md" <<'EOF'
# tz-naive-sibling

```json
{
  "slug": "tz-naive-sibling",
  "branches": ["someOtherBranch"],
  "session_window": {"from": "2026-01-01T00:00:00", "to": null},
  "exclude_sessions": []
}
```
EOF
write_manifest "2026-07-17T22:00:00Z" null
capture > "$TMP/out9d.txt"
check "9e. a sibling manifest's naive bound is not warned about" \
  "! grep -q '2026-01-01T00:00:00' '$TMP/out9d.txt'"
rm -rf "$SIB2"

echo
if [ "$fails" -eq 0 ]; then
  echo "timestamps-are-utc: all checks passed"
else
  echo "timestamps-are-utc: $fails check(s) failed"
fi
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
