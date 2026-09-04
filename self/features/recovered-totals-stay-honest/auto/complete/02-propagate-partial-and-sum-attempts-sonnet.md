# 02 — propagate the unpriceable, sum the durable

Feature: two ways a recovered total still looks whole and is low.

Plan 2 of 2 build plans. Make plan 01's two assertions pass.

## Defect 1 — `recover_attempts.py`

The loop at `analysis/recover_attempts.py:84-90`:

```python
    total_cost = 0.0
    for model, tokens in totals.items():
        cost, rates = compute_cost(model, tokens, as_of)
        recovered_tokens[model] = tokens
        rates_applied[model] = rates
        if cost is not None:
            total_cost += cost
```

`if cost is not None` is where the spend disappears. Record the miss instead of swallowing
it: collect the models `compute_cost` could not price, and put them on the returned attempt
as `unpriced_models` with `recovered_is_partial: true` when the list is non-empty.

`pricing.py:117-118` states the rule this violates — *"a silent 0 reads as 'planning was
cheap' when it means 'unmeasured'; callers must propagate None, not coerce it"* — and
`capture_planning.py:376-381` is the house precedent for what propagating looks like here:
warn, and mark the result partial. Match it.

Print the unpriced models in the script's summary line too. A partial figure that is only
discoverable by opening a JSON file is a partial figure nobody will discover.

## Defect 2 — `report.py`

`report.py:276` reads `usage_data.get("recovered_cost_usd") or 0.0`. That key is rebuilt away
by `write_usage_sidecar` (`plan-runner-lib.sh:554-581`) on any later write, while the
attempt-level fields survive, so the top level is the wrong place to read from.

Sum `attempts[]`'s `recovered_cost_usd` values instead — the durable location — and keep the
top-level field as a **cross-check**: when both are present and disagree by more than a cent,
warn naming both figures. Do not silently prefer one; a disagreement means something rewrote
the sidecar and the reader should say so.

Then teach the three-bucket rule about partial recovery: an attempt with
`recovered_is_partial` is neither *recovered* (whole) nor *unrecoverable*. It counts its
dollars **and** sets `total_is_partial`. Add `cost.partially_recovered_attempts[]` alongside
the existing `cost.unrecoverable_attempts[]` so the distinction is visible in the artifact,
and render it in `report.md`.

Read every new key with a default, as `report.py` already does for `cost.review` and
`cost.recovered`. Both corpora predate this batch.

## Do not

- Do not change `write_usage_sidecar`. Design resolution 1: the fix is in the reader, because
  a runner change affects every consuming repo's sidecar writes. The top-level key stays.
- Do not widen `normalize_model_id` to make the test's fake model resolve. The defect is
  about a model that genuinely is not in the table.
- Do not re-run the backfill. The verify pass checks whether defect 1 ever fired on the real
  corpus; that is its job, not yours.

## Done when

All 14 assertions pass, `python3 -m py_compile analysis/*.py` is clean, and
`python3 analysis/report.py --all` plus `--self --all` still run against the committed
corpora. Update `analysis/README.md`'s `usage.json` and `report.json` field lists with
`recovered_is_partial`, `unpriced_models[]` and `cost.partially_recovered_attempts[]`, and
the `report.py` entry with where recovered dollars are now read from and why.
