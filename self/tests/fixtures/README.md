# self/tests/fixtures

Shell helpers the tests under `self/tests/` source to build their throwaway corpora —
`cost-recovery.sh`, `capture-guard.sh`, `timestamps-are-utc.sh`, `subagent-capture.sh`,
`recover-at-close.sh`, `recover-duration.sh`, `claims-ledger.sh`, `session-share.sh`,
`session-claims.sh` and `feature-lifecycle.sh`. These are function libraries, not data: the actual
transcripts and sidecars are synthesized into a `mktemp -d` at test run time, never
committed here as JSON blobs.

**Three files here are data**, and they are the exceptions that say why the rule holds
elsewhere: a *command* is not a corpus, and neither is a price list or the output of code
that no longer exists. `hook-replay-2026-09-18.json` is a table of command lines and
the verdict each must get, which nothing can synthesize — the commands are the fixture.

- `hook-replay-2026-09-18.json` — `{ provenance, cwd, verdicts, records[] }`, where each
  record is `{ command, verdict, reason_contains }` and `verdict` is one of `ALLOW` (the
  hook approves), `REWRITE` (it denies with the rewrite as the reason), `DENY` (one of the
  three older shape denies) or `ASK` (it prints nothing). Replayed by
  `../allow-repo-commands.sh`, which maps the four onto the three decisions a caller can
  see and checks `reason_contains` against every denial's reason. Every path in it is
  relative to the throwaway project root that test builds, so no record carries a machine
  path. Its `provenance` says what it is: the shapes
  `../../DESIGN-2026-09-18-hook-rewrite-or-ask.md` §1 names, one record per shape and per
  approved read — **composed, not transcribed**, since the 2026-09-18 replay behind the
  design's counts was recorded as counts and the commands themselves survive nowhere.
- `pricing/rates-main-2026-09-22.json` — `{ provenance, dates[], tokens{input, output,
  cache_read, cache_creation_5m, cache_creation_1h}, unknown[], models{<model id or dated
  alias>: {<date>: {model, input, output, cache_read, cache_creation_5m,
  cache_creation_1h, cost_usd}}} }`: what main's `analysis/pricing.py` — the hand table
  `RATES`, `RATES_VERIFIED` 2026-09-22 — returned from `get_rates` and `compute_cost`
  (for `tokens`) for every model it held plus three dated aliases, on each of `dates`.
  Generated **once, before** litellm-pricing replaced the table, so it cannot be
  regenerated: the code that produced it is gone. `../rates-history.sh` H1 holds the
  seeded `analysis/rates_history.json` to it; `unknown[]` are ids that must stay unpriced.
- `pricing/litellm-sample.json` — a small file in the shape of LiteLLM's
  `model_prices_and_context_window.json` (`<key>: {litellm_provider, mode,
  input_cost_per_token, output_cost_per_token, cache_read_input_token_cost,
  cache_creation_input_token_cost, cache_creation_input_token_cost_above_1hr, …}`, plus
  the upstream `sample_spec`), built to trip each rule `analysis/refresh_rates.py` states:
  a changed model with a disagreeing dated key (Opus 5.5), a model under dated keys only
  (Sonnet 4.6), a new model (Mythos preview), float noise (Sonnet 5 — per-token figures a
  ulp off, so × 10⁶ is not exact), an entry missing its 1h rate (`claude-3-haiku-20240307`),
  and other providers' keys (openrouter, vertex, openai). Mythos 5.1 is deliberately
  absent. Read by `../rates-history.sh` through `--source`, and by
  `../feature-lifecycle.sh` and `../recover-at-close.sh` through `RATES_CHECK_SOURCE`,
  so no capture under test reaches the network.

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
