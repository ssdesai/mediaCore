"""LiteLLM's public price list: the one fetch, selection and conversion.

Both readers of the list import this module and nothing else for it, so a rate priced
live and the entry a later refresh appends for the same model cannot disagree:

- `refresh_rates.py` appends what `upstream_rates` returns to `rates_history.json`;
- `pricing.py` prices a model the history lacks from the same `upstream_rates`, live.

It imports nothing from this package. `pricing.py` imports it, and `refresh_rates.py`
imports `pricing.py`, so anything here that imported `pricing` back would be circular —
which is why `normalize_model_id`, the one model-id rule both sides need, lives here and
`pricing` re-exports it. Importing this module fetches nothing; only `fetch` does.

Selection (self/features/litellm-pricing/NOTES.md): an entry whose `litellm_provider` is
"anthropic" and whose key starts "claude-", normalized; an undated key beats a dated
one, and among dated keys the latest date wins; an entry missing any of the five rates
is skipped and named. Conversion: per token -> per million, rounded to RATE_DECIMALS.
"""

from __future__ import annotations

import http.client
import json
import urllib.request

# Where LiteLLM publishes its price list.
LITELLM_PRICES_URL = (
    "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
)
# How long a fetch may take before it counts as failed — a capture runs --check and may
# price live, and a hung network must not hang a capture.
FETCH_TIMEOUT_S = 15
URL_SCHEMES = ("https://", "http://")

# Which upstream entries are Anthropic's own list prices.
ANTHROPIC_PROVIDER = "anthropic"
CLAUDE_KEY_PREFIX = "claude-"

# History field <- LiteLLM per-token field.
LITELLM_FIELDS = {
    "input": "input_cost_per_token",
    "output": "output_cost_per_token",
    "cache_read": "cache_read_input_token_cost",
    "cache_creation_5m": "cache_creation_input_token_cost",
    "cache_creation_1h": "cache_creation_input_token_cost_above_1hr",
}
TOKENS_PER_MILLION = 1_000_000
# Decimal places of USD per million kept from a conversion: $0.000001/Mtok, far below
# any real price step, far above the float noise of multiplying by a million.
RATE_DECIMALS = 6

# The `from` of every model's first history entry — and of a live price, which stands in
# for exactly that entry until a refresh writes it.
FIRST_ENTRY_FROM = "0000-01-01"

# A model id's trailing release date: "-" then this many digits.
DATE_SUFFIX_DIGITS = 8


class FetchError(Exception):
    """The price list could not be read or is not a JSON object."""


def normalize_model_id(model_id: str) -> str:
    """Strip a trailing -YYYYMMDD date suffix, e.g.
    "claude-haiku-4-5-20251001" -> "claude-haiku-4-5". Leaves ids with no
    suffix, or a suffix that isn't 8 digits, unchanged.
    """
    parts = model_id.rsplit("-", 1)
    if len(parts) == 2 and len(parts[1]) == DATE_SUFFIX_DIGITS and parts[1].isdigit():
        return parts[0]
    return model_id


def fetch(source: str) -> dict:
    """LiteLLM's price list from a URL or a local path."""
    try:
        if source.startswith(URL_SCHEMES):
            with urllib.request.urlopen(source, timeout=FETCH_TIMEOUT_S) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        else:
            with open(source) as f:
                data = json.load(f)
    # URLError is an OSError, JSONDecodeError a ValueError, and a truncated response an
    # HTTPException — uncaught, it would exit 1, which reads as CHANGES_EXIT.
    except (OSError, ValueError, http.client.HTTPException) as exc:
        raise FetchError(f"{source}: {exc}") from exc
    if not isinstance(data, dict):
        raise FetchError(f"{source}: not a JSON object")
    return data


def per_million(cost_per_token: float) -> float | int:
    """A per-token cost as USD per million, rounded to RATE_DECIMALS; integral -> int."""
    rate = round(cost_per_token * TOKENS_PER_MILLION, RATE_DECIMALS)
    return int(rate) if rate == int(rate) else rate


def _key_rank(key: str, normalized: str) -> tuple[int, str]:
    """Higher wins: an undated key beats every dated one; a later date beats an earlier."""
    if key == normalized:
        return (1, "")
    return (0, key[len(normalized) + 1:])


def upstream_entries(data: dict) -> tuple[dict[str, dict], list[str]]:
    """({normalized model: the winning upstream entry}, [incomplete upstream keys, with what
    they lack]). The one selection rule the refresh, `--tiers` and the live price read from."""
    winners: dict[str, tuple[tuple[int, str], dict]] = {}
    incomplete: dict[str, list[str]] = {}
    for key, entry in data.items():
        if not isinstance(entry, dict) or not key.startswith(CLAUDE_KEY_PREFIX):
            continue
        if entry.get("litellm_provider") != ANTHROPIC_PROVIDER:
            continue
        normalized = normalize_model_id(key)
        missing = [src for src in LITELLM_FIELDS.values()
                   if not isinstance(entry.get(src), (int, float))]
        if missing:
            incomplete.setdefault(normalized, []).append(f"{key}: missing {', '.join(missing)}")
            continue
        rank = _key_rank(key, normalized)
        if normalized not in winners or rank > winners[normalized][0]:
            winners[normalized] = (rank, entry)
    skipped = [line for model, lines in sorted(incomplete.items())
               if model not in winners for line in lines]
    return {model: entry for model, (_, entry) in winners.items()}, skipped


def upstream_rates(data: dict) -> tuple[dict[str, dict], list[str]]:
    """({normalized model: {field: rate}}, [incomplete upstream keys, with what they lack])."""
    entries, skipped = upstream_entries(data)
    return {model: {field: per_million(entry[src]) for field, src in LITELLM_FIELDS.items()}
            for model, entry in entries.items()}, skipped
