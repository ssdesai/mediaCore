#!/usr/bin/env bash
set -uo pipefail

# Unit test for plan-runner-roots.sh's round readers — report_verdict,
# latest_review_plan and completed_review_count — and, since round 2, its stray-records
# reader stray_paths (with stray_labels, which derives the four globals stray_paths
# reads) — all called DIRECTLY, with no runner
# (self/features/lifecycle-records-and-numbering/README.md, slice A2; the stray phase is
# round 2's escalation, escalations/01-review-opus.md). Run by self/gate.sh, or by hand:
# bash self/tests/verdict-readers.sh
#
# Every other test drives the first three through a whole lifecycle run, where the
# report's first line is always one of two exact strings and every stem is one width, and
# every caller of stray_paths calls stray_labels first. Three rules these readers
# implement are invisible from there, and all three are the kind a "simplification" would
# delete without failing anything:
#
#   - the verdict is the report's FIRST LINE and nothing else. A review report says
#     "clean" and "escalated" all through its prose, so a reader rewritten as a `grep`
#     would pass every lifecycle assertion and read a verdict out of a sentence;
#   - that line is matched with its surrounding space, its `\r` and its case folded away,
#     so a report opening `  VERDICT:  CLEAN ` (CRLF, a shouting executor) is the clean
#     verdict it plainly is rather than an unreadable one;
#   - stray_paths refuses to judge — returning STRAY_UNJUDGED_RC rather than an empty
#     "nothing is stray" — when FEATURE_REL/FEATURES_REL/STRAY_SLUG have not
#     been derived by stray_labels. Every lifecycle test calls stray_labels before
#     stray_paths, so a caller that dropped the call would pass every one of them and
#     still read a dirty tree as clean; this is the only assertion that would notice.
#
# And latest_review_plan orders stems by their LEADING NUMBER, not lexically: a feature
# whose own numbering has passed 99 holds stems of two widths, where "98-review-opus"
# sorts above "101-review-sonnet" as a string and would hand the close the wrong round's
# verdict.
#
# The seam is FEATURES_DIR for the round readers, and REPO_DIR/FEATURES_LABEL for
# stray_labels. resolve_roots derives all three from this checkout's own location, which
# would point every reader at the real corpus; nothing under test calls resolve_roots
# itself, so this script sources the file and then sets its own mktemp -d corpus and its
# own REPO_DIR/FEATURES_LABEL by hand — simpler than staging a whole fake checkout for
# resolve_roots to find, and the only globals these readers touch. No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Sourced BEFORE FEATURES_DIR is set, never after: the file assigns its roots only from
# inside resolve_roots today, but a later edit that set one at source time would silently
# point every reader below at this checkout's real corpus — where the fixture slug holds
# no review at all, so every assertion would still pass and assert nothing.
# shellcheck source=/dev/null
source "$HERE/plan-runner-roots.sh" 2>/dev/null || true
if ! declare -f report_verdict >/dev/null; then
  echo "  FAIL  plan-runner-roots.sh did not define report_verdict — nothing below can run"
  exit 1
fi

# The corpus the readers walk, and the one feature in it. Both readers take the slug and
# build <FEATURES_DIR>/<slug>/review/{complete,failed} from it.
SLUG="verdict-readers"
FEATURES_DIR="$TMP/features"
COMPLETE="$FEATURES_DIR/$SLUG/review/complete"
FAILED="$FEATURES_DIR/$SLUG/review/failed"
mkdir -p "$COMPLETE" "$FAILED"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "verdict readers"

# ── report_verdict: the first line, and only the first line ───────────────────
REPORT="$TMP/review-report.md"

printf 'Verdict: clean\n\nEverything the manifest asked for is here.\n' > "$REPORT"
check "V1. a plain 'Verdict: clean' first line reads clean (got $(report_verdict "$REPORT"))" \
  '[[ "$(report_verdict "$REPORT")" == "$VERDICT_CLEAN" ]]'

printf 'Verdict: escalated\n\nTwo findings are structural.\n' > "$REPORT"
check "V2. 'Verdict: escalated' reads escalated (got $(report_verdict "$REPORT"))" \
  '[[ "$(report_verdict "$REPORT")" == "$VERDICT_ESCALATED" ]]'

# The defect a `grep` would ship: the verdict word is all over a real report's prose.
printf 'This review read the diff against main and found nothing blocking.\n\nVerdict: clean\n' \
  > "$REPORT"
check "V3. a prose first line reads unreadable though the BODY says 'Verdict: clean' (got $(report_verdict "$REPORT"))" \
  '[[ "$(report_verdict "$REPORT")" == "$VERDICT_UNREADABLE" ]]'

# A CRLF report from a shouting executor: leading space, upper case, trailing space, \r.
printf '  VERDICT:  CLEAN \r\n\nThe body.\n' > "$REPORT"
check "V4. '  VERDICT:  CLEAN ' with a trailing CR reads clean (got $(report_verdict "$REPORT"))" \
  '[[ "$(report_verdict "$REPORT")" == "$VERDICT_CLEAN" ]]'

printf 'Verdict: probably fine\n' > "$REPORT"
check "V5. a verdict word the vocabulary does not hold reads unreadable (got $(report_verdict "$REPORT"))" \
  '[[ "$(report_verdict "$REPORT")" == "$VERDICT_UNREADABLE" ]]'

check "V6. a report that does not exist reads unreadable (got $(report_verdict "$TMP/no-such-report.md"))" \
  '[[ "$(report_verdict "$TMP/no-such-report.md")" == "$VERDICT_UNREADABLE" ]]'

# ── latest_review_plan: highest by leading number, over complete/ and failed/ ──
check "L0. no review filed yet: latest_review_plan is empty, the count is 0" \
  '[[ -z "$(latest_review_plan "$SLUG")" && "$(completed_review_count "$SLUG")" == "0" ]]'

echo "round 98" > "$COMPLETE/98-review-opus.md"
echo "round 101" > "$COMPLETE/101-review-sonnet.md"
check "L1. with 98 and 101 both complete, the 101 stem is the latest — numerically, not lexically (got $(latest_review_plan "$SLUG"))" \
  '[[ "$(latest_review_plan "$SLUG")" == "101-review-sonnet" ]]'
check "L2. ... and both count toward the round (got $(completed_review_count "$SLUG"))" \
  '[[ "$(completed_review_count "$SLUG")" == "2" ]]'

# A review whose budget cap fired AFTER it wrote its report is filed to failed/ with a
# complete verdict: the close must read it, and the round must not advance for it.
echo "round 102, capped after its report" > "$FAILED/102-review-sonnet.md"
check "L3. the highest stem in failed/ is what latest_review_plan returns (got $(latest_review_plan "$SLUG"))" \
  '[[ "$(latest_review_plan "$SLUG")" == "102-review-sonnet" ]]'
check "L4. ... and it does NOT count toward the round (got $(completed_review_count "$SLUG"))" \
  '[[ "$(completed_review_count "$SLUG")" == "2" ]]'
check "L5. next_round is the completed count plus one (got $(next_round "$SLUG"))" \
  '[[ "$(next_round "$SLUG")" == "3" ]]'

# The harness's own live log beside a plan, which is neither a plan nor a round.
echo "a progress log" > "$COMPLETE/103-review-opus.progress.md"
echo "a progress log" > "$FAILED/104-review-opus.progress.md"
check "L6. a .progress.md in complete/ or failed/ is not a plan (got $(latest_review_plan "$SLUG"))" \
  '[[ "$(latest_review_plan "$SLUG")" == "102-review-sonnet" ]]'
check "L7. ... and is not counted (got $(completed_review_count "$SLUG"))" \
  '[[ "$(completed_review_count "$SLUG")" == "2" ]]'

# `10#` is not decoration: bash reads a leading zero as octal, and `08` aborts the caller.
echo "an early round" > "$FAILED/08-review-opus.md"
check "L8. an 08 stem neither wins nor aborts the reader on octal (got $(latest_review_plan "$SLUG"))" \
  '[[ "$(latest_review_plan "$SLUG")" == "102-review-sonnet" ]]'

check "L9. an unknown slug is empty, not an error" \
  '[[ -z "$(latest_review_plan "no-such-feature")" && "$(completed_review_count "no-such-feature")" == "0" ]]'

# ── stray_paths: fails closed when stray_labels has not derived its labels ────
# Round 2's escalation (escalations/01-review-opus.md): stray_paths used to read
# FEATURE_REL/FEATURES_REL/STRAY_SLUG as plain globals with no guard, so a
# caller that skipped stray_labels hit `set -u` inside the command substitution wrapping
# the call — only that subshell died, STRAY came back empty, and every caller read empty
# as "nothing is stray." The fix checks each of them before the loop and returns
# STRAY_UNJUDGED_RC, naming stray_labels on stderr, rather than trusting set -u to fail
# loudly on its own. (There were four labels until the routing record moved inside the
# feature directory — `ROUTING_REL` was the fourth, and its one arm of the reader went
# with it: a routing record is a cost record of its feature now, S7 below.)
echo
echo "stray reader"

STRAY_PATH="self/features/x/NOTES.md.tmp"
STRAY_LINE="?? $STRAY_PATH"
STRAY_ERR="$TMP/stray.err"

# S1/S2: called cold — nothing above this line in the whole script has called
# stray_labels, so FEATURE_REL and friends are genuinely unset. Must fail closed.
STRAY_OUT="$(stray_paths "$STRAY_LINE" "" 2>"$STRAY_ERR")"
STRAY_RC=$?
check "S1. stray_paths called without stray_labels returns non-zero (rc $STRAY_RC)" \
  '(( STRAY_RC != 0 ))'
check "S2. ... and its stderr names stray_labels (got: $(cat "$STRAY_ERR"))" \
  'grep -q "stray_labels" "$STRAY_ERR"'

# Now derive the labels the way both real callers do, for a --self-shaped checkout:
# REPO_DIR equal to the checkout itself, so the status-line prefix is bare
# "self/features/..." with no leading repo directory (resolve_roots' own --self shape,
# stood up by hand since this script never calls resolve_roots — see header).
REPO_DIR="$TMP/checkout"
FEATURES_LABEL="self/features"
stray_labels x "$TMP/checkout"

# S3/S4: the same input, now judged, returns 0 and reports the path as stray — it is
# nobody's cost record.
STRAY_OUT="$(stray_paths "$STRAY_LINE" "")"
STRAY_RC=$?
check "S3. after stray_labels, the same input returns 0 (rc $STRAY_RC)" \
  '(( STRAY_RC == 0 ))'
check "S4. ... and reports the path as stray (got: $STRAY_OUT)" \
  '[[ "$STRAY_OUT" == "$STRAY_PATH" ]]'

# S5/S6: a cost-record path under the same feature directory returns 0 and prints
# nothing — the ordinary "nothing is stray" case, now that it can be trusted.
COST_LINE="?? self/features/x/planning.json"
STRAY_OUT2="$(stray_paths "$COST_LINE" "")"
STRAY_RC2=$?
check "S5. a cost-record path returns 0 (rc $STRAY_RC2)" \
  '(( STRAY_RC2 == 0 ))'
check "S6. ... and reports nothing (got: $STRAY_OUT2)" \
  '[[ -z "$STRAY_OUT2" ]]'

# S7/S8: the routing record is a cost record of the feature it links now
# (self/DESIGN-2026-09-18-ledger-and-routing.md §1) — `routing.json` is in COST_FILES, so
# the capture may commit its own feature's copy, while a sibling's is a stranger's work
# like any other file under a sibling's directory.
ROUTING_LINE="?? self/features/x/routing.json"
STRAY_OUT3="$(stray_paths "$ROUTING_LINE" "")"
check "S7. this feature's routing.json is a cost record, not stray (got: $STRAY_OUT3)" \
  '[[ -z "$STRAY_OUT3" ]]'
SIBLING_ROUTING="self/features/other/routing.json"
STRAY_OUT4="$(stray_paths "?? $SIBLING_ROUTING" "")"
check "S8. ... while another feature's copy is (got: $STRAY_OUT4)" \
  '[[ "$STRAY_OUT4" == "$SIBLING_ROUTING" ]]'

echo
if (( fails > 0 )); then echo "verdict-readers: $fails assertion(s) FAILED"; exit 1; fi
echo "verdict-readers: all assertions passed"
