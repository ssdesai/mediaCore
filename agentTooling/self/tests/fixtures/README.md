# self/tests/fixtures

Shell helpers the tests under `self/tests/` source to build their throwaway corpora —
`cost-recovery.sh`, `capture-guard.sh`, `timestamps-are-utc.sh`, `subagent-capture.sh`,
`recover-at-close.sh`, `recover-duration.sh`, `claims-ledger.sh`, `session-share.sh`,
`session-claims.sh` and `feature-lifecycle.sh`. These are function libraries, not data: the actual
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
  opening `user` line, the brief `--list-subagents` shows. `user_line TIMESTAMP` prints a
  timestamped `user` line with no usage block at all: it moves a transcript's first and
  last instant without being billable, which is how `recover-duration.sh` gives a session a
  span longer than its priced responses and how `session-share.sh` phase 14 gives one a
  last line past its window's `to` with nothing billable out there. It carries no
  `sessionId`/`cwd`/`gitBranch`, so a fixture using it needs a `session_line` in the same
  file for capture to read those from.
- `usage/build-usage.sh` — `write_usage_json PATH ATTEMPT...` writes a minimal `usage.json`
  sidecar with one `attempts[]` entry per `"session_id:outcome:total_cost_usd"` argument
  (`total_cost_usd` may be the literal `null`), in the shape `analysis/README.md` documents.
  `write_unpriced_usage_json PATH SESSION_ID [MODEL]` writes the other unpriced shape —
  the sidecar a run that exited 0 with no `result` event in its stream leaves: `outcome:
  "complete"` (the exit code's fact) beside `result_event: "missing"` (the pricing fact),
  every CLI-reported figure null or zero, and one `complete`-outcome attempt with a null
  `total_cost_usd`. MODEL defaults to `opus`, the model a review plan runs on.
