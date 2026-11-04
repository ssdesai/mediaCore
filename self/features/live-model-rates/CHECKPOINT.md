# Checkpoint: live-model-rates

status: committed
updated: 2026-10-02T04:26:44Z
gate: === gate: done — all checks passed ===

## Slices
- [x] acceptance tests — self/tests/rates-history.sh L1–L9 (7 red at commit, expected)
- [x] 1. analysis/litellm_prices.py: fetch, selection, conversion moved out of
      refresh_rates.py (plus normalize_model_id, FIRST_ENTRY_FROM); refresh_rates
      imports it, H/T expectations unchanged
- [x] 2. pricing.get_rates live fallback: on a miss only, once per process, cached
      success or failure, source "litellm-live", from 0000-01-01; RATES_CHECK_SOURCE seam,
      RATES_LIVE_LOOKUP=off switch
- [x] 3. visibility: pricing.live_price_warning in capture_planning / report warnings[],
      recover_attempts summary `live:` line; close summary via report's WARN lines
- [x] 4. every test sandbox copying pricing.py copies litellm_prices.py and exports
      RATES_LIVE_LOOKUP=off; gate exports it too
- [x] 5. repair: refresh_rates.py (real fetch: sonnet-5-5, mythos-preview appended);
      sandbox-consumer-reads recaptured and re-rendered; hook-hash-chained-cd checked,
      nothing to repair (NOTES.md); rates-history.sh moved onto a frozen seed history + H0
- [x] READMEs: analysis/README.md, self/tests/README.md, self/tests/fixtures/README.md,
      root README.md; NOTES.md; self/BACKLOG.md entry for consuming repos' records

## Learned
- hook-hash-chained-cd's sonnet review usage.json carry CLI-reported total_cost_usd;
  the `$0.0000 †` cells are the Rounds table's build column, not unpriced reviews.
- A refresh that appends a model the tests call "unknown" breaks any test that copies the
  committed history; hence the seed fixture.

## Resume
- Nothing to resume: committed on branch live-model-rates. Next is the review pass.
