# Notes: litellm-pricing

Rulings the spec left open, made by the direct implementer, one line of rationale each.

## Rulings

1. **Float noise: every converted rate is rounded to `RATE_DECIMALS = 6` decimal places
   of USD per million tokens, then compared exactly.** $0.000001/Mtok is 10⁻¹² per token,
   four orders below the smallest per-token figure LiteLLM carries for any Claude model,
   so no real price change can hide under it; `round` makes 1.9999999999999998 read as 2.
   One rule for both the refresh and the seed, so a refresh of an unchanged price is
   exactly equal rather than merely close.
2. **The seed stores clean decimals, not main's float artefacts.** Main computed
   `0.8 × 0.1` as `0.08000000000000002`; the history says `0.08`. Parity is asserted as
   "new rate == main's rate rounded to `RATE_DECIMALS`" and "new cost == main's cost to a
   relative 1e-12", which is representation error and not a figure anyone can see. A
   history holding `0.30000000000000004` would be data nobody could read or maintain.
3. **Integral rates are written as JSON integers** (`4`, not `4.0`), so `rates_applied`
   in a recapture reads as it did under the old table and the file reads like a price list.
4. **Dated vs undated LiteLLM keys: the undated key wins; with no undated key, the latest
   dated key wins.** The undated alias is the entry LiteLLM keeps current; a dated
   snapshot can lag it. Among dated keys only, the newest snapshot is the model's current
   price. Deterministic whatever order the JSON lists them in.
5. **A model new to the history gets its first entry at `from: "0000-01-01"`, not today.**
   Spec item 1 says every model's first entry starts there, and item 4 says appended
   entries start today; for a model with no entry the two conflict. The invariant wins:
   sessions on that model before the refresh were unpriced (`None`, a lower bound), so
   pricing them at the only rate known fills a gap rather than changing a figure — the
   never-rewrite guarantee is about dollars already computed, and there were none.
6. **An upstream entry missing any of the five rates is skipped and named** in the
   output (`incomplete`), never half-imported: `compute_cost` needs all five, and
   inventing one would be a multiplier by the back door.
7. **Only `litellm_provider == "anthropic"` and keys starting `claude-`** — vertex,
   bedrock and openrouter keys (which may carry resellers' prices) are ignored.
8. **`--history <path>`** points a run at another history file; the default is
   `rates_history.json` beside `pricing.py` (`pricing.HISTORY_PATH`). The tests use
   sandbox copies of `analysis/` and `--history` once, to prove it writes only that file.
9. **`FETCH_FAILED_EXIT = 3`** — distinct from 0 (no changes), 1 (changes) and argparse's
   2. A source that cannot be read, or is not a JSON object, is a fetch failure too; a
   write-mode refresh that cannot fetch writes nothing, `checked` included.
10. **`--check` prints the history's `checked` date and staleness as its first line**,
    before fetching, so the capture's one call reports both and a network failure still
    leaves the date on screen.
11. **`feature-capture.sh` reads `RATES_CHECK_SOURCE`** from the environment and passes it
    as `--source` when set — the seam that keeps `self/tests/feature-lifecycle.sh` off the
    network, as every test here must be. Unset in real use, so the check fetches LiteLLM.
    The fetch has a timeout (`FETCH_TIMEOUT_S`), so a hung network cannot hang a capture.
12. **Same-day second change** (LiteLLM moving twice in one UTC day): appended like any
    other; `get_rates` takes the last entry whose `from` is on or before the date, so the
    later one wins that day. Never happens in practice; nothing is rewritten if it does.
13. **Every test sandbox that copies `pricing.py` copies `rates_history.json`**, the same
    rule `self/tests/README.md` already states for `routing.py`. `pricing.py` loads the
    history at import and a missing file is an import error — loud, never a silent $0.
14. **`cost-recovery.sh` 1–3 and 7 were adapted, not weakened**: they asserted the intro
    `tier` and the `CACHE_WRITE_*_MULTIPLIER` constants, both removed by spec items 1 and
    3. They now assert the `from` of the entry applied (same dates, same 2/3 cost ratio)
    and the 1h/5m ratio from `get_rates`. `feature-lifecycle.sh` C4 now makes the history
    stale by rewriting its `checked` instead of `pricing.py`'s assignment.

15. **Wording** (spec item 5 leaves it to the implementer): `rates_source` is
    `agentTooling/analysis/rates_history.json checked=<date>`; the capture warning is
    `rate history is stale (checked <date>); refresh …`; the report footer reads `Rates from
    analysis/rates_history.json, last checked <date> (fresh|stale …)`; the gate's
    informational check is renamed `pricing rate history is current` and still never
    fetches. `report.py` imports only `HISTORY_FILENAME` besides the two names it had —
    it still never calls `compute_cost`.
16. **`timestamps-are-utc.sh` 7b** asserted `rates_applied.tier == "intro"`; it now asserts
    `rates_applied.from == "2026-08-22"` — the same session, the same boundary, the field
    the spec gives it (see 14).
17. **The seed round-trips**: `refresh_rates.serialize` writes the committed seed byte for
    byte, so the first real refresh's diff is `checked` plus one line per appended entry.
    Checked once by hand against the real LiteLLM file (scratch copy, not committed): its
    only difference from the seed is a new `claude-mythos-preview`.

## Deviations from the spec

None.

## Open questions

None.
