#!/usr/bin/env bash
set -uo pipefail

# Self-test for the Cost and Time tables' unpriced/undurated bucket marks
# (self/features/tooling-backlog-2026-09-06/README.md, items 5 and 6). Run by
# self/gate.sh, or by hand: bash self/tests/report-footnotes.sh
#
# Same scaffolding as stale-failed-sidecars.sh — copies of `analysis/pricing.py`,
# `roots.py`, `transcript.py` and `report.py` into a throwaway agentTooling checkout
# under mktemp -d, plus a synthesized `self/features/` corpus of hand-written manifests,
# `planning.json` files, plan `.md` files and `usage.json` sidecars. No transcripts, no
# model, no network: every dollar is a literal in a sidecar, which is what report.py's
# no-recompute contract says it reads. Its own file rather than a phase of that one
# because the subject is different: that file is about which sidecar the index picks,
# this one about what the two tables say when a figure is missing.
#
# The defect (self/BACKLOG.md, both raised by `recover-cost-at-close`):
#   - `recover-cost-at-close` fixed the cost line `feature-close.sh` PRINTS
#     (`review $0.0000 (0.0%, unpriced: <stem> — …)`) and added an **Unpriced plans**
#     paragraph below the Cost table, but the table cell itself stayed a bare `$0.0000`.
#     Anyone quoting a bucket figure out of the table — which the close's own closing
#     line tells them to do — was quoting the same misleading zero, one file over.
#   - The time roll-up had no equivalent of `cost.unpriced_plans[]` at all: a plan that
#     ran for eight minutes with a null `duration_ms` contributed `0.0` to its bucket
#     with nothing beside it. The dollars said why they were missing and the minutes
#     did not.
#
# Asserts, in order:
#   1. a review plan that ran and carries no `total_cost_usd` marks its Cost row: the
#      review cell is no longer exactly `$0.0000`, it carries the mark, a footnote
#      directly under the table names the stem and the reason, and the separate
#      **Unpriced plans** paragraph is REPLACED rather than duplicated;
#   2. ...while the buckets that simply had no work are unmarked, so the mark means
#      "unpriced" and not "zero";
#   3. a priced feature's Cost table carries no mark and no footnote at all;
#   4. a review plan with a null `duration_ms` marks its Time row the same way, with a
#      footnote naming the plan, and `time.missing_duration_plans[]` carries the
#      `{plan, queue, reason}` shape `cost.unpriced_plans[]` does — both reason
#      branches, since a single return value must not satisfy them both;
#   5. a feature whose plans carry durations has an unmarked Time table and an empty
#      `missing_duration_plans[]`;
#   6. a plan whose `duration_ms` is null but whose attempt carries a
#      `recovered_duration_s` contributes that span to its bucket and to the total,
#      is listed under `time.recovered_duration_plans[]` with the `{plan, queue, reason}`
#      shape plus `recovered_s`, is NOT also listed under `missing_duration_plans[]`,
#      and is marked `‡` — a second mark, because `†` means "no figure" and this row has
#      one — with a footnote naming the plan, the seconds and that it is a transcript
#      span. `total_is_partial` stays true: a transcript span is not a wall clock
#      (self/features/recovered-duration-lower-bound/README.md, item 1 points 3 and 4);
#   7. a plan whose transcript is gone renders exactly as it did before item 1 — `†`,
#      the missing-duration footnote, and no `‡` anywhere.
#
# RED until items 5 and 6 land: phase 1 finds a bare `| review | $0.0000 | 0.0% |` and
# an **Unpriced plans** paragraph, phase 4 finds a bare `| review | 0.0 |` and a list of
# stems where the dicts should be. Phase 6 was RED until recovered-duration-lower-bound
# landed: the recovered span was on the attempt and no table read it. A missing analysis
# script is tolerated rather than fatal, the cost-recovery.sh convention.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/report-footnotes.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

for f in pricing.py roots.py transcript.py report.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "report-footnotes"

# The one dollar figure and the one duration these fixtures use. Distinct from each
# other and from any total below, so no assertion can pass by coincidence.
PRICED_COST="2.5"
PRICED_MS="480000"          # eight minutes — the backlog entry's own example
# The mark the two tables share. One glyph, asserted by value here so a change to it is
# a visible change to both tables at once.
MARK="†"
# The Time table's second mark, and the reason there are two: `†` says the bucket has no
# figure, `‡` says it has one and it is a lower bound. Asserted by value for the same
# reason MARK is.
RECOVERED_MARK="‡"
# The recovered span one attempt below carries, in seconds and in the minutes the table
# renders it as. Distinct from PRICED_MS's eight minutes, so 6c cannot pass by reading
# the wrong fixture.
RECOVERED_S="450.0"
RECOVERED_MIN="7.5"

# ── Fixture helpers ───────────────────────────────────────────────────────────

# feature_dir <slug> — the throwaway feature, with the manifest and planning.json
# report.py needs before it reads anything else. planning.json's total is 0.0 so every
# dollar below comes from a usage.json.
feature_dir() {
  local slug="$1" dir="$AT/self/features/$1"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<MDEOF
# $slug

Test fixture only, for self/tests/report-footnotes.sh.

\`\`\`json
{"plans": ["01-review-opus"]}
\`\`\`
MDEOF
  cat > "$dir/planning.json" <<'JSONEOF'
{"cost_usd": {"total": 0.0, "total_is_partial": false}}
JSONEOF
  echo "$dir"
}

plan_md() {
  cat > "$1" <<'MDEOF'
# 01-review-opus

Test fixture plan for report-footnotes.sh. Not a real plan.
MDEOF
}

# usage_json <path> <total_cost_usd|null> <duration_ms|null> <result_event|null> — the
# sidecar shape write_usage_sidecar writes. `result_event` is what both reason functions
# read: `"missing"` is what a stream that lost its result event leaves, and the literal
# `null` writes no such key at all, which is the shape every sidecar committed before
# the field existed still has.
usage_json() {
  local path="$1" cost="$2" duration="$3" result_event="$4"
  local event_line=""
  if [[ "$result_event" != "null" ]]; then
    event_line="  \"result_event\": \"$result_event\","
  fi
  cat > "$path" <<JSONEOF
{
  "plan": "01-review-opus",
  "model": "opus",
  "outcome": "complete",
  "session_id": "sess-$(basename "$(dirname "$path")")",
$event_line
  "subtype": null,
  "is_error": null,
  "num_turns": null,
  "duration_ms": $duration,
  "total_cost_usd": $cost,
  "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0},
  "model_usage": {},
  "permission_denials": 0,
  "tool_counts": {},
  "files_edited": [],
  "edit_count": 0,
  "attempts": [
    {"session_id": "sess-$(basename "$(dirname "$path")")", "outcome": "complete", "total_cost_usd": $cost, "num_turns": null, "duration_ms": $duration}
  ]
}
JSONEOF
}

# recovered_usage_json <path> <total_cost_usd|null> <recovered_duration_s> — the sidecar
# `recover_attempts.py` leaves behind once it has priced an attempt AND bounded it from
# the same transcript: `duration_ms` still null (the CLI never reported one and a
# recovered figure never becomes a measured one), `recovered_duration_s` on the attempt
# and summed at the top level. See analysis/README.md → usage.json.
recovered_usage_json() {
  local path="$1" cost="$2" recovered="$3"
  local sid="sess-$(basename "$(dirname "$path")")"
  cat > "$path" <<JSONEOF
{
  "plan": "01-review-opus",
  "model": "opus",
  "outcome": "complete",
  "session_id": "$sid",
  "result_event": "missing",
  "subtype": null,
  "is_error": null,
  "num_turns": null,
  "duration_ms": null,
  "total_cost_usd": $cost,
  "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0},
  "model_usage": {},
  "permission_denials": 0,
  "tool_counts": {},
  "files_edited": [],
  "edit_count": 0,
  "attempts": [
    {"session_id": "$sid", "outcome": "complete", "total_cost_usd": $cost, "num_turns": null, "duration_ms": null, "recovered_duration_s": $recovered, "recovered_from": "transcript"}
  ],
  "recovered_duration_s": $recovered
}
JSONEOF
}

# review_feature <slug> <cost|null> <duration_ms|null> <result_event|null> — a feature
# whose ONLY plan is a review plan the runner filed complete, with the four files it
# leaves behind. Prints the feature directory.
review_feature() {
  local dir
  dir="$(feature_dir "$1")"
  mkdir -p "$dir/review/complete"
  plan_md "$dir/review/complete/01-review-opus.md"
  echo "review pass complete" > "$dir/review/complete/01-review-opus.progress.md"
  usage_json "$dir/review/complete/01-review-opus.usage.json" "$2" "$3" "$4"
  echo "$dir"
}

# ── Python verification helper ────────────────────────────────────────────────
# JSON parsing belongs in Python, not bash.
cat > "$TMP/verify.py" <<'PYEOF'
import json
import sys


def load(path):
    with open(path) as f:
        return json.load(f)


def get_path(data, dotted):
    cur = data
    for part in dotted.split("."):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(part)
    return cur


def cmd_field_equals(args):
    report_path, dotted, expected_json = args
    print(get_path(load(report_path), dotted) == json.loads(expected_json))


COMMANDS = {"field_equals": cmd_field_equals}

if __name__ == "__main__":
    COMMANDS[sys.argv[1]](sys.argv[2:])
PYEOF

V() { python3 "$TMP/verify.py" "$@" 2>/dev/null; }
report_for() { python3 "$AT/analysis/report.py" "$1" --self >/dev/null 2>&1; }

# ── 1 + 2: an unpriced review plan marks its Cost row ─────────────────────────
D1="$(review_feature rf-unpriced null null missing)"
report_for rf-unpriced
rc1=$?
check "1a. an unpriced review plan reports cleanly (report.py exit $rc1)" '(( rc1 == 0 ))'
R1="$D1/report.json"
M1="$D1/report.md"
r1b="$(V field_equals "$R1" cost.unpriced_plans '[{"plan": "01-review-opus", "queue": "review", "reason": "no result event", "recovery": "transcript not found"}]')"
check "1b. cost.unpriced_plans names the plan, its queue and its reason (got $r1b)" '[[ "$r1b" == "True" ]]'
check "1c. the review row is no longer the bare zero the defect printed" '! grep -qF "| review | \$0.0000 | 0.0% |" "$M1"'
check "1d. ...it carries the mark in the dollar cell" 'grep -qF "| review | \$0.0000 $MARK | 0.0% |" "$M1"'
check "1e. ...and a footnote names the bucket, the stem and the reason" 'grep -qF "$MARK review: unpriced 01-review-opus — no result event" "$M1"'
check "1f. ...replacing the Unpriced plans paragraph rather than duplicating it" '! grep -qF "**Unpriced plans:**" "$M1"'
# The mark means "unpriced", not "zero": build and verify really did cost nothing here,
# and marking them too would make the mark worthless.
check "2a. the build row, genuinely empty, is unmarked" 'grep -qF "| build | \$0.0000 | 0.0% |" "$M1"'
check "2b. the verify row, genuinely empty, is unmarked" 'grep -qF "| verify | \$0.0000 | 0.0% |" "$M1"'

# ── 3: a fully priced feature carries no mark at all ──────────────────────────
D3="$(review_feature rf-priced "$PRICED_COST" "$PRICED_MS" seen)"
report_for rf-priced
rc3=$?
check "3a. a priced feature reports cleanly (report.py exit $rc3)" '(( rc3 == 0 ))'
M3="$D3/report.md"
r3b="$(V field_equals "$D3/report.json" cost.unpriced_plans '[]')"
check "3b. cost.unpriced_plans is empty (got $r3b)" '[[ "$r3b" == "True" ]]'
check "3c. the review row carries its dollars and no mark" 'grep -qF "| review | \$2.5000 | 100.0% |" "$M3"'
check "3d. ...and there is no footnote anywhere in the report" '! grep -qF "$MARK review:" "$M3"'

# ── 4: a null duration_ms marks the Time row the same way ─────────────────────
# The dollars are real here and the minutes are not, which is the whole point: without
# the mark the Time table's review row reads `0.0` beside $2.5000 and nothing says why.
D4="$(review_feature rf-noduration "$PRICED_COST" null missing)"
report_for rf-noduration
rc4=$?
check "4a. a null-duration review plan reports cleanly (report.py exit $rc4)" '(( rc4 == 0 ))'
R4="$D4/report.json"
M4="$D4/report.md"
r4b="$(V field_equals "$R4" time.missing_duration_plans '[{"plan": "01-review-opus", "queue": "review", "reason": "no result event"}]')"
check "4b. time.missing_duration_plans carries the {plan, queue, reason} shape (got $r4b)" '[[ "$r4b" == "True" ]]'
check "4c. the Time table's review row carries the mark" 'grep -qF "| review | 0.0 $MARK |" "$M4"'
check "4d. ...and a footnote names the bucket, the plan and the reason" 'grep -qF "$MARK review: no duration for 01-review-opus — no result event" "$M4"'
check "4e. ...while the Cost table's review row is priced and unmarked" 'grep -qF "| review | \$2.5000 | 100.0% |" "$M4"'

# The other reason branch, from the shape every sidecar committed before `result_event`
# existed still has: no such key at all. Pinned by exact text beside 4b, so no single
# return value satisfies both.
D4B="$(review_feature rf-noduration-unrecorded "$PRICED_COST" null null)"
report_for rf-noduration-unrecorded
r4f="$(V field_equals "$D4B/report.json" time.missing_duration_plans '[{"plan": "01-review-opus", "queue": "review", "reason": "no duration reported, cause not recorded"}]')"
check "4f. a sidecar with no result_event field at all says its cause is unrecorded (got $r4f)" '[[ "$r4f" == "True" ]]'

# ── 5: a feature whose plans carry durations is unmarked ──────────────────────
r5a="$(V field_equals "$D3/report.json" time.missing_duration_plans '[]')"
check "5a. a priced, timed feature has an empty missing_duration_plans (got $r5a)" '[[ "$r5a" == "True" ]]'
check "5b. ...and its Time table carries no mark" '! grep -qF "$MARK review: no duration" "$M3"'
check "5c. ...its review minutes being the sidecar's own eight (got: $(grep -F "| review | " "$M3" | tail -1))" 'grep -qF "| review | 8.0 |" "$M3"'

# ── 6: a recovered duration is a figure, and a lower bound ────────────────────
# The plan is priced and its `duration_ms` is null, exactly like rf-noduration above —
# the one difference is that recovery reached its transcript and wrote the span. The row
# must therefore stop reading `0.0 †` and start reading `7.5 ‡`.
D6="$(feature_dir rf-recovered)"
mkdir -p "$D6/review/complete"
plan_md "$D6/review/complete/01-review-opus.md"
echo "review pass complete" > "$D6/review/complete/01-review-opus.progress.md"
recovered_usage_json "$D6/review/complete/01-review-opus.usage.json" "$PRICED_COST" "$RECOVERED_S"
report_for rf-recovered
rc6=$?
R6="$D6/report.json"
M6="$D6/report.md"
check "6a. a recovered-duration feature reports cleanly (report.py exit $rc6)" '(( rc6 == 0 ))'
r6b="$(V field_equals "$R6" time.recovered_duration_plans '[{"plan": "01-review-opus", "queue": "review", "reason": "no result event", "recovered_s": 450.0}]')"
check "6b. time.recovered_duration_plans carries {plan, queue, reason} plus recovered_s (got $r6b)" '[[ "$r6b" == "True" ]]'
r6c="$(V field_equals "$R6" time.missing_duration_plans '[]')"
check "6c. ...and the plan is NOT also listed as missing (got $r6c)" '[[ "$r6c" == "True" ]]'
r6d="$(V field_equals "$R6" time.review_s '450.0')"
check "6d. the recovered span is the review bucket's minutes (got $r6d)" '[[ "$r6d" == "True" ]]'
check "6e. the Time table's review row carries the span and the recovered mark" 'grep -qF "| review | $RECOVERED_MIN $RECOVERED_MARK |" "$M6"'
check "6f. ...and not the missing-figure mark, which means something else" '! grep -qF "| review | $RECOVERED_MIN $MARK" "$M6"'
check "6g. ...with a footnote naming the plan, the seconds and the transcript span" 'grep -qF "$RECOVERED_MARK review: recovered 450.0s for 01-review-opus" "$M6" && grep -q "transcript span" "$M6"'
r6h="$(V field_equals "$R6" time.total_is_partial 'true')"
check "6h. the total stays partial — a transcript span is not the executor's wall clock (got $r6h)" '[[ "$r6h" == "True" ]]'
check "6i. ...so the lower-bound line stays" 'grep -qF "**This total is a lower bound**" "$M6"'
check "6j. the Cost table is untouched: priced, unmarked" 'grep -qF "| review | \$2.5000 | 100.0% |" "$M6"'

# ── 7: a transcript that is gone renders as it did before ─────────────────────
# rf-noduration from phase 4: same null duration_ms, no recovered span. Nothing about it
# may change, which is the half of the assertion the feature is judged by that says an
# attempt whose transcript is gone still renders as it does today.
r7a="$(V field_equals "$R4" time.recovered_duration_plans '[]')"
check "7a. a plan with no recovered span has an empty recovered_duration_plans (got $r7a)" '[[ "$r7a" == "True" ]]'
check "7b. ...its row still carries the missing-figure mark and a bare 0.0" 'grep -qF "| review | 0.0 $MARK |" "$M4"'
check "7c. ...and no recovered mark appears anywhere in its report" '! grep -qF "$RECOVERED_MARK" "$M4"'

echo
if (( fails > 0 )); then echo "report-footnotes: $fails assertion(s) FAILED"; exit 1; fi
echo "report-footnotes: all assertions passed"
