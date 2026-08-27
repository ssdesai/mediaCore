# self/tests/fixtures

Shell helpers `self/tests/cost-recovery.sh`, `self/tests/capture-guard.sh`,
`self/tests/timestamps-are-utc.sh` and `self/tests/subagent-capture.sh` source to build their throwaway corpora. These are function libraries, not data: the actual
transcripts and sidecars are synthesized into a `mktemp -d` at test run time, never
committed here as JSON blobs.

- `transcripts/build-transcript.sh` — `transcript_line MESSAGE_ID MODEL TIMESTAMP INPUT
  OUTPUT CACHE_READ CACHE_5M CACHE_1H [IS_SIDECHAIN]` prints one `assistant`-line session
  transcript fixture to stdout, in the shape `analysis/transcript.py`'s
  `iter_billable_messages` reads (`message.usage.cache_creation.ephemeral_{5m,1h}_input_tokens`
  for the cache-write split). `synthetic_line TIMESTAMP [INPUT] [OUTPUT]` prints a
  `model: "<synthetic>"` notice line — INPUT/OUTPUT default to 0 (what a real one always
  carries) but can be set non-zero so a test can prove a consumer skips it on `model` rather
  than on happening to add zero regardless. `session_line SESSION_ID CWD BRANCH MESSAGE_ID
  MODEL TIMESTAMP INPUT OUTPUT CACHE_READ CACHE_5M CACHE_1H` prints a line carrying the
  session-identifying fields `analysis/capture_planning.py` selects on — `sessionId`, `cwd`,
  `gitBranch` — alongside the same usage block. Separate from `transcript_line` because the
  two consumers read different halves: `recover_attempts.py` finds a transcript by filename
  and needs only usage, while `capture_planning.py` decides membership from those three
  fields, and is blind to a line without them. `subagent_line SESSION_ID AGENT_ID CWD
  BRANCH MESSAGE_ID MODEL TIMESTAMP INPUT OUTPUT CACHE_READ CACHE_5M CACHE_1H` prints one
  billable line of a *subagent* transcript — the parent's `sessionId`/`cwd`/`gitBranch`
  (inherited at spawn, never the subagent's own) plus `agentId` and `isSidechain: true` —
  to be written under `<projects>/<SESSION_ID>/subagents/agent-<AGENT_ID>.jsonl`;
  `subagent_prompt_line SESSION_ID AGENT_ID CWD BRANCH TIMESTAMP TEXT` prints its unbilled
  opening `user` line, the brief `--list-subagents` shows.
- `usage/build-usage.sh` — `write_usage_json PATH ATTEMPT...` writes a minimal `usage.json`
  sidecar with one `attempts[]` entry per `"session_id:outcome:total_cost_usd"` argument
  (`total_cost_usd` may be the literal `null`), in the shape `analysis/README.md` documents.
