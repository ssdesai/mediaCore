# killed-attempt-cost-recovery — review

## What the batch was supposed to do

Two things. **(1)** Make a killed attempt's cost recoverable: the runner takes cost from a run's
final `result` event, a killed run never emits one, so `attempts[].total_cost_usd` stays null —
but `attempts[].session_id` is recorded anyway and the session transcript holds every token,
including the 5m/1h cache-creation split that `usage.json`'s own `usage{}` block flattens away.
**(2)** Fix `pricing.py`'s one-sided intro window, which applied sonnet's introductory rate to
every date *before* its expiry and so under-priced three weeks of runs by ~33%.

It does both. `pricing.py` now requires `starts <= as_of <= expires`; `analysis/transcript.py`
holds the shared billable-message iterator; `analysis/recover_attempts.py` prices a killed
attempt from its transcript into a parallel `recovered_cost_usd` (never over `total_cost_usd`);
`report.py` folds recovered dollars into the roll-up and stops calling a fully-recovered total
partial; the self-test is wired into `self/gate.sh`; and the "its spend is real but
unrecoverable" claim is gone from `analysis/README.md`. Gate green on arrival.

Four things I checked specifically and found sound, so the next reader does not re-check them:

- **Assertion 7 does constrain the production path.** Both of its fixtures go through a real
  `recover_attempts.py --self` run, and the read path itself (`transcript.py:59-61`) takes
  `usage.cache_creation.ephemeral_{5m,1h}_input_tokens` from the transcript. Nothing in
  `recover_attempts.py` reads `usage.json`'s flat `cache_creation_input_tokens`. A flat-total
  implementation would price the 5m and 1h fixtures identically and fail the ratio.
- **The `capture_planning.py` extraction is behaviour-identical.** Same guard order, same
  `message.id` dedup, the `isSidechain` flag still reaches the grouping key, and the
  count-it-anyway branch for a line with no id survives intact.
- **Recovery cannot double-count a resumed plan.** Each resume is a fresh `claude -p` with its
  own session id (`RUNNER.md:278`), so one transcript maps to exactly one attempt.
- **`report.py`'s new keys are read with defaults** (`cost.get("recovered", 0.0)`,
  `cost.get("unrecoverable_attempts") or []`), and `--all` never touches them, so the entirely
  pre-batch corpora render without a crash.

## Fixed in this pass

1. **`report.py` asserted a cause it cannot know.** The rendered report said each unpriced
   attempt's "session transcript has since aged out". Today that is false for the only real case
   in either corpus: `self/features/plan-analytics/verify/complete/57-verify-sonnet.usage.json`
   has two null-cost attempts, and both transcripts are still on disk — they are unpriced because
   recovery has not been run, not because anything expired. Reworded to **Unpriced attempts**,
   naming both possibilities and telling the reader to run `recover_attempts.py` and regenerate.
2. **`analysis/README.md`, same overclaim in two places** (the `report.py` entry and the
   `report.json` field list): "the transcript itself is gone" / "has aged out" → recovery has not
   run over the feature, or it ran and the transcript had already aged out.
3. **`analysis/README.md` did not record that the `starts` date is inferred.** `pricing.py`
   carries the provenance note, but the README is the page someone opens when re-checking rates,
   and `RATES_VERIFIED` was bumped alongside the inference so `is_rates_stale()` will stay quiet
   for 30 days. Added an "Unconfirmed" note under the rate-table step with the billing evidence
   (1.5x through 2026-08-21, 1.0x on 2026-08-22) and the instruction to confirm it against
   published rates. The date itself is pinned on both sides by observation, so a one-day error in
   either direction is contradicted by the corpus — the note is about provenance, not doubt.
4. **`self/tests/README.md` described the old world.** It said the fixtures cover files written
   "once written" and that `cost-recovery.sh` is "not yet `record`ed by `../gate.sh`" — plan 06
   wired it in (`self/gate.sh:161`). Rewritten to describe what is actually there, keeping the
   note that a missing `recover_attempts.py` fails assertions loudly rather than aborting.

## Escalated to the next batch

Both are the same defect class this feature exists to remove — a total that looks whole and is
low — reintroduced one layer up from where it was fixed.

### 1. An unpriced model is silently dropped from a recovered total

`analysis/recover_attempts.py:89-90` does `if cost is not None: total_cost += cost`.
`pricing.compute_cost` returns `(None, None)` for a model absent from `RATES`, and its docstring
(`pricing.py:117-118`) is explicit: *"A silent 0 reads as 'planning was cheap' when it means
'unmeasured'; callers must propagate None, not coerce it."* `capture_planning.py:376-381` is the
house precedent — it warns and sets `total_is_partial`. Recovery does neither.

Failure scenario: a killed attempt ran on a model not in `RATES` (a new id, or one whose suffix
`normalize_model_id` does not strip). `recover_attempt` still writes `recovered_tokens[model]`,
`rates_applied[model] = None`, and a `recovered_cost_usd` that omits those dollars. `report.py`
sees `recovered_cost_usd is not None`, files the attempt under *recovered*, and does **not** set
`total_is_partial`. The feature's total reads complete while missing a whole model's spend, and
`rates_applied: null` is the only trace, in a file nobody opens.

What it should be: `recover_attempt` records the models it could not price — `recovered_is_partial`
plus an `unpriced_models[]`, or refusing to write the attempt at all and printing it under the
existing `unrecoverable:` heading — and `report.py` treats such an attempt as partial rather than
whole. **Missing assertion** for `self/tests/cost-recovery.sh`: a transcript whose `model` is not
in `RATES` must not produce a whole-looking recovered figure. That assertion is cheap to write and
is what pins the contract permanently.

### 2. The runner erases the top-level `recovered_cost_usd` that `report.py` reads

`report.py:276` takes a plan's recovered dollars from the sidecar's **top-level**
`recovered_cost_usd`. `write_usage_sidecar` (`plan-runner-lib.sh:554-581`) rebuilds that top-level
object from a fixed key list on every write. `attempts[]` entries are carried through as whole
objects, so the attempt-level recovery fields survive — but the top-level key is not in the list
and is dropped.

Failure scenario: a plan has attempt A (killed, later recovered at $1.44) and attempt B (measured,
$2.90). Recovery writes A's fields and the $1.44 top-level sum. The plan is later resumed or
re-run, `write_usage_sidecar` fires again, and the top-level key is gone while A's fields remain.
`report.py` now computes `plan_recovered = 0.0`, so A's $1.44 disappears from `cost.build` and
`cost.recovered` reads `0.0` — and because A still carries `recovered_cost_usd`, it lands in the
*recovered* bucket, so the total is **not** marked partial. Re-running recovery does not repair
it: A is skipped as already-recovered (`recover_attempts.py:135`), `changed` stays `False`, and
nothing is rewritten. `--force` is the only repair, and nothing tells anyone to reach for it.

What it should be: `report.py` should derive a plan's recovered dollars by summing the
attempt-level `recovered_cost_usd` values — the durable location — using the top-level field only
as a cross-check, and warning when the two disagree. (Teaching `write_usage_sidecar` to preserve
unknown top-level keys would also work and is arguably more correct, but it is a runner change
with a wider blast radius than a reader change.) **Missing assertion**: a sidecar whose attempts
carry `recovered_cost_usd` while the top-level key is absent must still roll those dollars into
the total.

## On the two stated exclusions

Corpus-wide backfill and re-capturing the ~33%-low `planning.json` figures are both correctly out
of scope — each is an operational pass that commits data, not a code change, and plan 06 records
the second as owed work in `analysis/README.md` where the weekly cadence will meet it. No
objection to either. Worth noting only that the corpus now contains a script whose first real run
will change committed numbers, so it wants to be run deliberately rather than folded into an
unrelated batch.
