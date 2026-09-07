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
#      `missing_duration_plans[]`.
#
# RED until items 5 and 6 land: phase 1 finds a bare `| review | $0.0000 | 0.0% |` and
# an **Unpriced plans** paragraph, phase 4 finds a bare `| review | 0.0 |` and a list of
# stems where the dicts should be. A missing analysis script is tolerated rather than
# fatal, the cost-recovery.sh convention.

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

echo
if (( fails > 0 )); then echo "report-footnotes: $fails assertion(s) FAILED"; exit 1; fi
echo "report-footnotes: all assertions passed"
