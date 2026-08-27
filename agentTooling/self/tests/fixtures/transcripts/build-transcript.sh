#!/usr/bin/env bash
# Shell helpers for synthesizing session-transcript `.jsonl` lines, for
# self/tests/cost-recovery.sh. Sourced, not executed — defines functions only.
#
# Matches the shape `analysis/transcript.py`'s `iter_billable_messages` reads
# (spec lives in analysis/README.md and, until it lands, in the
# killed-attempt-cost-recovery feature's plan 03): one `assistant` line per API
# response, `message.usage` carrying the 5m/1h cache-creation split under
# `cache_creation.ephemeral_{5m,1h}_input_tokens`.

# transcript_line MESSAGE_ID MODEL TIMESTAMP INPUT OUTPUT CACHE_READ CACHE_5M CACHE_1H [IS_SIDECHAIN]
# Prints one JSON transcript line to stdout. Two calls with the same
# MESSAGE_ID simulate the several content-block lines one real API response
# is written as — the dedup a consumer must key on.
transcript_line() {
  local message_id="$1" model="$2" timestamp="$3"
  local input="$4" output="$5" cache_read="$6" cache_5m="$7" cache_1h="$8"
  local sidechain="${9:-false}"
  printf '{"type":"assistant","timestamp":"%s","isSidechain":%s,"message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s}}}}\n' \
    "$timestamp" "$sidechain" "$message_id" "$model" "$input" "$output" "$cache_read" "$cache_5m" "$cache_1h"
}

# session_line SESSION_ID CWD BRANCH MESSAGE_ID MODEL TIMESTAMP INPUT OUTPUT CACHE_READ CACHE_5M CACHE_1H
# Prints one JSON transcript line carrying the session-identifying fields
# `analysis/capture_planning.py` selects on — `sessionId`, `cwd`, `gitBranch` —
# alongside the same `message.usage` block `transcript_line` emits.
#
# Separate from `transcript_line` because the two consumers read different halves:
# `recover_attempts.py` locates a transcript by filename and needs only usage, while
# `capture_planning.py` scans every transcript and decides membership from these three
# fields (cwd under the session root, gitBranch in the manifest's `branches`). A line
# without them is invisible to capture, which is why its fixtures need this helper.
session_line() {
  local session_id="$1" cwd="$2" branch="$3" message_id="$4" model="$5" timestamp="$6"
  local input="$7" output="$8" cache_read="$9" cache_5m="${10}" cache_1h="${11}"
  printf '{"type":"assistant","sessionId":"%s","cwd":"%s","gitBranch":"%s","timestamp":"%s","isSidechain":false,"message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s}}}}\n' \
    "$session_id" "$cwd" "$branch" "$timestamp" "$message_id" "$model" "$input" "$output" "$cache_read" "$cache_5m" "$cache_1h"
}

# synthetic_line TIMESTAMP [INPUT] [OUTPUT]
# A `model: "<synthetic>"` locally-generated notice. A real one always carries
# all-zero usage; INPUT/OUTPUT default to 0 but a caller may pass non-zero
# values to prove a consumer actually skips the line on `model`, rather than
# happening to add zero either way.
synthetic_line() {
  local timestamp="$1" input="${2:-0}" output="${3:-0}"
  printf '{"type":"assistant","timestamp":"%s","isSidechain":false,"message":{"id":"synthetic","model":"<synthetic>","usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0}}}}\n' \
    "$timestamp" "$input" "$output"
}

# subagent_line SESSION_ID AGENT_ID CWD BRANCH MESSAGE_ID MODEL TIMESTAMP INPUT OUTPUT CACHE_READ CACHE_5M CACHE_1H
# One billable line of a *subagent* transcript — the `<session_id>/subagents/agent-<id>.jsonl`
# file beside the parent's. Carries the parent's `sessionId`, `cwd` and `gitBranch` (a
# real subagent inherits all three at spawn; it never records a branch of its own),
# plus `agentId` and `isSidechain: true`, which is what `capture_planning.py` prices it
# under. Write it to `$PROJECTS/$SESSION_ID/subagents/agent-$AGENT_ID.jsonl`.
subagent_line() {
  local session_id="$1" agent_id="$2" cwd="$3" branch="$4" message_id="$5" model="$6" timestamp="$7"
  local input="$8" output="$9" cache_read="${10}" cache_5m="${11}" cache_1h="${12}"
  printf '{"type":"assistant","sessionId":"%s","agentId":"%s","cwd":"%s","gitBranch":"%s","timestamp":"%s","isSidechain":true,"message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s}}}}\n' \
    "$session_id" "$agent_id" "$cwd" "$branch" "$timestamp" "$message_id" "$model" "$input" "$output" "$cache_read" "$cache_5m" "$cache_1h"
}

# subagent_prompt_line SESSION_ID AGENT_ID CWD BRANCH TIMESTAMP TEXT
# The subagent's opening `user` line — the brief it was spawned with. Unbilled (no
# usage); it exists so `--list-subagents` has a prompt head to print.
subagent_prompt_line() {
  local session_id="$1" agent_id="$2" cwd="$3" branch="$4" timestamp="$5" text="$6"
  printf '{"type":"user","sessionId":"%s","agentId":"%s","cwd":"%s","gitBranch":"%s","timestamp":"%s","isSidechain":true,"message":{"role":"user","content":"%s"}}\n' \
    "$session_id" "$agent_id" "$cwd" "$branch" "$timestamp" "$text"
}
