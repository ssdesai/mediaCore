Verdict: escalated

# Review: live-model-rates

## What the batch was supposed to do

When a model has no entry in `analysis/rates_history.json`, price it from LiteLLM's list at that moment (`source: "litellm-live"`, `from: 0000-01-01`). The fetch happens only on a miss, at most once per process, with a timeout. It is never made at import and never writes the history. The fetch, selection and conversion move into one module that `pricing.py` and `refresh_rates.py` both import. A failure stays `(None, None)` and keeps the existing warnings. A live price is named wherever price provenance is shown. The tests stay offline. The batch also refreshes the history and repairs the short sandbox-consumer-reads record.

## Does it do it

Yes. I checked each contract in the brief against the diff (`main...HEAD`):

- **Import is network-free; a model the history knows never fetches.** `pricing.get_rates` calls `_live_rates` only when `_HISTORY["models"].get(normalized)` is empty. `litellm_prices.py` does nothing at import. Tests L5 and L6 cover this.
- **At most one fetch per process, failures cached.** `_live_upstream` stays `None` until the first miss. After that it holds the rates, or `{}` on a `FetchError`. The fetch uses `FETCH_TIMEOUT_S`. Tests L3 and L7 cover this.
- **One parser.** `fetch`, `upstream_entries`, `upstream_rates`, `per_million`, `normalize_model_id` and the constants now exist only in `analysis/litellm_prices.py`. `refresh_rates.py` re-binds them under their old names. The H and T expectations are unchanged; their sandbox now uses a frozen seed history (`fixtures/pricing/rates-history-2026-09-22.json`), and H0 checks that the committed history only grew from it.
- **No circular import.** `litellm_prices` imports nothing from the package. Every test that copies `pricing.py` now also copies `litellm_prices.py`; `audit-fixes.sh` gets it through its `*.py` glob. `harness/lib.sh` only mentions `pricing.py` in a comment.
- **`RatesApplied` shape.** No field was added. `source` gains `"litellm-live"`, and `from` is `0000-01-01` for a live price. Both are documented in `analysis/README.md`.
- **Never `(0.0, None)`.** A model the source lacks or holds incomplete, a failed fetch, and the off switch all return `(None, None)` (L2, L3, L4).
- **History untouched by pricing.** Nothing outside `refresh_rates.py` writes `rates_history.json` (L8).
- **Visibility.** The warning appears in `capture_planning` `warnings[]`, in `report.py` `warnings[]` (from both `priced[]` and recovered `attempts[]`), and on `recover_attempts.py`'s `live:` summary line. `feature-capture.sh` streams the output of both scripts.
- **Tests offline.** `self/gate.sh` exports `RATES_LIVE_LOOKUP=off`, and so does every self-test that prices. The L phase points the lookup at local files only. The gate report is newer than every source file and reads "all checks passed", with nothing skipped.
- **Repair.** `rates_history.json` gains exactly two appended entries (`claude-mythos-preview`, `claude-sonnet-5-5`) plus `checked`, and no existing line changed. In sandbox-consumer-reads, the sonnet-5-5 row is now priced ($0.0917042, `source: "litellm"`), `total_is_partial` is false, and the total went from $3.1030826 to $3.1947868. The report follows. The only other change is four new ids in `excluded_session_ids`, which is just the recapture noting sessions created since; it changes no figures.
- **READMEs.** The root, `analysis/`, `self/tests/` and `self/tests/fixtures/` READMEs describe the new module, the fallback, the two env vars and the new `source` value.

## Fixed in this pass

Nothing. The brief asked for findings only.

## Escalated to the next round

Both are low severity. The code is correct, and both are cheap work for a build plan.

1. **Two of the three visibility paths have no test** (`analysis/recover_attempts.py:248-249,291-292`, `analysis/report.py:2809-2814`).
   - L9 only covers a live price in `planning.json`'s `priced[]`.
   - Nothing tests `recover_attempts.py`'s `live:` line, which is the close-residue surface the brief names. Nothing tests `report.py`'s `live_priced_models` reading a recovered `attempts[].rates_applied` with `source: "litellm-live"`. `grep litellm-live self/tests/*.sh` matches only `rates-history.sh`.
   - If either path broke (for example, `attempts` renamed, or the `is_live` check dropped), every check would stay green.
   - **Add:** a case in `self/tests/recover-at-close.sh` phase B, or in `rates-history.sh` L. Recover one attempt on a model only the fixture source carries, with `RATES_LIVE_LOOKUP` unset and `RATES_CHECK_SOURCE` pointed at `fixtures/pricing/litellm-sample.json`. Then assert:
     - the attempt's `rates_applied[<model>].source == "litellm-live"`;
     - stdout has a `live:` line naming the model;
     - `report.py` over that feature has a `WARN:` line naming the model, even when `planning.json` has no live row.

2. **The live-price warning gives the wrong instruction once the history has been refreshed** (`analysis/pricing.py:188-192`, `live_price_warning`).
   - `report.py` takes the warning from what the records say, so a record priced live keeps raising it until someone runs `--recapture` on it.
   - The sentence only says "refresh the history with analysis/refresh_rates.py in an agentTooling self feature". After that refresh has shipped through the subtree, a consuming repo's report still tells them to refresh. The actual fix, `--recapture` (described in `analysis/README.md`, the "refresh, then `--recapture`" paragraph), is never mentioned.
   - **Change:** the sentence should end with something like "— refresh the history with analysis/refresh_rates.py in an agentTooling self feature, then `capture_planning.py --recapture` this feature". Update the quote in `analysis/README.md` to match. The L9 and planning assertions match only on `litellm-live` and the model name, so they need no change.
