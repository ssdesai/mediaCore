#!/usr/bin/env bash
set -uo pipefail

# Self-test for the LiteLLM-sourced rate history (self/features/litellm-pricing/README.md,
# "Spec"). Run by self/gate.sh, or by hand: bash self/tests/rates-history.sh
#
# Copies `analysis/pricing.py`, `analysis/refresh_rates.py` and `analysis/rates_history.json`
# into throwaway checkouts under one mktemp -d — every run of `refresh_rates.py` here
# writes a COPY of the history, never the committed one — and feeds the refresh
# `fixtures/pricing/litellm-sample.json` through `--source`, a small file in the shape of
# LiteLLM's `model_prices_and_context_window.json`. No model, no network.
#
# Asserts, in order:
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

# A fresh throwaway analysis/ holding the three files under test.
sandbox() {
  mkdir -p "$TMP/$1/analysis"
  local f
  for f in pricing.py refresh_rates.py rates_history.json; do
    cp "$HERE/analysis/$f" "$TMP/$1/analysis/$f" 2>/dev/null || true
  done
  echo "$TMP/$1/analysis"
}

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

cat > "$TMP/h.py" <<'PYEOF'
import json
import math
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


COMMANDS = {
    "parity": cmd_parity,
    "from": cmd_from,
    "rate": cmd_rate,
    "shape": cmd_shape,
    "no_table": cmd_no_table,
    "entries": cmd_entries,
    "others_equal": cmd_others_equal,
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

echo
if (( fails > 0 )); then echo "rates-history: $fails assertion(s) FAILED"; exit 1; fi
echo "rates-history: all assertions passed"
