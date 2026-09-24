#!/usr/bin/env python3
"""Refresh `rates_history.json` from LiteLLM's public price list.

    python3 analysis/refresh_rates.py [--check] [--source <path or url>] [--history <path>]

Reads the entries of LiteLLM's `model_prices_and_context_window.json` whose
`litellm_provider` is "anthropic" and whose key starts with "claude-", normalizes each
key with `pricing.normalize_model_id`, converts the five per-token costs to USD per
million, and for every model whose rates differ from its latest history entry — or
that has none — APPENDS an entry with `source: "litellm"`. It then sets `checked` to
today's UTC date. It never rewrites or removes an entry, so any session dated before a
refresh re-prices to the dollars it priced to before; a model the history holds and
LiteLLM lacks is left alone.

Rulings (self/features/litellm-pricing/NOTES.md):
- a converted rate is rounded to RATE_DECIMALS places before it is compared or stored,
  so the per-token -> per-million float noise never reads as a price change;
- where a dated key and an undated key normalize to one model, the undated key wins;
  with no undated key, the latest dated key wins;
- an appended entry starts today, except a model's FIRST entry, which starts at
  FIRST_ENTRY_FROM like every model's first entry;
- an upstream entry missing any of the five rates is skipped and named.

`--check` fetches and diffs, prints each model that would change, writes nothing, and
exits CHANGES_EXIT with changes and NO_CHANGES_EXIT without. A fetch failure prints the
reason and exits FETCH_FAILED_EXIT, in both modes, having written nothing. Either mode
first prints the history's `checked` date and whether it is stale.

The history ships to every consuming repo through the subtree: run the write mode only
in an agentTooling self feature, never in a consuming repo.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import sys
import urllib.request
from pathlib import Path

import pricing

# Where LiteLLM publishes its price list.
LITELLM_PRICES_URL = (
    "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
)
# How long a fetch may take before it counts as failed — a capture runs --check, and a
# hung network must not hang a capture.
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

# Entry bookkeeping.
LITELLM_SOURCE = "litellm"
FIRST_ENTRY_FROM = "0000-01-01"

# Exit codes. 2 is argparse's usage error, so a fetch failure is 3.
NO_CHANGES_EXIT = 0
CHANGES_EXIT = 1
FETCH_FAILED_EXIT = 3

JSON_INDENT = "  "


class FetchError(Exception):
    """The price list could not be read or is not a JSON object."""


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


def upstream_rates(data: dict) -> tuple[dict[str, dict], list[str]]:
    """({normalized model: {field: rate}}, [incomplete upstream keys, with what they lack])."""
    winners: dict[str, tuple[tuple[int, str], dict]] = {}
    incomplete: dict[str, list[str]] = {}
    for key, entry in data.items():
        if not isinstance(entry, dict) or not key.startswith(CLAUDE_KEY_PREFIX):
            continue
        if entry.get("litellm_provider") != ANTHROPIC_PROVIDER:
            continue
        normalized = pricing.normalize_model_id(key)
        missing = [src for src in LITELLM_FIELDS.values()
                   if not isinstance(entry.get(src), (int, float))]
        if missing:
            incomplete.setdefault(normalized, []).append(f"{key}: missing {', '.join(missing)}")
            continue
        rates = {field: per_million(entry[src]) for field, src in LITELLM_FIELDS.items()}
        rank = _key_rank(key, normalized)
        if normalized not in winners or rank > winners[normalized][0]:
            winners[normalized] = (rank, rates)
    skipped = [line for model, lines in sorted(incomplete.items())
               if model not in winners for line in lines]
    return {model: rates for model, (_, rates) in winners.items()}, skipped


def plan_changes(history: dict, upstream: dict[str, dict], today: str) -> list[tuple[str, dict, dict | None]]:
    """[(model, entry to append, latest entry it replaces or None)], sorted by model."""
    changes = []
    for model in sorted(upstream):
        rates = upstream[model]
        entries = history["models"].get(model) or []
        latest = entries[-1] if entries else None
        if latest is not None and all(latest[f] == rates[f] for f in pricing.RATE_FIELDS):
            continue
        entry = {"from": today if latest is not None else FIRST_ENTRY_FROM}
        entry.update(rates)
        entry["source"] = LITELLM_SOURCE
        changes.append((model, entry, latest))
    return changes


def describe(model: str, entry: dict, latest: dict | None) -> str:
    if latest is None:
        figures = ", ".join(f"{f} {entry[f]}" for f in pricing.RATE_FIELDS)
        return f"{model}: new, {figures}"
    moved = ", ".join(f"{f} {latest[f]} -> {entry[f]}"
                      for f in pricing.RATE_FIELDS if latest[f] != entry[f])
    return f"{model}: {moved} from {entry['from']}"


def serialize(history: dict) -> str:
    """The history's on-disk form: one entry per line, so a diff shows one line per price."""
    lines = ["{"]
    lines.append(f'{JSON_INDENT}"checked": {json.dumps(history["checked"])},')
    lines.append(f'{JSON_INDENT}"source_url": {json.dumps(history["source_url"])},')
    lines.append(f'{JSON_INDENT}"models": {{')
    models = list(history["models"].items())
    for i, (model, entries) in enumerate(models):
        lines.append(f"{JSON_INDENT * 2}{json.dumps(model)}: [")
        for j, entry in enumerate(entries):
            comma = "," if j < len(entries) - 1 else ""
            lines.append(f"{JSON_INDENT * 3}{json.dumps(entry)}{comma}")
        comma = "," if i < len(models) - 1 else ""
        lines.append(f"{JSON_INDENT * 2}]{comma}")
    lines.append(f"{JSON_INDENT}}}")
    lines.append("}")
    return "\n".join(lines) + "\n"


def write_history(path: Path, history: dict) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(serialize(history))
    os.replace(tmp, path)


def status_line(history: dict, today: str) -> str:
    checked = history["checked"]
    if pricing.is_rates_stale(today=today, checked=checked):
        return (f"verified {checked} — rate history is stale (older than "
                f"{pricing.STALENESS_THRESHOLD_DAYS} days)")
    return f"verified {checked} (fresh)"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="diff against LiteLLM and write nothing; exit 1 if anything would change")
    parser.add_argument("--source", default=LITELLM_PRICES_URL,
                        help="a URL or path to read LiteLLM's price list from (default: LITELLM_PRICES_URL)")
    parser.add_argument("--history", type=Path, default=pricing.HISTORY_PATH,
                        help="the rate history to read and append to (default: rates_history.json beside pricing.py)")
    args = parser.parse_args(argv)

    today = pricing.utc_today()
    history = pricing.load_history(args.history)
    print(status_line(history, today))

    try:
        data = fetch(args.source)
    except FetchError as exc:
        print(f"litellm fetch failed, history not checked: {exc}", file=sys.stderr)
        return FETCH_FAILED_EXIT

    upstream, skipped = upstream_rates(data)
    for line in skipped:
        print(f"skipped (incomplete) {line}")
    changes = plan_changes(history, upstream, today)
    verb = "would change" if args.check else "appended"
    for model, entry, latest in changes:
        print(f"{verb} {describe(model, entry, latest)}")

    if args.check:
        if changes:
            print(f"{len(changes)} model(s) differ from litellm; refresh with "
                  "analysis/refresh_rates.py in an agentTooling self feature")
            return CHANGES_EXIT
        print("no changes against litellm")
        return NO_CHANGES_EXIT

    for model, entry, _ in changes:
        entries = history["models"].setdefault(model, [])
        entries.append(entry)
        entries.sort(key=lambda e: e["from"])  # stable: a same-day entry stays after its peer
    history["checked"] = today
    history["source_url"] = LITELLM_PRICES_URL
    write_history(args.history, history)
    print(f"{len(changes)} entr{'y' if len(changes) == 1 else 'ies'} appended; checked {today}")
    return NO_CHANGES_EXIT


if __name__ == "__main__":
    sys.exit(main())
