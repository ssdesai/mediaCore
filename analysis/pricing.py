"""Pricing table and cost calculator for Claude model usage.

Rates are USD per million tokens. Cache multipliers apply to the base input
rate: cache reads are cheaper than a fresh input token, cache writes are more
expensive because they also pay to store the prefix.
"""

from __future__ import annotations

from datetime import date as _date
from datetime import datetime as _datetime
from datetime import timezone as _timezone
from typing import Optional, TypedDict

# Rates verified against Anthropic's published pricing on this date. Re-verify
# and bump this whenever rates are re-checked; a stale RATES_VERIFIED is
# reported by callers as a warning, never silently trusted.
# NOTE: claude-sonnet-5's intro.starts date was inferred from observed billing
# ratios in this repo's usage corpus and is pending confirmation against
# Anthropic's published rates.
RATES_VERIFIED = "2026-09-04"

# Age, in days, past which RATES_VERIFIED must be treated as stale and callers
# should warn (never fail) that the table needs re-verification.
STALENESS_THRESHOLD_DAYS = 30

# Cache pricing is expressed as a multiplier on the model's base input rate. An entry
# may carry its own "cache_read_multiplier" where the published rate departs from the
# default — Fable 5.1 and Mythos 5.1 read cache at 0.025x, per the pricing page.
CACHE_READ_MULTIPLIER = 0.1
CACHE_WRITE_5M_MULTIPLIER = 1.25
CACHE_WRITE_1H_MULTIPLIER = 2.0

# Base rates, USD per million tokens: {input, output}. Keyed by normalized
# model id (no trailing -YYYYMMDD suffix — see normalize_model_id).
# "intro" is an optional temporary override: {input, output, starts, expires} where
# starts and expires are ISO date strings ("YYYY-MM-DD"); on or between (inclusive)
# those dates the intro rate applies instead of the base rate above.
RATES: dict[str, dict] = {
    "claude-opus-5": {"input": 5, "output": 25},
    "claude-fable-5-1": {"input": 10, "output": 50, "cache_read_multiplier": 0.025},
    "claude-mythos-5-1": {"input": 10, "output": 50, "cache_read_multiplier": 0.025},
    "claude-fable-5": {"input": 10, "output": 50},
    "claude-mythos-5": {"input": 10, "output": 50},
    "claude-opus-4-8": {"input": 5, "output": 25},
    "claude-opus-4-7": {"input": 5, "output": 25},
    "claude-opus-4-6": {"input": 5, "output": 25},
    "claude-sonnet-5": {
        "input": 3,
        "output": 15,
        # Announced as introductory through 2026-08-31 and made permanent on 2026-09-01
        # (platform.claude.com/docs/en/about-claude/pricing, read 2026-09-04): the
        # window is left open-ended rather than re-basing the entry, so sessions before
        # 2026-08-22 keep the 3/15 they were billed at. The start date was inferred from
        # observed billing ratios in this repo's corpus.
        "intro": {"input": 2, "output": 10, "starts": "2026-08-22", "expires": "9999-12-31"},
    },
    "claude-sonnet-4-6": {"input": 3, "output": 15},
    "claude-haiku-4-5": {"input": 1, "output": 5},
}


class RatesApplied(TypedDict):
    model: str
    input: float
    output: float
    cache_read: float
    cache_creation_5m: float
    cache_creation_1h: float
    tier: str  # "standard" or "intro"


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
    if the model is not in RATES. `as_of` selects intro vs standard pricing —
    never the caller's wall-clock date — so a session captured while an intro
    window was active continues to price at the intro rate even after it
    expires.
    """
    normalized = normalize_model_id(model_id)
    entry = RATES.get(normalized)
    if entry is None:
        return None

    tier = "standard"
    base_input = entry["input"]
    base_output = entry["output"]
    intro = entry.get("intro")
    if intro is not None and intro["starts"] <= as_of <= intro["expires"]:
        tier = "intro"
        base_input = intro["input"]
        base_output = intro["output"]

    return {
        "model": normalized,
        "input": base_input,
        "output": base_output,
        "cache_read": base_input * entry.get("cache_read_multiplier", CACHE_READ_MULTIPLIER),
        "cache_creation_5m": base_input * CACHE_WRITE_5M_MULTIPLIER,
        "cache_creation_1h": base_input * CACHE_WRITE_1H_MULTIPLIER,
        "tier": tier,
    }


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


def is_rates_stale(today: Optional[str] = None) -> bool:
    """True when RATES_VERIFIED is more than STALENESS_THRESHOLD_DAYS old.
    `today` defaults to the current UTC date; pass an ISO string to test.
    """
    as_of = _date.fromisoformat(today or utc_today())
    verified = _date.fromisoformat(RATES_VERIFIED)
    return (as_of - verified).days > STALENESS_THRESHOLD_DAYS
