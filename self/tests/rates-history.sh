#!/usr/bin/env bash
set -uo pipefail

# Self-test for the LiteLLM-sourced rate history (self/features/litellm-pricing/README.md,
# "Spec"). Run by self/gate.sh, or by hand: bash self/tests/rates-history.sh
#
# Copies `analysis/pricing.py`, `analysis/litellm_prices.py` and `analysis/refresh_rates.py`
# into throwaway checkouts under one mktemp -d, beside a copy of
# `fixtures/pricing/rates-history-2026-09-22.json` — the history the expectations below
# were written against — as their `rates_history.json`: every run of `refresh_rates.py`
# here writes a COPY of a history, never the committed one — and feeds the refresh
# `fixtures/pricing/litellm-sample.json` through `--source`, a small file in the shape of
# LiteLLM's `model_prices_and_context_window.json`. No model, no network.
#
# Asserts, in order:
#   H0. the committed `analysis/rates_history.json` still holds every entry of the seed
#       fixture, unchanged and in order: a refresh only ever appended to it.
#   H1. seed parity: for every model, dated alias and date in
#       `fixtures/pricing/rates-main-2026-09-22.json` — generated from main's
#       `pricing.py` BEFORE the table was replaced — the new `get_rates` returns the same
#       five rates (main's figures rounded to the refresh's `RATE_DECIMALS`, which is
#       float representation error and nothing else: main computed 0.8 × 0.1 as
#       0.08000000000000002) and `compute_cost` the same dollars to 1e-12; every unknown
#       model is `(None, None)`; every applied rate says `tier: "standard"`, `source:
#       "manual"` and the `from` of the entry in effect (Sonnet 5 changes on 2026-08-22).
#   H2. the history's shape: every model's entries sorted by `from`, the first at
#       `0000-01-01`, every rate present, `source` litellm or manual; `checked` is
#       `pricing.RATES_VERIFIED`; and `pricing.py` holds no table or multiplier of its own.
#   H3. a refresh from the fixture appends one dated `litellm` entry for a model whose
#       rates changed (Opus 5.5, the UNDATED key's figures, though a dated key disagrees),
#       for a model known only by dated keys (Sonnet 4.6, the latest date's figures), and
#       a first entry for a model the history lacks (Mythos preview, at `0000-01-01`);
#       leaves every other model byte-for-byte alone — Mythos 5.1, absent from the
#       source, included — skips an entry missing a rate and names it, ignores other
#       providers, and sets `checked` to today.
#   H4. float noise does not register: Sonnet 5's per-token figures × 10⁶ differ from the
#       history's (premise asserted) and it gains no entry, and `--check` does not name it.
#   H5. a second refresh is a no-op but for `checked`.
#   H6. a session dated before the refresh prices at the old rate, to the cent the parity
#       fixture recorded, and one dated today at the new rate with `source: "litellm"`.
#   H7. an unknown model is `(None, None)` after the refresh too.
#   H8. `--check` writes nothing and exits 1 with changes (naming them) and 0 without; a
#       fetch failure prints its reason and exits `FETCH_FAILED_EXIT`, which is neither of
#       those nor argparse's 2, and a write-mode refresh that cannot fetch writes nothing.
#   H9. `--history <path>` writes that file and leaves the default one alone.
#   T1-T8. `--tiers` (self/features/rates-tier-check): over a sandbox corpus whose records
#       name Sonnet 4.5 (a dated alias in `planning.json`, the bare id in a `usage.json`)
#       and Haiku 4.5, it reports Sonnet 4.5's above-200k rates from the fixture — the
#       standard ones, never the `_batches` variants — reports Haiku 4.5 as carrying no
#       tier, never names Opus 5.5 (tiered in the fixture, absent from the corpus), ends on
#       the summary line `feature-capture.sh`'s residue prints, exits 1, and writes
#       nothing; a corpus of flat models ends on "no model in the corpus carries a tiered
#       rate" and exits 0; a fetch failure exits `FETCH_FAILED_EXIT` naming the source;
#       and the suffixes it reads are the named constant `TIER_SUFFIXES`.
#   L1-L9. the live fallback (self/features/live-model-rates/README.md, "The spec"), every
#       case through the offline seam — `RATES_CHECK_SOURCE` names a local file, and
#       every phase above runs with `RATES_LIVE_LOOKUP=off`, the off switch, exported
#       below. A model the history lacks and the source carries (Mythos preview) prices at
#       the rates a refresh would append, `source: "litellm-live"`, `from: 0000-01-01`, a
#       dated alias included (L1); a model the source lacks or holds incomplete is
#       `(None, None)` (L2); a failed fetch is `(None, None)` and is not retried within
#       the process, even once the source appears (L3); the off switch is `(None, None)`
#       with a readable source (L4); importing `pricing` reads nothing — the source can
#       appear after the import (L5); a model the history knows never fetches — the source
#       vanishing afterwards leaves the next miss unpriced (L6); one fetch serves every
#       later miss — the source vanishing after the first leaves the second priced (L7);
#       the history file is never written (L8); and a capture over a live-priced session
#       records the price with its source and names it in `warnings[]`, and the report
#       over it names it too (L9).
#
# RED until the feature lands: the sandbox has no `rates_history.json` or
# `refresh_rates.py` and `pricing.py` still holds `RATES`. A missing file fails its own
# assertions rather than aborting the run (no `set -e`, every cp tolerates absence).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rates-history.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

FIXTURES="$HERE/self/tests/fixtures/pricing"
PARITY="$FIXTURES/rates-main-2026-09-22.json"
SAMPLE="$FIXTURES/litellm-sample.json"
TODAY="$(date -u '+%Y-%m-%d')"
BEFORE="2026-09-01"

# pricing.py's live lookup is OFF for every phase but L, which turns it on per call and
# points it at a local file. Without this an unknown model in H1 would reach the network.
export RATES_LIVE_LOOKUP=off
unset RATES_CHECK_SOURCE

# Every sandbox prices from SEED_HISTORY, the history as it stood on 2026-09-22 — the
# one every H/T/L expectation below was written against — never the committed
# analysis/rates_history.json, which a refresh legitimately appends to (Mythos preview,
# the H3d/L "model the history lacks", was appended by live-model-rates). H0 holds the
# committed history to the seed: every seed entry still there, unchanged, in order.
SEED_HISTORY="$FIXTURES/rates-history-2026-09-22.json"

# A fresh throwaway analysis/ holding the files under test (litellm_prices.py: both
# pricing.py and refresh_rates.py import it).
sandbox() {
  mkdir -p "$TMP/$1/analysis"
  local f
  for f in pricing.py litellm_prices.py refresh_rates.py roots.py; do
    cp "$HERE/analysis/$f" "$TMP/$1/analysis/$f" 2>/dev/null || true
  done
  cp "$SEED_HISTORY" "$TMP/$1/analysis/rates_history.json" 2>/dev/null || true
  echo "$TMP/$1/analysis"
}

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

cat > "$TMP/h.py" <<'PYEOF'
import json
import math
import os
import shutil
import sys

FIELDS = ["input", "output", "cache_read", "cache_creation_5m", "cache_creation_1h"]
PER_TOKEN = {
    "input": "input_cost_per_token",
    "output": "output_cost_per_token",
    "cache_read": "cache_read_input_token_cost",
    "cache_creation_5m": "cache_creation_input_token_cost",
    "cache_creation_1h": "cache_creation_input_token_cost_above_1hr",
}
ZERO_DATE = "0000-01-01"


def load(path):
    with open(path) as f:
        return json.load(f)


def pricing_from(analysis_dir):
    sys.path.insert(0, analysis_dir)
    import pricing
    return pricing


def cmd_parity(args):
    analysis_dir, fixture_path = args
    pricing = pricing_from(analysis_dir)
    import refresh_rates
    fx = load(fixture_path)
    for model, per_date in fx["models"].items():
        for d, want in per_date.items():
            got = pricing.get_rates(model, d)
            if got is None:
                print(f"{model}@{d}: get_rates None")
                return
            for f in FIELDS:
                if got[f] != round(want[f], refresh_rates.RATE_DECIMALS):
                    print(f"{model}@{d}: {f} {got[f]!r} != main {want[f]!r}")
                    return
            if got["model"] != want["model"]:
                print(f"{model}@{d}: model {got['model']} != {want['model']}")
                return
            if got.get("tier") != "standard" or got.get("source") != "manual":
                print(f"{model}@{d}: tier/source {got.get('tier')}/{got.get('source')}")
                return
            cost, applied = pricing.compute_cost(model, fx["tokens"], d)
            if cost is None or not math.isclose(cost, want["cost_usd"], rel_tol=1e-12):
                print(f"{model}@{d}: cost {cost!r} != main {want['cost_usd']!r}")
                return
            if applied != got:
                print(f"{model}@{d}: compute_cost rates_applied differs from get_rates")
                return
    for model in fx["unknown"]:
        for d in fx["dates"]:
            if pricing.compute_cost(model, fx["tokens"], d) != (None, None):
                print(f"{model}@{d}: unknown model priced")
                return
            if pricing.get_rates(model, d) is not None:
                print(f"{model}@{d}: unknown model has rates")
                return
    print(True)


def cmd_from(args):
    analysis_dir, model, d = args
    rates = pricing_from(analysis_dir).get_rates(model, d)
    print(rates.get("from") if rates else "NONE")


def cmd_rate(args):
    analysis_dir, model, d, field = args
    rates = pricing_from(analysis_dir).get_rates(model, d)
    print(rates.get(field) if rates else "NONE")


def cmd_shape(args):
    analysis_dir, history_path = args
    pricing = pricing_from(analysis_dir)
    h = load(history_path)
    if h.get("checked") != pricing.RATES_VERIFIED:
        print(f"checked {h.get('checked')} != RATES_VERIFIED {pricing.RATES_VERIFIED}")
        return
    if not str(h.get("source_url", "")).startswith("https://"):
        print("no source_url")
        return
    for model, entries in h["models"].items():
        froms = [e["from"] for e in entries]
        if not entries or froms[0] != ZERO_DATE or froms != sorted(froms):
            print(f"{model}: from dates {froms}")
            return
        for e in entries:
            if any(not isinstance(e.get(f), (int, float)) for f in FIELDS):
                print(f"{model}: entry missing a rate {e}")
                return
            if e.get("source") not in ("litellm", "manual"):
                print(f"{model}: source {e.get('source')}")
                return
    print(True)


def cmd_no_table(args):
    pricing = pricing_from(args[0])
    held = [n for n in dir(pricing) if n == "RATES" or "MULTIPLIER" in n]
    print(True if not held else held)


def cmd_entries(args):
    history_path, model = args
    print(json.dumps(load(history_path)["models"].get(model)))


def cmd_others_equal(args):
    a_path, b_path = args[0], args[1]
    skip = set(args[2:])
    a, b = load(a_path)["models"], load(b_path)["models"]
    same = all(b.get(m) == entries for m, entries in a.items() if m not in skip)
    extra = set(b) - set(a) - skip
    print(same and not extra)


def cmd_appended_only(args):
    seed_path, live_path = args
    seed, live = load(seed_path)["models"], load(live_path)["models"]
    for model, entries in seed.items():
        if live.get(model, [])[:len(entries)] != entries:
            print(f"{model}: a seed entry was changed, removed or reordered")
            return
    print(True)


def cmd_field(args):
    path, key = args
    print(load(path).get(key))


def cmd_set_checked(args):
    path, value = args
    h = load(path)
    h["checked"] = value
    with open(path, "w") as f:
        json.dump(h, f, indent=2)
        f.write("\n")


def cmd_noise_premise(args):
    sample_path, history_path, model = args
    entry = load(sample_path)[model]
    latest = load(history_path)["models"][model][-1]
    raw_differs = any(entry[PER_TOKEN[f]] * 1_000_000 != latest[f] for f in FIELDS)
    print(raw_differs)


def cmd_const(args):
    analysis_dir, name = args
    sys.path.insert(0, analysis_dir)
    import refresh_rates
    print(getattr(refresh_rates, name))


def cmd_cost_matches_parity(args):
    analysis_dir, fixture_path, model, d = args
    pricing = pricing_from(analysis_dir)
    fx = load(fixture_path)
    cost, _ = pricing.compute_cost(model, fx["tokens"], d)
    want = fx["models"][model][d]["cost_usd"]
    print(cost is not None and math.isclose(cost, want, rel_tol=1e-12))


# ── L: the live fallback. The bash side sets RATES_CHECK_SOURCE / RATES_LIVE_LOOKUP. ──
# One million of every token kind, so a cost is the sum of the five rates.
LIVE_TOKENS = {f: 1_000_000 for f in FIELDS}
# A model no history and no real price list holds, added to a copy of the sample for L7.
EXTRA_MODEL = "claude-live-only-9"
EXTRA_ENTRY = {
    "litellm_provider": "anthropic",
    "input_cost_per_token": 1e-06,
    "output_cost_per_token": 2e-06,
    "cache_read_input_token_cost": 1e-07,
    "cache_creation_input_token_cost": 1.25e-06,
    "cache_creation_input_token_cost_above_1hr": 2e-06,
}
LIVE_MODEL = "claude-mythos-preview"
KNOWN_MODEL = "claude-opus-5-5"


def source_of(pricing, model, d):
    rates = pricing.get_rates(model, d)
    return rates["source"] if rates else "NONE"


def cmd_live_price(args):
    analysis_dir, model, d = args
    cost, rates = pricing_from(analysis_dir).compute_cost(model, LIVE_TOKENS, d)
    print(json.dumps([cost, rates], sort_keys=True))


def cmd_import_then_source(args):
    analysis_dir, source_path, sample_path = args
    pricing = pricing_from(analysis_dir)
    shutil.copy(sample_path, source_path)
    print(source_of(pricing, LIVE_MODEL, "2026-10-01"))


def cmd_known_then_vanish(args):
    analysis_dir, source_path = args
    pricing = pricing_from(analysis_dir)
    first = source_of(pricing, KNOWN_MODEL, "2026-10-01")
    os.remove(source_path)
    print(first, source_of(pricing, LIVE_MODEL, "2026-10-01"))


def cmd_one_fetch(args):
    analysis_dir, source_path, sample_path = args
    data = load(sample_path)
    data[EXTRA_MODEL] = EXTRA_ENTRY
    with open(source_path, "w") as f:
        json.dump(data, f)
    pricing = pricing_from(analysis_dir)
    first = source_of(pricing, LIVE_MODEL, "2026-10-01")
    os.remove(source_path)
    print(first, source_of(pricing, EXTRA_MODEL, "2026-10-01"))


def cmd_failure_cached(args):
    analysis_dir, source_path, sample_path = args
    pricing = pricing_from(analysis_dir)
    first = pricing.compute_cost(LIVE_MODEL, LIVE_TOKENS, "2026-10-01")
    shutil.copy(sample_path, source_path)
    second = pricing.compute_cost(LIVE_MODEL, LIVE_TOKENS, "2026-10-01")
    print(first == (None, None), second == (None, None))


def cmd_planning_live(args):
    planning_path, model = args
    d = load(planning_path)
    rows = [r for r in d.get("priced", []) if r.get("model") == model]
    print(json.dumps({
        "sources": [(r.get("rates_applied") or {}).get("source") for r in rows],
        "priced": all(r.get("cost_usd") is not None for r in rows) and bool(rows),
        "partial": d.get("cost_usd", {}).get("total_is_partial"),
        "warned": any("litellm-live" in w and model in w for w in d.get("warnings", [])),
    }, sort_keys=True))


def cmd_attempt_live_source(args):
    usage_path, model = args
    attempts = load(usage_path).get("attempts") or []
    print(",".join(
        str(((a.get("rates_applied") or {}).get(model) or {}).get("source")) for a in attempts
    ))


COMMANDS = {
    "attempt_live_source": cmd_attempt_live_source,
    "live_price": cmd_live_price,
    "import_then_source": cmd_import_then_source,
    "known_then_vanish": cmd_known_then_vanish,
    "one_fetch": cmd_one_fetch,
    "failure_cached": cmd_failure_cached,
    "planning_live": cmd_planning_live,
    "parity": cmd_parity,
    "from": cmd_from,
    "rate": cmd_rate,
    "shape": cmd_shape,
    "no_table": cmd_no_table,
    "entries": cmd_entries,
    "others_equal": cmd_others_equal,
    "appended_only": cmd_appended_only,
    "field": cmd_field,
    "set_checked": cmd_set_checked,
    "noise_premise": cmd_noise_premise,
    "const": cmd_const,
    "cost_matches_parity": cmd_cost_matches_parity,
}

if __name__ == "__main__":
    COMMANDS[sys.argv[1]](sys.argv[2:])
PYEOF

H() { python3 -B "$TMP/h.py" "$@" 2>&1 | tail -1; }
refresh() { python3 -B "$1/refresh_rates.py" "${@:2}" 2>&1; }

echo "rates history"

# ── H0. the committed history only ever grew from the seed ───────────────────
h0="$(H appended_only "$SEED_HISTORY" "$HERE/analysis/rates_history.json")"
check "H0. analysis/rates_history.json holds every seed entry unchanged, in order — refreshes only appended (got $h0)" \
  '[[ "$h0" == "True" ]]'

# ── H1-H2. the seed ──────────────────────────────────────────────────────────
A1="$(sandbox seed)"
h1="$(H parity "$A1" "$PARITY")"
check "H1a. every model, alias and date prices exactly as main's table did (got $h1)" '[[ "$h1" == "True" ]]'
h1b="$(H from "$A1" claude-sonnet-5 2026-08-21)"; h1c="$(H from "$A1" claude-sonnet-5 2026-08-22)"
check "H1b. Sonnet 5's old window is two dated entries: 0000-01-01 then 2026-08-22 (got $h1b, $h1c)" \
  '[[ "$h1b" == "0000-01-01" && "$h1c" == "2026-08-22" ]]'
h2="$(H shape "$A1" "$A1/rates_history.json")"
check "H2a. the history's shape holds and checked is RATES_VERIFIED (got $h2)" '[[ "$h2" == "True" ]]'
h2b="$(H no_table "$A1")"
check "H2b. pricing.py holds no RATES table and no multiplier (got $h2b)" '[[ "$h2b" == "True" ]]'

# ── H3-H4. a refresh from the fixture ────────────────────────────────────────
A3="$(sandbox refresh)"
cp "$A3/rates_history.json" "$TMP/pristine.json" 2>/dev/null
h4p="$(H noise_premise "$SAMPLE" "$TMP/pristine.json" claude-sonnet-5)"
check "H4a. premise: Sonnet 5's per-token figures x 10^6 are not the history's exact floats (got $h4p)" '[[ "$h4p" == "True" ]]'
out3="$(refresh "$A3" --source "$SAMPLE")"; rc3=$?
check "H3a. a refresh from the fixture exits 0 (got $rc3)" '[[ $rc3 -eq 0 ]]'
opus="$(H entries "$A3/rates_history.json" claude-opus-5-5)"
check "H3b. Opus 5.5 keeps its manual entry and gains a litellm one from today at the UNDATED key's rates (got $opus)" \
  '[[ "$opus" == "[{\"from\": \"0000-01-01\", \"input\": 4, \"output\": 20, \"cache_read\": 0.2, \"cache_creation_5m\": 5, \"cache_creation_1h\": 8, \"source\": \"manual\"}, {\"from\": \"$TODAY\", \"input\": 5, \"output\": 25, \"cache_read\": 0.5, \"cache_creation_5m\": 6.25, \"cache_creation_1h\": 10, \"source\": \"litellm\"}]" ]]'
s46="$(H entries "$A3/rates_history.json" claude-sonnet-4-6)"
check "H3c. a model LiteLLM lists only under dated keys takes the latest date's rates (got $s46)" \
  'grep -q "{\"from\": \"$TODAY\", \"input\": 3.5, \"output\": 17.5, \"cache_read\": 0.35, \"cache_creation_5m\": 4.375, \"cache_creation_1h\": 7, \"source\": \"litellm\"}" <<<"$s46"'
myp="$(H entries "$A3/rates_history.json" claude-mythos-preview)"
check "H3d. a model the history lacks gets one litellm entry from 0000-01-01 (got $myp)" \
  '[[ "$myp" == "[{\"from\": \"0000-01-01\", \"input\": 10, \"output\": 50, \"cache_read\": 1, \"cache_creation_5m\": 12.5, \"cache_creation_1h\": 20, \"source\": \"litellm\"}]" ]]'
h3e="$(H others_equal "$TMP/pristine.json" "$A3/rates_history.json" claude-opus-5-5 claude-sonnet-4-6 claude-mythos-preview)"
check "H3e. every other model — Mythos 5.1, absent from the source, among them — is untouched (got $h3e)" '[[ "$h3e" == "True" ]]'
check "H3f. an entry missing a rate is skipped, named, and never added" \
  'grep -q "claude-3-haiku" <<<"$out3" && [[ "$(H entries "$A3/rates_history.json" claude-3-haiku)" == "null" ]]'
check "H3g. other providers' claude keys are ignored (openrouter's claude-opus-4 changed nothing)" \
  '[[ "$(H entries "$A3/rates_history.json" claude-opus-4)" == "$(H entries "$TMP/pristine.json" claude-opus-4)" ]]'
check "H3h. checked is today" '[[ "$(H field "$A3/rates_history.json" checked)" == "$TODAY" ]]'
check "H4b. float noise registers no change: Sonnet 5 still has its two entries" \
  '[[ "$(H entries "$A3/rates_history.json" claude-sonnet-5)" == "$(H entries "$TMP/pristine.json" claude-sonnet-5)" ]]'

# ── H5. a second refresh ─────────────────────────────────────────────────────
cp "$A3/rates_history.json" "$TMP/after-first.json" 2>/dev/null
H set_checked "$A3/rates_history.json" 2026-01-01 >/dev/null
out5="$(refresh "$A3" --source "$SAMPLE")"; rc5=$?
check "H5a. a second refresh exits 0 (got $rc5)" '[[ $rc5 -eq 0 ]]'
check "H5b. ... and is byte-identical to the first but for checked, which is today again" \
  'cmp -s "$TMP/after-first.json" "$A3/rates_history.json"'

# ── H6-H7. pricing across the refresh ────────────────────────────────────────
check "H6a. a session dated before the refresh prices at the old rate" \
  '[[ "$(H rate "$A3" claude-opus-5-5 "$BEFORE" input)" == "4" && "$(H rate "$A3" claude-opus-5-5 "$BEFORE" source)" == "manual" ]]'
check "H6b. ... to the dollars main's table gave it" \
  '[[ "$(H cost_matches_parity "$A3" "$PARITY" claude-opus-5-5 2026-09-01)" == "True" ]]'
check "H6c. a session dated today prices at the new rate, from litellm, from today" \
  '[[ "$(H rate "$A3" claude-opus-5-5 "$TODAY" input)" == "5" && "$(H rate "$A3" claude-opus-5-5 "$TODAY" source)" == "litellm" && "$(H from "$A3" claude-opus-5-5 "$TODAY")" == "$TODAY" ]]'
check "H7. an unknown model still has no rates after the refresh" \
  '[[ "$(H rate "$A3" claude-not-a-real-model-9 "$TODAY" input)" == "NONE" ]]'

# ── H8. --check ──────────────────────────────────────────────────────────────
A8="$(sandbox check)"
FETCH_FAILED="$(H const "$A8" FETCH_FAILED_EXIT)"
check "H8a. FETCH_FAILED_EXIT is distinct from 0, 1 and argparse's 2 (got $FETCH_FAILED)" \
  '[[ "$FETCH_FAILED" =~ ^[0-9]+$ && "$FETCH_FAILED" -ne 0 && "$FETCH_FAILED" -ne 1 && "$FETCH_FAILED" -ne 2 ]]'
cp "$A8/rates_history.json" "$TMP/check-before.json" 2>/dev/null
out8="$(refresh "$A8" --check --source "$SAMPLE")"; rc8=$?
check "H8b. --check with changes exits 1 (got $rc8)" '[[ $rc8 -eq 1 ]]'
check "H8c. ... names each model that would change and not the noisy one" \
  'grep -q claude-opus-5-5 <<<"$out8" && grep -q claude-mythos-preview <<<"$out8" && grep -q claude-sonnet-4-6 <<<"$out8" && ! grep -qE "claude-sonnet-5([^-0-9]|$)" <<<"$out8"'
check "H8d. ... and writes nothing" 'cmp -s "$TMP/check-before.json" "$A8/rates_history.json"'
cp "$A3/rates_history.json" "$TMP/refreshed.json" 2>/dev/null
out8e="$(refresh "$A3" --check --source "$SAMPLE")"; rc8e=$?
check "H8e. --check against a refreshed history exits 0 and writes nothing, checked included (got $rc8e)" \
  '[[ $rc8e -eq 0 ]] && cmp -s "$TMP/refreshed.json" "$A3/rates_history.json"'
out8f="$(refresh "$A8" --check --source "$TMP/no-such-file.json")"; rc8f=$?
check "H8f. a fetch failure exits FETCH_FAILED_EXIT and says why (got $rc8f: $out8f)" \
  '[[ -n "$FETCH_FAILED" && "$rc8f" == "$FETCH_FAILED" ]] && grep -q "no-such-file" <<<"$out8f"'
out8g="$(refresh "$A8" --source "$TMP/no-such-file.json")"; rc8g=$?
check "H8g. a write-mode refresh that cannot fetch exits the same and writes nothing (got $rc8g)" \
  '[[ -n "$FETCH_FAILED" && "$rc8g" == "$FETCH_FAILED" ]] && cmp -s "$TMP/check-before.json" "$A8/rates_history.json"'

# ── H9. --history ────────────────────────────────────────────────────────────
A9="$(sandbox history)"
cp "$A9/rates_history.json" "$TMP/other.json" 2>/dev/null
cp "$A9/rates_history.json" "$TMP/default-before.json" 2>/dev/null
refresh "$A9" --history "$TMP/other.json" --source "$SAMPLE" >/dev/null; rc9=$?
check "H9. --history writes the named file and leaves the default alone (got $rc9)" \
  '[[ $rc9 -eq 0 ]] && [[ "$(H field "$TMP/other.json" checked)" == "$TODAY" ]] && cmp -s "$TMP/default-before.json" "$A9/rates_history.json"'

# ── T. --tiers ───────────────────────────────────────────────────────────────
# A sandbox's corpus is `<sandbox>/self/features` (roots.features_root(True), derived from
# where the copied refresh_rates.py sits); `$TMP/plans/features`, the ordinary corpus, is
# never created, so each sandbox's records are the whole corpus it sees.
TIERED_SUMMARY="1 model(s) carry an above-200k tier: claude-sonnet-4-5 — tiered pricing is unbuilt, see self/BACKLOG.md"
FLAT_SUMMARY="no model in the corpus carries a tiered rate"
SONNET45_LINE="claude-sonnet-4-5: above 200k: input 6, output 22.5, cache_read 0.6, cache_creation_5m 7.5, cache_creation_1h 12"

A10="$(sandbox tiers)"
F10="$TMP/tiers/self/features/alpha"
mkdir -p "$F10/review/complete"
cat > "$F10/planning.json" <<'JSON'
{"slug": "alpha", "priced": [
  {"session_id": "s1", "agent_id": null, "model": "claude-sonnet-4-5-20250929", "cost_usd": 1.0},
  {"session_id": "s1", "agent_id": null, "model": "claude-haiku-4-5", "cost_usd": 0.1}
]}
JSON
cat > "$F10/review/complete/01-review-opus.usage.json" <<'JSON'
{"plan": "01-review-opus", "model": "opus", "model_usage": {"claude-sonnet-4-5": {"costUSD": 1.0}},
 "attempts": [{"session_id": "s2", "total_cost_usd": 1.0}]}
JSON
cp "$A10/rates_history.json" "$TMP/tiers-before.json" 2>/dev/null
out10="$(refresh "$A10" --tiers --source "$SAMPLE")"; rc10=$?
check "T1. --tiers over a corpus using a tiered model exits 1 (got $rc10)" '[[ $rc10 -eq 1 ]]'
check "T2. ... reports the model's above-200k rates, the standard ones and not the _batches ones" \
  'grep -qxF "$SONNET45_LINE" <<<"$out10"'
check "T3. ... reports a flat model as carrying no tier, and the summary leaves it out" \
  'grep -qxF "claude-haiku-4-5: no tier" <<<"$out10" && ! grep -q "haiku" <<<"$(tail -1 <<<"$out10")"'
check "T4. ... ends on the residue's summary line, verbatim (got: $(tail -1 <<<"$out10"))" \
  '[[ "$(tail -1 <<<"$out10")" == "$TIERED_SUMMARY" ]]'
check "T5. ... never names a tiered model the corpus does not use (Opus 5.5)" \
  '! grep -q "claude-opus-5-5" <<<"$out10"'
check "T6. ... and writes nothing" 'cmp -s "$TMP/tiers-before.json" "$A10/rates_history.json"'

A11="$(sandbox flat)"
F11="$TMP/flat/self/features/beta"
mkdir -p "$F11"
cat > "$F11/planning.json" <<'JSON'
{"slug": "beta", "priced": [{"session_id": "s3", "agent_id": null, "model": "claude-haiku-4-5-20251001", "cost_usd": 0.1}]}
JSON
out11="$(refresh "$A11" --tiers --source "$SAMPLE")"; rc11=$?
check "T7. a corpus of flat models exits 0 and ends on \"$FLAT_SUMMARY\" (got $rc11: $(tail -1 <<<"$out11"))" \
  '[[ $rc11 -eq 0 && "$(tail -1 <<<"$out11")" == "$FLAT_SUMMARY" ]]'
out12="$(refresh "$A11" --tiers --source "$TMP/no-such-file.json")"; rc12=$?
check "T8a. --tiers that cannot fetch exits FETCH_FAILED_EXIT and names the source (got $rc12: $out12)" \
  '[[ -n "$FETCH_FAILED" && "$rc12" == "$FETCH_FAILED" ]] && grep -q "no-such-file" <<<"$(tail -1 <<<"$out12")"'
t8b="$(H const "$A11" TIER_SUFFIXES)"
check "T8b. the tier suffixes read are a named constant holding LiteLLM's above-200k suffix (got $t8b)" \
  'grep -q "_above_200k_tokens" <<<"$t8b"'

# ── L. the live fallback ─────────────────────────────────────────────────────
# LIVE <source> <command> ...: the helper with the lookup ON and pointed at <source>, a
# local path — the seam feature-capture.sh's residue already uses. Never the network.
LIVE() { local src="$1"; shift; env -u RATES_LIVE_LOOKUP RATES_CHECK_SOURCE="$src" python3 -B "$TMP/h.py" "$@" 2>&1 | tail -1; }
LIVE_RATES='"cache_creation_1h": 20, "cache_creation_5m": 12.5, "cache_read": 1, "from": "0000-01-01", "input": 10'
LIVE_PRICE="[93.5, {$LIVE_RATES, \"model\": \"claude-mythos-preview\", \"output\": 50, \"source\": \"litellm-live\", \"tier\": \"standard\"}]"
NO_PRICE="[null, null]"

AL="$(sandbox live)"
cp "$AL/rates_history.json" "$TMP/live-before.json" 2>/dev/null
l1="$(LIVE "$SAMPLE" live_price "$AL" claude-mythos-preview 2026-10-01)"
check "L1a. a model the history lacks prices from the source: the rates a refresh would append (H3d), litellm-live, from 0000-01-01 (got $l1)" \
  '[[ "$l1" == "$LIVE_PRICE" ]]'
l1b="$(LIVE "$SAMPLE" live_price "$AL" claude-mythos-preview-20260101 2026-10-01)"
check "L1b. ... under a dated alias too (got $l1b)" '[[ "$l1b" == "$LIVE_PRICE" ]]'
l2a="$(LIVE "$SAMPLE" live_price "$AL" claude-not-a-real-model-9 2026-10-01)"
l2b="$(LIVE "$SAMPLE" live_price "$AL" claude-3-haiku 2026-10-01)"
check "L2. a model the source lacks, or holds without every rate, is (None, None) (got $l2a, $l2b)" \
  '[[ "$l2a" == "$NO_PRICE" && "$l2b" == "$NO_PRICE" ]]'
l3="$(LIVE "$TMP/late-source.json" failure_cached "$AL" "$TMP/late-source.json" "$SAMPLE")"
rm -f "$TMP/late-source.json"
check "L3. a failed fetch is (None, None), and is not retried once the source appears (got $l3)" \
  '[[ "$l3" == "True True" ]]'
l4="$(RATES_LIVE_LOOKUP=off RATES_CHECK_SOURCE="$SAMPLE" python3 -B "$TMP/h.py" live_price "$AL" claude-mythos-preview 2026-10-01 2>&1 | tail -1)"
check "L4. RATES_LIVE_LOOKUP=off is (None, None) with a readable source (got $l4)" '[[ "$l4" == "$NO_PRICE" ]]'
l5="$(LIVE "$TMP/after-import.json" import_then_source "$AL" "$TMP/after-import.json" "$SAMPLE")"
rm -f "$TMP/after-import.json"
check "L5. importing pricing reads no source: one that appears after the import is used (got $l5)" \
  '[[ "$l5" == "litellm-live" ]]'
cp "$SAMPLE" "$TMP/vanishing.json"
l6="$(LIVE "$TMP/vanishing.json" known_then_vanish "$AL" "$TMP/vanishing.json")"
check "L6. a model the history knows fetches nothing: the source vanishing after it leaves the next miss unpriced (got $l6)" \
  '[[ "$l6" == "manual NONE" ]]'
l7="$(LIVE "$TMP/once.json" one_fetch "$AL" "$TMP/once.json" "$SAMPLE")"
check "L7. one fetch serves every later miss: the source vanishing after the first leaves the second priced (got $l7)" \
  '[[ "$l7" == "litellm-live litellm-live" ]]'
check "L8. no live price writes the history" 'cmp -s "$TMP/live-before.json" "$AL/rates_history.json"'

# L9: a capture over one session on a model only the source prices, then its report.
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"
TMPP="$(cd "$TMP" && pwd -P)"
R9="$TMPP/capture/agentTooling"
SLUG9="live-cap"
SID9="1111aaaa-0000-0000-0000-000000000009"
HOME9="$TMPP/home"
mkdir -p "$R9/analysis" "$R9/self/features/$SLUG9" "$R9/.git"
for f in pricing.py litellm_prices.py roots.py transcript.py capture_planning.py routing.py report.py manifest.py; do
  cp "$HERE/analysis/$f" "$R9/analysis/$f" 2>/dev/null || true
done
cp "$SEED_HISTORY" "$R9/analysis/rates_history.json" 2>/dev/null || true
printf '# %s\n\nTest fixture only.\n\n```json\n{"slug": "%s", "method": "direct", "plans": [], "branches": ["%s"], "base": "main", "session_window": {"from": "2026-06-01T00:00:00Z", "to": "2026-06-02T00:00:00Z"}, "exclude_sessions": [], "exclude_subagents": [], "sessions": [], "subagents": []}\n```\n' \
  "$SLUG9" "$SLUG9" "$SLUG9" > "$R9/self/features/$SLUG9/README.md"
P9="$HOME9/.claude/projects/$(echo "$R9" | tr '/.' '--')"
mkdir -p "$P9"
session_line "$SID9" "$R9" "$SLUG9" "m-live" claude-mythos-preview "2026-06-01T10:00:00.000Z" 100 5000 0 0 0 > "$P9/$SID9.jsonl"
cap9="$(HOME="$HOME9" env -u RATES_LIVE_LOOKUP RATES_CHECK_SOURCE="$SAMPLE" python3 -B "$R9/analysis/capture_planning.py" --self "$SLUG9" 2>&1)"; rc9c=$?
l9="$(H planning_live "$R9/self/features/$SLUG9/planning.json" claude-mythos-preview)"
check "L9a. a capture over a live-priced session exits 0 (got $rc9c)" '[[ $rc9c -eq 0 ]]'
check "L9b. ... prices it, records source litellm-live, is not partial, and warns naming the model (got $l9)" \
  '[[ "$l9" == "{\"partial\": false, \"priced\": true, \"sources\": [\"litellm-live\"], \"warned\": true}" ]]'
rep9="$(HOME="$HOME9" python3 -B "$R9/analysis/report.py" --self "$SLUG9" 2>&1)"
check "L9c. the report's printed warnings name the live price" 'grep -q "WARN:.*litellm-live.*claude-mythos-preview" <<<"$rep9"'
check "L9d. ... and so does report.md" 'grep -q "litellm-live.*claude-mythos-preview" "$R9/self/features/$SLUG9/report.md"'

# L10: the other two visibility paths. A feature whose planning.json holds NO live row (its
# one captured session is on a model the seed history knows) but whose review sidecar is an
# unpriced attempt on a model only the source prices. recover_attempts.py prices it live and
# names it on its `live:` line; report.py then warns from the recovered attempt alone.
source "$HERE/self/tests/fixtures/usage/build-usage.sh"
SLUG10="live-rec"
SID10="1111aaaa-0000-0000-0000-000000000010"
SIDREV10="1111aaaa-0000-0000-0000-000000000011"
FD10="$R9/self/features/$SLUG10"
mkdir -p "$FD10/review/complete"
cp "$R9/self/features/$SLUG9/README.md" "$FD10/README.md"
sed -i.bak -e "s/$SLUG9/$SLUG10/g" -e 's/"plans": \[\]/"plans": ["01-review-opus"]/' "$FD10/README.md"; rm -f "$FD10/README.md.bak"
echo "a review plan" > "$FD10/review/complete/01-review-opus.md"
cp "$HERE/analysis/recover_attempts.py" "$R9/analysis/recover_attempts.py" 2>/dev/null || true
session_line "$SID10" "$R9" "$SLUG10" "m-known" claude-opus-5-5 "2026-06-01T10:00:00.000Z" 100 5000 0 0 0 > "$P9/$SID10.jsonl"
HOME="$HOME9" env -u RATES_LIVE_LOOKUP RATES_CHECK_SOURCE="$SAMPLE" python3 -B "$R9/analysis/capture_planning.py" --self "$SLUG10" >/dev/null 2>&1
U10="$FD10/review/complete/01-review-opus.usage.json"
write_unpriced_usage_json "$U10" "$SIDREV10" opus
transcript_line "m-rev" claude-mythos-preview "2026-06-01T11:00:00.000Z" 1000 500 2000 0 0 > "$P9/$SIDREV10.jsonl"
rec10="$(HOME="$HOME9" env -u RATES_LIVE_LOOKUP RATES_CHECK_SOURCE="$SAMPLE" python3 -B "$R9/analysis/recover_attempts.py" --self --for "$SLUG10" 2>&1)"; rc10=$?
src10="$(H attempt_live_source "$U10" claude-mythos-preview)"
live10="$(H planning_live "$FD10/planning.json" claude-mythos-preview)"
check "L10a. planning.json of the feature has no live row for the model (got $live10)" \
  '[[ "$live10" != *litellm-live* ]]'
check "L10b. a recovered attempt on a model only the source prices records rates_applied.source litellm-live (rc $rc10, got ${src10:-<absent>})" \
  '[[ $rc10 -eq 0 && "$src10" == "litellm-live" ]]'
check "L10c. ... and recover_attempts.py prints a live: line naming the model (got: $(grep '^live:' <<<"$rec10"))" \
  'grep -q "^live: .*litellm-live.*claude-mythos-preview" <<<"$rec10"'
rep10="$(HOME="$HOME9" python3 -B "$R9/analysis/report.py" --self "$SLUG10" 2>&1)"
check "L10d. report.py warns naming the model from the recovered attempt alone" \
  'grep -q "WARN:.*litellm-live.*claude-mythos-preview" <<<"$rep10"'
check "L10e. ... and the warning tells the reader to refresh, then --recapture" \
  'grep -q "WARN:.*refresh_rates.py in an agentTooling self feature, then capture_planning.py --recapture this feature" <<<"$rep10"'

echo
if (( fails > 0 )); then echo "rates-history: $fails assertion(s) FAILED"; exit 1; fi
echo "rates-history: all assertions passed"
