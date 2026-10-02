# 03 — recover a killed attempt's cost from its session transcript

Feature: a killed attempt's cost is recoverable from its session transcript, and
`pricing.py`'s intro tier must not apply to dates before the promotion began.

Plan 3 of 6 build plans, and the substance of the batch. Two new files in `analysis/`, plus
a refactor of `capture_planning.py` onto the first of them.

## Why this is possible at all

The runner takes cost from a run's final `result` event, and a killed run never emits one, so
`attempts[].total_cost_usd` stays null. But `write_usage_sidecar` records `session_id` for
every attempt including a killed one (`plan-runner-lib.sh`, the `$attempt` object — its
comment says "a killed run with no result event still yields the one thing the exclusion rule
needs"), and the session transcript survives under `~/.claude/projects/`. Every token is
there, with the 5m/1h cache-creation split that `usage.json` lacks.

## File 1 — `analysis/transcript.py`

The two transcript-format facts currently live only inside `capture_planning.py`'s main loop
(around `capture_planning.py:378-395`). Two consumers now need them, and duplicating a
subtle dedup rule is how it drifts. Extract, and give the module a `README.md` entry.

```python
SYNTHETIC_MODEL = "<synthetic>"


def iter_billable_messages(lines):
    """Yield (model, usage, is_sidechain) once per billable API response.

    One API response is written as several `assistant` lines, one per content
    block, each repeating that response's `usage` verbatim — summing per line
    measured 2.4x-2.8x over. Bill each response once, keyed on its API id. A
    line with no id cannot be de-duplicated; count it, since dropping it would
    under-bill. `model: "<synthetic>"` marks a locally-generated notice with
    all-zero usage and is skipped.
    """
    seen_message_ids = set()
    for line in lines:
        if line.get("type") != "assistant":
            continue
        message = line.get("message") or {}
        model = message.get("model")
        usage = message.get("usage")
        if not model or not usage or model == SYNTHETIC_MODEL:
            continue
        message_id = message.get("id")
        if message_id is not None:
            if message_id in seen_message_ids:
                continue
            seen_message_ids.add(message_id)
        yield model, usage, bool(line.get("isSidechain", False))
```

Also move `add_usage` (`capture_planning.py:63-77`) here unchanged — it is the other half of
the same job and its five-key token shape is what `pricing.compute_cost` consumes.

Then rewrite `capture_planning.py`'s loop to call `iter_billable_messages`, deleting the
inlined copy. **Its observable output must not change.** The comments at
`capture_planning.py:370-374` and `:386-388` explaining the two facts belong with the code
that now implements them; do not leave orphaned copies behind.

## File 2 — `analysis/recover_attempts.py`

Same shape as its neighbours: stdlib only, run directly, `--self` via
`roots.add_self_flag(parser)`, roots resolved through `roots.py` and never from `cwd`.

Walk every `usage.json` under `roots.features_root(self_mode)`. For each attempt with
`total_cost_usd` null and a `session_id`:

- **Locate the transcript by globbing `~/.claude/projects/*/<session_id>.jsonl`.** Not via
  `roots.session_root`. Session ids are unique, and a `--self` executor runs with cwd
  `agentTooling/` while a host-repo executor runs from the repo root, so the two land in
  different project directories — a glob is correct for both and needs no root resolution.
- Sum tokens with `iter_billable_messages` + `add_usage`, keyed by model.
- Price each model's tokens with `pricing.compute_cost(model, tokens, date)`, where `date`
  is **the session's own earliest timestamp**, not today. `get_rates`' docstring commits to
  this and plan 02 has just given it two-sided meaning.
- Write onto the attempt: `recovered_cost_usd`, `recovered_tokens` (the five-key shape, per
  model), `recovered_from: "transcript"`, `recovered_at` (ISO now), `rates_applied` (what
  `compute_cost` returned).
- Never write `total_cost_usd`. It means "the CLI's own figure" and must stay
  distinguishable from a derived one.
- Maintain a top-level `recovered_cost_usd` = sum over recovered attempts.

Missing transcript: leave the attempt untouched, count it, print it under an
`unrecoverable:` heading with the session id and the plan stem, exit 0. Transcripts are on a
retention clock (`analysis/README.md` → "Why the cadence matters"); an aged-out session is an
expected outcome, not a failure.

Idempotent, like `backfill_usage.py`: an attempt that already carries `recovered_cost_usd` is
skipped unless `--force`. Print a one-line summary — attempts recovered, dollars recovered,
attempts unrecoverable.

## The trap this plan exists to avoid

Do **not** derive tokens from `usage.json`'s own `usage{}` block. It reports
`cache_creation_input_tokens` as one flat total with no 5m/1h split, and these are 1-hour
writes billed at 2x base input rather than the 1.25x of a 5m write.
`analysis/README.md` → "Do not re-price build or verify cost" measures the resulting error at
roughly 1.5x too low and records the residual solved exactly against a single-model haiku run
as 2.0000. The transcript's `usage.cache_creation.ephemeral_{5m,1h}_input_tokens` is the only
correct source. Assertion 7 of `self/tests/cost-recovery.sh` fails any implementation that
takes the flat total.

## Done when

All 12 assertions of `self/tests/cost-recovery.sh` pass, and `python3 -m py_compile
analysis/*.py` is clean. Do not wire the self-test into `self/gate.sh` — plan 06 owns that.

Add `transcript.py` and `recover_attempts.py` entries to `analysis/README.md`'s Scripts list,
in the form of the existing entries. `recover_attempts.py`'s entry must name the two
dependencies that are not visible from its imports: the `~/.claude/projects/*/` glob, and the
`attempts[].session_id` field the runner writes for killed attempts.
