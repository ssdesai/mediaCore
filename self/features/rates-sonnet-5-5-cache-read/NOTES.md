# Notes — rates-sonnet-5-5-cache-read

## Why

`rates-haiku-live-warning`'s close warned that LiteLLM still lists `claude-sonnet-5-5`'s
cache read at 0.1 against the history's 0.2. That feature had held the figure on the
ground that "Anthropic's published cache-read rate for Sonnet 5.5 is $0.20". Its source
was a cached model table (the claude-api skill's, dated 2026-10-06), not the live page.

## What the live page says (2026-10-13)

`https://platform.claude.com/docs/en/about-claude/pricing.md`, Model pricing table:

```
| Claude Opus 5.5   | $4 / MTok | $5 / MTok    | $8 / MTok | $0.20 / MTok<sup>2</sup> | $20 / MTok |
| Claude Sonnet 5.5 | $2 / MTok | $2.50 / MTok | $4 / MTok | $0.10 / MTok<sup>2</sup> | $10 / MTok |
| Claude Sonnet 5   | $2 / MTok | $2.50 / MTok | $4 / MTok | $0.20 / MTok             | $10 / MTok |
```

Footnote 2: "Cache hits and refreshes on Claude Opus 5.5 and Claude Sonnet 5.5 are priced
at 0.05x the base input price." The prompt-caching section repeats it: "$0.20 USD per
million tokens on Claude Opus 5.5, $0.10 USD on Claude Sonnet 5.5".

The other four Sonnet 5.5 figures (2 / 10 / 2.5 / 4) match the history. Opus 5.5's 0.2 is
already 0.05×, so the history had it right.

## Rulings

- **Take LiteLLM's 0.1 with `--only claude-sonnet-5-5`.** This is the case `--only` was
  built for, run the other way. The entry is the one a full refresh would append
  (`source: "litellm"`, from today). It is the only difference in `--check`, so a full
  refresh would have written the same thing, but `--only` keeps the intent explicit.
- **No back-dated entry.** Whether Sonnet 5.5 was ever billed at $0.20 is unknown. The
  skill's cached table and the earlier ruling both said $0.20, which could mean a price
  change or could just as well be a copy that was wrong. Back-dating would re-price the corpus's
  earlier Sonnet 5.5 sessions (in `sandbox-consumer-reads`, `live-model-rates`,
  `execution-profiles`, `cloud-pull-fixes`, `hook-hash-chained-cd`,
  `cost-capture-collisions` and `review-base-and-cloud-hook` here, plus the consuming
  repos) on a guess. It is written up as unconfirmed in `analysis/README.md` → "Repair
  tools", next to Sonnet 5's `2026-08-22` entry, for whoever can settle it.
- **The refresh procedure names the live page.** The failure here was checking against a
  remembered or cached copy, so the "Check a moved price" line in `analysis/README.md` now
  names the URL and says never to use a cached copy.

## Verification

- `refresh_rates.py --check` before: one change, `claude-sonnet-5-5: cache_read 0.2 -> 0.1`,
  exit 1.
- `refresh_rates.py --only claude-sonnet-5-5`: `appended claude-sonnet-5-5: cache_read
  0.2 -> 0.1 from 2026-10-13`.
- `refresh_rates.py --check` after: exit 0.
- `./self/gate.sh`: green.
