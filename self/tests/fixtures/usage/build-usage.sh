#!/usr/bin/env bash
# Shell helper for synthesizing `usage.json` sidecar fixtures, for
# self/tests/cost-recovery.sh. Sourced, not executed — defines a function only.
#
# Matches the shape `analysis/README.md` documents for usage.json: a
# `attempts[]` array of `{session_id, outcome, total_cost_usd, num_turns,
# duration_ms}`, one entry per `claude -p` invocation.

# write_usage_json PATH ATTEMPT...
# Each ATTEMPT is "session_id:outcome:total_cost_usd" — total_cost_usd may be
# the literal word "null" (unquoted) for a killed attempt with no recoverable
# CLI-reported cost, or a bare number for a measured one. Writes a minimal
# usage.json with one attempt per ATTEMPT.
write_usage_json() {
  local path="$1"; shift
  local attempts_json="" sep=""
  local spec sid rest outcome cost
  for spec in "$@"; do
    sid="${spec%%:*}"
    rest="${spec#*:}"
    outcome="${rest%%:*}"
    cost="${rest#*:}"
    attempts_json="${attempts_json}${sep}{\"session_id\":\"${sid}\",\"outcome\":\"${outcome}\",\"total_cost_usd\":${cost},\"num_turns\":1,\"duration_ms\":1000}"
    sep=","
  done
  cat > "$path" <<JSON
{
  "plan": "$(basename "$path" .usage.json)",
  "model": "sonnet",
  "outcome": "killed",
  "session_id": null,
  "subtype": null,
  "is_error": null,
  "num_turns": null,
  "duration_ms": null,
  "total_cost_usd": null,
  "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0},
  "model_usage": {},
  "permission_denials": 0,
  "tool_counts": {},
  "files_edited": [],
  "edit_count": 0,
  "attempts": [${attempts_json}]
}
JSON
}

# write_unpriced_usage_json PATH SESSION_ID [MODEL]
# The sidecar `write_usage_sidecar` leaves behind when a run exits 0 but its captured
# stream held no `result` event: `outcome: "complete"` (the exit code is what outcome
# means), `result_event: "missing"` (pricing is a separate fact), and every CLI-reported
# figure null, zero or empty — the shape three closed reviews were recorded at $0 in, and
# what `recover_attempts.py` must price from the session transcript. MODEL defaults to
# opus, the model a review plan runs on. See analysis/README.md → usage.json.
write_unpriced_usage_json() {
  local path="$1" session_id="$2" model="${3:-opus}"
  cat > "$path" <<JSON
{
  "plan": "$(basename "$path" .usage.json)",
  "model": "$model",
  "outcome": "complete",
  "session_id": "$session_id",
  "result_event": "missing",
  "subtype": null,
  "is_error": null,
  "num_turns": null,
  "duration_ms": null,
  "total_cost_usd": null,
  "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0},
  "model_usage": {},
  "permission_denials": 0,
  "tool_counts": {},
  "files_edited": [],
  "edit_count": 0,
  "attempts": [
    {"session_id": "$session_id", "outcome": "complete", "total_cost_usd": null, "num_turns": null, "duration_ms": null}
  ]
}
JSON
}
