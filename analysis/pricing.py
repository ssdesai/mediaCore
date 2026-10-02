"""Cost calculator for Claude model usage, priced from a dated rate history.

Rates live in `rates_history.json` beside this file, not here: for each normalized
model id, a list of entries sorted by `from`, each holding absolute USD-per-million
rates (`input`, `output`, `cache_read`, `cache_creation_5m`, `cache_creation_1h`) and
a `source` (`"manual"` or `"litellm"`). An entry applies from its `from` date until the
next entry's. `refresh_rates.py` appends to that file from LiteLLM's public price list
and never rewrites an entry, so a session priced once prices the same forever.

The live fallback (self/features/live-model-rates/README.md). A model the history has no
entry for at all — one released after the last refresh — is looked up in LiteLLM's list
itself, through `litellm_prices` (the same fetch, selection and conversion the refresh
uses), and priced with `source: "litellm-live"` and `from: FIRST_ENTRY_FROM`, the entry a
refresh will later append for it. The list is fetched only on such a miss, at most once
per process — success and failure are both cached — and never at import. The history is
never written from here. `RATES_CHECK_SOURCE` points the lookup at another URL or a local
file (the tests' seam, shared with `refresh_rates.py --check` in feature-capture.sh), and
`RATES_LIVE_LOOKUP=off` turns it off.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import date as _date
from datetime import datetime as _datetime
from datetime import timezone as _timezone
from pathlib import Path
from typing import Optional, TypedDict

import litellm_prices
# Re-exported: every caller imports the model-id rule from here.
from litellm_prices import normalize_model_id  # noqa: F401

# The rate history this module prices from, read once at import. A missing or
# malformed file is an import error — loud, never a silent $0.
HISTORY_FILENAME = "rates_history.json"
HISTORY_PATH = Path(__file__).resolve().with_name(HISTORY_FILENAME)

# The live fallback: the `source` a live price carries, the env var naming where to read
# LiteLLM's list from (unset: LITELLM_PRICES_URL), and the one that switches it off.
LIVE_SOURCE = "litellm-live"
LIVE_SOURCE_ENV = "RATES_CHECK_SOURCE"
LIVE_LOOKUP_ENV = "RATES_LIVE_LOOKUP"
LIVE_LOOKUP_OFF_VALUES = ("off", "0")

# Age, in days, past which the history's `checked` date must be treated as stale and
# callers should warn (never fail) that it needs a refresh.
STALENESS_THRESHOLD_DAYS = 30

# The five absolute rates every history entry carries, USD per million tokens.
RATE_FIELDS = ("input", "output", "cache_read", "cache_creation_5m", "cache_creation_1h")

# Every entry is list pricing; `tier` stays in RatesApplied for existing readers.
STANDARD_TIER = "standard"


def load_history(path: Path = HISTORY_PATH) -> dict:
    """The rate history at `path`: `{checked, source_url, models{<id>: [entry, ...]}}`."""
    with open(path) as f:
        return json.load(f)


_HISTORY = load_history()

# The date the history was last checked against its source — the history's `checked`.
# Kept under its old name because every caller imports it.
RATES_VERIFIED: str = _HISTORY["checked"]


# `from` is a Python keyword, so the TypedDict is spelled functionally.
RatesApplied = TypedDict(
    "RatesApplied",
    {
        "model": str,
        "input": float,
        "output": float,
        "cache_read": float,
        "cache_creation_5m": float,
        "cache_creation_1h": float,
        "tier": str,  # always "standard"
        "from": str,  # the applied entry's `from` date
        "source": str,  # "litellm", "manual", or LIVE_SOURCE ("litellm-live")
    },
)


# The live lookup's one fetch, per process: None until the first miss asks, then the
# upstream rates by normalized model — {} when the fetch failed, so it is never retried.
_live_upstream: Optional[dict] = None


def _live_lookup_enabled() -> bool:
    return os.environ.get(LIVE_LOOKUP_ENV, "").strip().lower() not in LIVE_LOOKUP_OFF_VALUES


def _live_rates(normalized: str) -> Optional[dict]:
    """LiteLLM's five rates for `normalized`, or None. Fetches on the first call only."""
    global _live_upstream
    if not _live_lookup_enabled():
        return None
    if _live_upstream is None:
        source = os.environ.get(LIVE_SOURCE_ENV) or litellm_prices.LITELLM_PRICES_URL
        try:
            _live_upstream, _ = litellm_prices.upstream_rates(litellm_prices.fetch(source))
        except litellm_prices.FetchError as exc:
            _live_upstream = {}
            # Once, on stderr: the unknown-model warnings every caller already prints say
            # which figures this left unpriced; this says why the fallback did not help.
            print(f"pricing: live rate lookup failed, unknown models stay unpriced: {exc}",
                  file=sys.stderr)
    return _live_upstream.get(normalized)


def get_rates(model_id: str, as_of: str) -> Optional[RatesApplied]:
    """Return the rates in effect for `model_id` on ISO date `as_of`, or None
    if neither the history nor the live lookup has a rate for it. `as_of` selects the
    entry — never the caller's wall-clock date — so a session keeps pricing at the
    rate in effect when it ran after a later entry is appended.

    A model with no history entry at all is priced from LiteLLM's list, live, with
    `source: LIVE_SOURCE` and `from: FIRST_ENTRY_FROM` (module docstring). A model the
    history knows never triggers a fetch.
    """
    normalized = normalize_model_id(model_id)
    entries = _HISTORY["models"].get(normalized)
    if not entries:
        live = _live_rates(normalized)
        if live is None:
            return None
        applied = dict(live, **{"from": litellm_prices.FIRST_ENTRY_FROM, "source": LIVE_SOURCE})
    else:
        applied = None
        for entry in entries:
            if entry["from"] <= as_of:
                applied = entry
        if applied is None:
            return None

    rates: RatesApplied = {"model": normalized}  # type: ignore[typeddict-item]
    for field in RATE_FIELDS:
        rates[field] = applied[field]  # type: ignore[literal-required]
    rates["tier"] = STANDARD_TIER
    rates["from"] = applied["from"]
    rates["source"] = applied["source"]
    return rates


def compute_cost(
    model_id: str,
    tokens: dict,
    as_of: str,
) -> tuple[Optional[float], Optional[RatesApplied]]:
    """Compute USD cost for one model's token usage on ISO date `as_of`.

    `tokens` keys (all optional, default 0): input, output, cache_read,
    cache_creation_5m, cache_creation_1h.

    Returns (cost_usd, rates_applied). Both are None when the model is
    unknown — never (0.0, None). A silent 0 reads as "planning was cheap"
    when it means "unmeasured"; callers must propagate None, not coerce it.
    """
    rates = get_rates(model_id, as_of)
    if rates is None:
        return None, None

    cost = (
        tokens.get("input", 0) * rates["input"]
        + tokens.get("output", 0) * rates["output"]
        + tokens.get("cache_read", 0) * rates["cache_read"]
        + tokens.get("cache_creation_5m", 0) * rates["cache_creation_5m"]
        + tokens.get("cache_creation_1h", 0) * rates["cache_creation_1h"]
    ) / 1_000_000

    return cost, rates


def is_live(rates: Optional[dict]) -> bool:
    """True when a `rates_applied` value came from the live lookup, not the history."""
    return isinstance(rates, dict) and rates.get("source") == LIVE_SOURCE


def live_price_warning(models) -> str:
    """The one sentence every caller that surfaces price provenance uses for figures
    priced live — capture_planning's and report.py's `warnings[]`, recover_attempts'
    summary — so a figure resting on an unrefreshed history is never silent."""
    return (
        f"priced from LiteLLM live ({LIVE_SOURCE}), not from analysis/{HISTORY_FILENAME}: "
        f"{', '.join(sorted(set(models)))} — refresh the history with "
        f"analysis/refresh_rates.py in an agentTooling self feature, "
        f"then capture_planning.py --recapture this feature"
    )


def utc_today() -> str:
    """Today's UTC date as "YYYY-MM-DD".

    Every other date in this package is a UTC calendar date derived from a transcript
    timestamp (`transcript.utc_date`), so the one date that comes from the wall clock
    has to be UTC too. `date.today()` is the machine's LOCAL date, which differs from
    the UTC one for part of every day — a full day ahead in Asia-Pacific zones — and
    mixing the two makes a comparison against a UTC-derived date wrong near the
    boundary.
    """
    return _datetime.now(_timezone.utc).date().isoformat()


def is_rates_stale(today: Optional[str] = None, checked: Optional[str] = None) -> bool:
    """True when the history's `checked` date (or `checked`, if given) is more than
    STALENESS_THRESHOLD_DAYS old. `today` defaults to the current UTC date; pass an
    ISO string to test.
    """
    as_of = _date.fromisoformat(today or utc_today())
    verified = _date.fromisoformat(checked or RATES_VERIFIED)
    return (as_of - verified).days > STALENESS_THRESHOLD_DAYS
