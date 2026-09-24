"""Cost calculator for Claude model usage, priced from a dated rate history.

Rates live in `rates_history.json` beside this file, not here: for each normalized
model id, a list of entries sorted by `from`, each holding absolute USD-per-million
rates (`input`, `output`, `cache_read`, `cache_creation_5m`, `cache_creation_1h`) and
a `source` (`"manual"` or `"litellm"`). An entry applies from its `from` date until the
next entry's. `refresh_rates.py` appends to that file from LiteLLM's public price list
and never rewrites an entry, so a session priced once prices the same forever.
"""

from __future__ import annotations

import json
from datetime import date as _date
from datetime import datetime as _datetime
from datetime import timezone as _timezone
from pathlib import Path
from typing import Optional, TypedDict

# The rate history this module prices from, read once at import. A missing or
# malformed file is an import error — loud, never a silent $0.
HISTORY_FILENAME = "rates_history.json"
HISTORY_PATH = Path(__file__).resolve().with_name(HISTORY_FILENAME)

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
        "source": str,  # "litellm" or "manual"
    },
)


def normalize_model_id(model_id: str) -> str:
    """Strip a trailing -YYYYMMDD date suffix, e.g.
    "claude-haiku-4-5-20251001" -> "claude-haiku-4-5". Leaves ids with no
    suffix, or a suffix that isn't 8 digits, unchanged.
    """
    parts = model_id.rsplit("-", 1)
    if len(parts) == 2 and len(parts[1]) == 8 and parts[1].isdigit():
        return parts[0]
    return model_id


def get_rates(model_id: str, as_of: str) -> Optional[RatesApplied]:
    """Return the rates in effect for `model_id` on ISO date `as_of`, or None
    if the history has no entry for the model on that date. `as_of` selects the
    entry — never the caller's wall-clock date — so a session keeps pricing at the
    rate in effect when it ran after a later entry is appended.
    """
    normalized = normalize_model_id(model_id)
    applied = None
    for entry in _HISTORY["models"].get(normalized, []):
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
