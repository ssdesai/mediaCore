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
