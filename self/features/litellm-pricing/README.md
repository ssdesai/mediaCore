# LiteLLM-sourced rate history

Replace the hand-maintained `RATES` table in `analysis/pricing.py` with a **dated rate
history** kept in the repo and refreshed by one command from LiteLLM's public price list,
`model_prices_and_context_window.json`. Today, updating rates means researching the
pricing page and editing a Python dict by hand, and the only safeguard is a 30-day staleness
warning. LiteLLM was chosen over pydantic's `genai-prices` after comparing both against the
current table on 2026-09-23. LiteLLM had every rate `pricing.py` holds except
`claude-mythos-5-1`, including Opus 5.5's 0.05× and Fable 5.1's 0.025× cache reads and the
1-hour cache-write rate. genai-prices lacked Opus 5.5, Fable 5.1 and Mythos 5.1, had no
1-hour cache-write rate, and its dated Sonnet 5 entry disagreed with the published price.

## Spec

The pinned names below are used exactly.

1. **The history file: `analysis/rates_history.json`.** One file, stored in agentTooling
   and shipped with the subtree like every other file here. Shape:
   `{ "checked": "YYYY-MM-DD", "source_url": "<litellm raw url>", "models": { "<normalized id>": [ { "from": "YYYY-MM-DD", "input", "output", "cache_read", "cache_creation_5m", "cache_creation_1h", "source" } ] } }`.
   - All rates are USD per million tokens and absolute. The history stores no multipliers.
   - Each model's entries are sorted by `from`, and an entry applies from its `from` date
     until the next entry's `from`.
   - `source` is `"litellm"` or `"manual"`.
   - The first entry of each model uses `from: "0000-01-01"`.
2. **Seeding with no drift.** The history's first version must reproduce exactly the
   figures the current `RATES` table produces, for every model and every date.
   - That includes `claude-sonnet-5` at 3/15 before 2026-08-22 and 2/10 from that date,
     written as two dated entries (the old `intro` window becomes an ordinary price
     change).
   - It also includes each model's cache multipliers, turned into absolute rates.
   - The seeded entries are `"manual"`. The comment that says Sonnet 5's start date was
     inferred from observed billing ratios moves into the history's README entry.
3. **`pricing.py` reads the history.** It stops holding a table itself.
   - `get_rates(model_id, as_of)` returns the entry in effect on `as_of`.
   - Keep the public names callers import: `get_rates`, `compute_cost`,
     `normalize_model_id`, `utc_today`, `is_rates_stale`, and `RATES_VERIFIED`, which is now
     the history's `checked` date.
   - Keep `compute_cost`'s return contract, where an unknown model gives `(None, None)` and
     never 0.
   - `RatesApplied` gains a `source` field (`"litellm"` or `"manual"`) and a `from` field
     (the entry's `from` date), so every `rates_applied` written into `planning.json` and
     into an attempt records where its rates came from.
   - `tier` stays in the shape for existing readers. Its value is `"standard"` for every
     entry.
4. **The refresh command: `analysis/refresh_rates.py`.** It is stdlib-only
   (`urllib.request`, `json`).
   - It fetches LiteLLM's JSON from the constant `LITELLM_PRICES_URL`, or from `--source
     <path or url>`, which is how the tests stay offline.
   - It reads the entries whose `litellm_provider` is `"anthropic"` and whose key starts
     with `claude-`, normalized with `normalize_model_id`. Where a dated key and an undated
     key differ, the implementer rules which wins and records the ruling.
   - It converts per-token costs to per-million: `input_cost_per_token`,
     `output_cost_per_token`, `cache_read_input_token_cost`,
     `cache_creation_input_token_cost` → `cache_creation_5m`, and
     `cache_creation_input_token_cost_above_1hr` → `cache_creation_1h`.
   - For each model whose converted rates differ from its latest history entry, or that has
     no entry, it appends an entry with `from` set to today's UTC date and
     `source: "litellm"`. It then sets `checked` to today.
   - It **never rewrites or removes an existing entry**, so re-pricing any session dated
     before a refresh gives the same dollars it gave before. That is what makes a
     re-capture reproduce the figures it replaces.
   - A model present in the history but absent from LiteLLM (Mythos 5.1) is left
     untouched.
   - Floating-point noise from the per-token → per-million conversion must not register as
     a change. How is up to the implementer, recorded as a ruling.
   - `--check` fetches and diffs, prints each model that would change, writes nothing, and
     exits 0 with no changes and 1 with changes. A fetch failure prints the reason and
     exits with a distinct non-zero code.
5. **Callers.**
   - `feature-capture.sh`'s rates line stops telling a human to edit `RATES` by hand. It
     reports `checked` and whether the history is stale, and it runs `refresh_rates.py
     --check` and prints the result.
   - That check is a warning only: it never refuses, and a network failure is one line,
     not a stop.
   - The capture never **writes** the history. A refresh that finds a change is its own
     self feature, because the file ships to every consuming repo through the subtree and
     a consumer must never edit it.
   - `capture_planning.py`'s `rates_source` string and staleness warning, and
     `report.py`'s "Rates last verified" footer, read the new source. The wording is the
     implementer's choice.

## Plans

| Plan | What it does |
|---|---|
| `review/complete/01-review-opus.md` | Independent review of the direct build against the spec above — round 1, clean |
| `review/complete/02-review-sonnet.md` | Round 2: the merge of `origin/main` (PR #61, carry-stream-sections) only — clean |

## Deliberately excluded

- **Long-context (above 200k tokens) and other tiered pricing.** The current table ignores
  it too. Adding it changes which figures are correct, not just where the rates come from.
  It gets a `self/BACKLOG.md` entry.
- **Reusing each prior `rates_applied` on `--recapture`.** A history that is only ever
  appended to gives the same answer from one place (`pricing.get_rates`). Reusing prior
  rates would instead touch every `compute_cost` call site in `capture_planning.py`,
  `recover_attempts.py` and `routing.py`.
- **Fetching during capture.** Capture reads only the committed history, so its figures
  never depend on the network or on the day it ran.
- **genai-prices as a second source.** It was compared and rejected (see above).

## Machine-readable

```json
{
  "slug": "litellm-pricing",
  "method": "direct",
  "plans": ["01-review-opus", "02-review-sonnet"],
  "branches": ["litellm-pricing"],
  "base": "main",
  "session_window": {"from": "2026-09-23T15:55:46Z", "to": "2026-09-23T16:40:59Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["f95dbb82-60da-4017-af85-60cd44c218f2"],
  "subagents": ["a1b904cbda55fd01f"]
}
```

This session (`f95dbb82…`) started the feature as its router and was then kept on as its
coordinator, on `main` in the primary checkout. So it is pinned in `sessions`, and the
routing record `feature-start.sh` wrote for it is removed: a pinned session is never also
a router (`self/PROJECT_FACTS.md` → Commands). The implementer is spawned from this
session and not from the branch, so its agent id is pinned in `subagents` once it exists.
