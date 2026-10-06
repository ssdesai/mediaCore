# Notes: live-model-rates

Rulings the spec left open, each with its reason. Spec: `README.md` → "The spec".

## Rulings

- **The shared module is `analysis/litellm_prices.py`, and `normalize_model_id` moved into
  it** (re-exported by `pricing.py`, so no caller changed). The selection keys on the
  normalized model id, and `pricing.py` imports the new module, so the module cannot
  import `pricing` back; the model-id rule had to live on the import-free side to stay one
  copy. `FIRST_ENTRY_FROM` moved with it for the same reason: the live price's `from` and
  the refresh's first-entry `from` are one constant.
- **`pricing.py` imports `litellm_prices` at module import, not lazily on the first miss.**
  A sandbox that forgot to copy the module then fails at import, loudly, rather than only
  in the rare run that meets an unknown model. Import still fetches nothing. Every test
  sandbox copying `pricing.py` was updated (the contract the review holds).
- **"A miss" means the history has no entry for the model at all.** A model the history
  knows never fetches, even for an `as_of` before its first entry (impossible today: every
  first entry is `0000-01-01`).
- **The live price ignores `as_of`.** It stands in for the first entry a refresh writes,
  which starts at `0000-01-01`, so it applies to every date — spec 3's recapture
  equivalence depends on it.
- **The off switch is `RATES_LIVE_LOOKUP=off` (or `0`); the source is `RATES_CHECK_SOURCE`**,
  the seam `feature-capture.sh` already hands `refresh_rates.py --check`. Read at the first
  miss, not at import, so a test can set them per call.
- **Tests are offline by exporting the off switch in every sandbox that prices**, plus in
  `self/gate.sh`. A per-test export keeps a test run by hand offline; the gate export is the
  backstop. Off restores exactly the old behaviour, so no existing expectation changed.
- **A failed fetch prints one stderr line** (`pricing: live rate lookup failed, …`) and is
  then silent for the process; the unknown-model warnings every caller already prints say
  which figures it left unpriced.
- **Provenance is surfaced from the records, not from process state.** `capture_planning.py`
  derives its warning from its own `priced[]` rows' `rates_applied.source`, `report.py` from
  `planning.json`'s `priced[]` and the plans' recovered `attempts[].rates_applied`, and
  `recover_attempts.py` from the attempts it just priced. A process-wide "models priced
  live" set would leak between features under `capture_planning.py --all`. One sentence,
  `pricing.live_price_warning`, so the three cannot drift. Since the close summary prints
  `report.py`'s `WARN:` lines, the close names it too.
- **`rates-history.sh` sandboxes price from a frozen seed history
  (`self/tests/fixtures/pricing/rates-history-2026-09-22.json`), not the committed file.**
  The repair's refresh appended Mythos preview, which H1, H3d, H8c and L treat as the model
  the history lacks; every future refresh would break those tests the same way. The
  expectations are unchanged; H0 now holds the committed history to the seed (append-only).

## Deviations from the brief

- **hook-hash-chained-cd needed no repair.** Its three `review/complete/0{2,3,4}-review-sonnet.usage.json`
  carry CLI-reported `total_cost_usd` (`$0.1879`, `$0.1727`, `$0.2595`, with
  `model_usage.claude-sonnet-5-5.costUSD`) — the runner never prices through
  `pricing.py`. The `$0.0000 †` cells in its report are the Rounds table's **build** column
  for rounds 2–4 (the `†` footnote: no `checkpoint` stamp divides the build by round), not
  unpriced reviews. Its `planning.json` holds no `claude-sonnet-5-5` row and no warning.
  Nothing in it changes with the refresh, so it was left untouched (the review contract's
  "no unrelated record changed").
- **sandbox-consumer-reads had one unpriced row, not four.** Session `e2c3f2ec` (a
  four-second `claude-sonnet-5-5` session on the branch); the subagent `a94ed82d5c0c5ddcf`
  is opus and was already priced. Recapture: planning `$3.1031` (partial) → `$3.1948`;
  report `$3.9509` (partial) → `$4.0426`. The recapture also added five ids to
  `excluded_session_ids` (runner sessions run since its first capture — e.g. `0803b8c7`,
  hook-hash-chained-cd's 02 review — that the scan met and excluded) — metadata only, no
  figure moved. Its manifest is untouched.

## Open questions

- None blocking. Consuming repos' short records are a `self/BACKLOG.md` entry.
