# 01 — two assertions that pin "partial means partial"

Feature: two ways a recovered total still looks whole and is low.

Plan 1 of 2 build plans. Tests only — write no production code. Both assertions are RED until
plan 02.

Add to `self/tests/cost-recovery.sh`, which already has 12 assertions and the scaffolding you
need: a `mktemp -d` corpus, a transcript-line helper, and sidecars written into it. Follow the
existing form exactly; read the script before adding to it.

## Assertion 13 — an unpriced model must not produce a whole-looking total

Build a transcript whose `message.model` is an id **not** in `pricing.RATES` — use something
obviously synthetic like `claude-not-a-real-model-9`, not a plausible future id that someone
might later add to the table and silently disarm this test.

Then a sidecar with one killed attempt pointing at it, and run `recover_attempts.py --self`.

Assert:
- the attempt is marked partial — `recovered_is_partial` is true — and names the model in
  `unpriced_models[]`;
- `report.py` classes the plan's total as partial (`total_is_partial` true in the generated
  `report.json`), **not** as recovered-and-whole.

The second half is the one that matters. Defect 1 is not that the dollars are missing — they
are genuinely unmeasurable — it is that the report says nothing is missing.

Also build the mixed case: a transcript with **two** models, one priceable and one not. The
priceable model's dollars must still be recovered, and the attempt must still be partial.
That pins design resolution 2: propagate, do not refuse.

## Assertion 14 — attempt-level recovery survives the top-level key being erased

`write_usage_sidecar` rebuilds the sidecar's top-level object from a fixed key list, so a
resumed plan loses `recovered_cost_usd` from the top level while `attempts[]` keeps its
recovery fields. Simulate that directly: write a sidecar whose attempts carry
`recovered_cost_usd` and whose **top level does not**, then run `report.py`.

Assert:
- the attempt-level dollars are in `cost.recovered` and in the queue bucket
  (`cost.build` / `cost.verify` / `cost.review`) — not zero;
- the total is not marked partial on account of it, because nothing is actually missing.

Then the cross-check half: a sidecar whose top-level `recovered_cost_usd` **disagrees** with
the sum of its attempts must produce a warning naming both figures. A silent reconciliation
is the same defect class again.

Do not simulate this by running the real runner. The contract under test is `report.py`'s
reading of a sidecar shape; construct the shape directly.

## Done when

`bash self/tests/cost-recovery.sh` reaches and reports both new assertions, failing on an
assertion rather than erroring on a missing key. Assertions 1-12 still pass. Update
`self/tests/README.md`'s entry for the script.
