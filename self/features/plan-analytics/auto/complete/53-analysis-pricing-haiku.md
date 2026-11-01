# 53 — Pricing table and cost calculator

Feature: plan-analytics (plan 5 of 9) — tooling to price a feature end-to-end
(planning plus execution) and surface where delegated fanout wasted effort. This plan
adds the rate table and cost function every other analysis script prices tokens
through: `agentTooling/analysis/pricing.py`.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

Independent of other plans.

## Pinned facts

- All analysis tools are Python 3, **stdlib only** (no pip installs, no venv), living
  in `agentTooling/analysis/`. `agentTooling/` is a `git subtree`; `REPO_DIR` is its
  parent (the consuming repo root).
- Scripts in this folder run directly, e.g. `python3 agentTooling/analysis/pricing.py`
  — there is no package `__init__.py`. A sibling script can still `import pricing`
  because Python puts the invoked script's own directory on `sys.path[0]`.
- `agentTooling/analysis/` does not exist yet; this plan creates it.
- `agentTooling/README.md` has a `## Contents` table of one row per top-level file/folder
  in `agentTooling/` — a new row is needed for `analysis/`.

## Files

- Create `agentTooling/analysis/pricing.py`
- Create `agentTooling/analysis/README.md`
- Modify `agentTooling/README.md`

## `agentTooling/analysis/pricing.py`

Pure-data rate table plus small pure helpers — paste this file verbatim:

```python
"""Pricing table and cost calculator for Claude model usage.

Rates are USD per million tokens. Cache multipliers apply to the base input
rate: cache reads are cheaper than a fresh input token, cache writes are more
expensive because they also pay to store the prefix.
"""

from __future__ import annotations

from datetime import date as _date
from typing import Optional, TypedDict

# Rates verified against Anthropic's published pricing on this date. Re-verify
# and bump this whenever rates are re-checked; a stale RATES_VERIFIED is
# reported by callers as a warning, never silently trusted.
RATES_VERIFIED = "2026-07-30"

# Age, in days, past which RATES_VERIFIED must be treated as stale and callers
# should warn (never fail) that the table needs re-verification.
STALENESS_THRESHOLD_DAYS = 30

# Cache pricing is expressed as a multiplier on the model's base input rate.
CACHE_READ_MULTIPLIER = 0.1
CACHE_WRITE_5M_MULTIPLIER = 1.25
CACHE_WRITE_1H_MULTIPLIER = 2.0

# Base rates, USD per million tokens: {input, output}. Keyed by normalized
# model id (no trailing -YYYYMMDD suffix — see normalize_model_id).
# "intro" is an optional temporary override: {input, output, expires} where
# expires is an ISO date string ("YYYY-MM-DD"); on or before that date the
# intro rate applies instead of the base rate above.
RATES: dict[str, dict] = {
    "claude-opus-5": {"input": 5, "output": 25},
    "claude-fable-5": {"input": 10, "output": 50},
    "claude-mythos-5": {"input": 10, "output": 50},
    "claude-opus-4-8": {"input": 5, "output": 25},
    "claude-opus-4-7": {"input": 5, "output": 25},
    "claude-opus-4-6": {"input": 5, "output": 25},
    "claude-sonnet-5": {
        "input": 3,
        "output": 15,
        "intro": {"input": 2, "output": 10, "expires": "2026-08-31"},
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
    if intro is not None and as_of <= intro["expires"]:
        tier = "intro"
        base_input = intro["input"]
        base_output = intro["output"]

    return {
        "model": normalized,
        "input": base_input,
        "output": base_output,
        "cache_read": base_input * CACHE_READ_MULTIPLIER,
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


def is_rates_stale(today: Optional[str] = None) -> bool:
    """True when RATES_VERIFIED is more than STALENESS_THRESHOLD_DAYS old.
    `today` defaults to the real current date; pass an ISO string to test.
    """
    as_of = _date.fromisoformat(today) if today else _date.today()
    verified = _date.fromisoformat(RATES_VERIFIED)
    return (as_of - verified).days > STALENESS_THRESHOLD_DAYS
```

## `agentTooling/analysis/README.md`

New folder README. Content, in prose (this is the only script that exists yet — plans
54–56 each append their own entry to this same file later, do not stub entries for
scripts that don't exist):

- Opening paragraph: this folder holds the `plan-analytics` feature's tooling — stdlib-only
  Python 3 scripts (no pip installs, no venv) that price and report what a feature cost
  to plan and build, plus the JSON artifacts they read and write under `plans/`. Scripts
  are run directly (`python3 agentTooling/analysis/<name>.py`), not installed as a
  package.
- A `## Scripts` section with one entry per file. Per README Rule 1 (field lists for
  cross-module data shapes), list every exported name since other scripts in this same
  folder import from it:
  > - `pricing.py` — rate table and cost calculator. Exposes `RATES_VERIFIED` (date the
  >   table was last checked), `STALENESS_THRESHOLD_DAYS`, `RATES` (per-model USD/Mtok
  >   `{input, output}`, optional `intro{input, output, expires}`),
  >   `CACHE_READ_MULTIPLIER` / `CACHE_WRITE_5M_MULTIPLIER` / `CACHE_WRITE_1H_MULTIPLIER`,
  >   `normalize_model_id(model_id)`, `get_rates(model_id, as_of) -> RatesApplied | None`,
  >   `compute_cost(model_id, tokens, as_of) -> (cost_usd | None, rates_applied | None)`,
  >   `is_rates_stale(today=None) -> bool`. Any script that prices tokens imports
  >   `compute_cost` / `get_rates` / `is_rates_stale` from here rather than hardcoding
  >   rates — the table lives in exactly one place.
- A `## JSON artifacts` section, for now empty with a one-line note that it will list
  `usage.json`, `planning.json`, and `report.json` / `.report.md` as the
  scripts that produce them are added.

## `agentTooling/README.md`

Add one row to the existing `## Contents` table (after the `templates/` row), matching
the table's existing column style (`| `name` | description |`):

```
| `analysis/` | Stdlib-only Python scripts pricing and reporting what a feature cost to plan and build — the rate table, usage-sidecar backfill, planning-session capture, and the cross-feature cost report. See `analysis/README.md`. |
```
