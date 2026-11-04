#!/usr/bin/env bash
set -uo pipefail

# Self-test for report.py's missing-stream warnings on a record with carried rows
# (self/features/capture-record-wording-and-carried-rows/). Run by self/gate.sh, or by
# hand: bash self/tests/report-carried-streams.sh
#
# The defect. `planning.json` rows the capture could not reach are carried forward from the
# committed record, each marked `carried_from` (capture-merges-committed-record) — the
# normal case from round 2 of a cloud feature on, where each round runs in a container of
# its own. The plans of the earlier container wrote `*.stream.jsonl` files that are
# gitignored and went with it, so `report.py` warned "re-hunting / edit overlap computed
# without streams for: <those plans>" at every later render, naming streams that cannot
# come back, while the Cost table's one `carried` line already says the figure is a chain.
#
# Same scaffolding as report-rounds.sh — copies of the analysis modules into a throwaway
# checkout under mktemp -d, hand-written manifests, `planning.json` files, plan `.md`s and
# `usage.json` sidecars. No transcripts, no model, no network.
#
# Asserts, in order:
#   1. a record with a carried row and one plan whose stream is missing (another plan has
#      one, so the sections are computed rather than carried whole): no WARN names the
#      missing stream, and the carried line is still printed once;
#   2. the same fixture without `carried_from` on any row: both WARNs fire and name the
#      plan with no stream — the warning a live feature missing a stream still gets.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/report-carried-streams.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
for f in pricing.py litellm_prices.py rates_history.json roots.py transcript.py report.py routing.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "report-carried-streams"

WITH_STREAM="01-build-sonnet"
NO_STREAM="02-review-opus"
CARRIED_STAMP="2026-10-27T18:13:11.437611+00:00"

# make_feature <slug> <carried-stamp-json> — a feature of two plans, the first with a
# stream and the second without, whose one session row carries `carried_from` when the
# stamp is not `null`.
make_feature() {
  local slug="$1" stamp="$2" dir="$AT/self/features/$1"
  mkdir -p "$dir/auto/complete" "$dir/review/complete"
  cat > "$dir/README.md" <<MDEOF
# $slug

Test fixture only, for self/tests/report-carried-streams.sh.

\`\`\`json
{"slug": "$slug", "method": "plans", "plans": ["$WITH_STREAM", "$NO_STREAM"], "branches": ["$slug"]}
\`\`\`
MDEOF
  local carried=""
  if [ "$stamp" != "null" ]; then
    carried=", \"carried_from\": \"$stamp\""
  fi
  cat > "$dir/planning.json" <<JSONEOF
{"cost_usd": {"total": 0.0, "total_is_partial": false},
 "duration_s": {"sessions": 0.0, "subagents": 0.0},
 "sessions": [{"session_id": "sess-planning", "duration_s": 0.0$carried}],
 "subagents": []}
JSONEOF
  write_plan "$dir" auto "$WITH_STREAM"
  write_plan "$dir" review "$NO_STREAM"
  printf '{"type":"result","subtype":"success"}\n' > "$dir/auto/complete/$WITH_STREAM.stream.jsonl"
}

# write_plan <feature dir> <queue> <stem> — the plan `.md` and a priced `usage.json`.
write_plan() {
  local dir="$1" queue="$2" stem="$3"
  printf '# %s\n\nTest fixture plan.\n' "$stem" > "$dir/$queue/complete/$stem.md"
  cat > "$dir/$queue/complete/$stem.usage.json" <<JSONEOF
{
  "plan": "$stem",
  "model": "sonnet",
  "outcome": "complete",
  "session_id": "sess-$stem",
  "result_event": "seen",
  "num_turns": 4,
  "duration_ms": 60000,
  "total_cost_usd": 1.0,
  "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0},
  "model_usage": {},
  "permission_denials": 0,
  "tool_counts": {},
  "files_edited": ["fixture.txt"],
  "edit_count": 1,
  "attempts": [
    {"session_id": "sess-$stem", "outcome": "complete", "total_cost_usd": 1.0, "num_turns": 4, "duration_ms": 60000}
  ]
}
JSONEOF
}

report_out() { python3 "$AT/analysis/report.py" --self "$1" 2>&1; }

# ── 1. a carried row: the missing stream is not warned about ──────────────────
make_feature rcs-carried "$CARRIED_STAMP"
report_out rcs-carried > "$TMP/out1.txt"
check "1a. the render succeeds and prints the carried line once" \
  "[ \"\$(grep -c 'carried from the capture' '$TMP/out1.txt')\" = 1 ]"
check "1b. no WARN names the plan whose stream is missing" \
  "! grep -q 'WARN' '$TMP/out1.txt'"
check "1c. neither the re-hunting nor the edit-overlap WARN is printed" \
  "! grep -q 'computed without streams' '$TMP/out1.txt'"

# ── 2. no carried row: the same missing stream still warns ────────────────────
make_feature rcs-plain null
report_out rcs-plain > "$TMP/out2.txt"
check "2a. the re-hunting WARN names the plan with no stream" \
  "grep 'WARN' '$TMP/out2.txt' | grep 're-hunting' | grep -q '$NO_STREAM'"
check "2b. the edit-overlap WARN names it too" \
  "grep 'WARN' '$TMP/out2.txt' | grep 'edit overlap' | grep -q '$NO_STREAM'"
check "2c. and no carried line is printed" \
  "! grep -q 'carried from the capture' '$TMP/out2.txt'"

echo ""
if (( fails > 0 )); then
  echo "report-carried-streams: $fails assertion(s) failed"
  exit 1
fi
echo "report-carried-streams: all assertions passed"
