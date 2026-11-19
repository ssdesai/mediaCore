# Notes — rates-refresh-2026-11

## Why

`analysis/rates_history.json` was last checked on 2026-10-13, more than 30 days before this
build. Running `refresh_rates.py --check` on 2026-11-18 exited 4 (`NEW_ONLY_EXIT`) and
reported:

```
verified 2026-10-13 — rate history is stale (older than 30 days)
would change claude-fable-5-2: new, input 8, output 40, cache_read 0.2, cache_creation_5m 10, cache_creation_1h 16
would change claude-mythos-5-2: new, input 8, output 40, cache_read 0.2, cache_creation_5m 10, cache_creation_1h 16
```

These are the same figures the orchestrator saw on 2026-11-17, and no recorded price has
moved. `--tiers` reports no tiered rate for any model in the corpus.

## Verification

Anthropic's pricing page (`platform.claude.com/docs/en/about-claude/pricing`) was
reachable on 2026-11-18. It lists:

| Model | Base input | 5m cache writes | 1h cache writes | Cache hits | Output |
|---|---|---|---|---|---|
| Claude Fable 5.2 | $8 | $10 | $16 | $0.20 | $40 |
| Claude Mythos 5.2 | $8 | $10 | $16 | $0.20 | $40 |

Every figure LiteLLM carries matches, all ten of them, so none is taken unverified.

**The cache read is not a LiteLLM error.** At 0.025× input it breaks the 0.1× ratio, which
is the pattern that held Sonnet 5.5's figure in `rates-haiku-live-warning`. Here, though,
the page's footnote 1 states it outright: "Cache hits and refreshes on Claude Fable 5.2,
Claude Mythos 5.2, Claude Fable 5.1, and Claude Mythos 5.1 are priced at 0.025x the base
input price". Fable 5.1 and Mythos 5.1 are already in the history at that ratio (0.25 on
$10). The cache writes follow the standard 1.25× and 2×.

## Rulings

- **Both models are taken, with no `--only`.** Nothing was in doubt, so this was a full
  refresh and `checked` is now 2026-11-18. Both are first entries at `0000-01-01` with
  `source: "litellm"`, as every model's first entry is.
- **No README changes.** No README states the history's current checked date or its model
  list. The 2026-10-13 mentions in `analysis/README.md` and in other features' records
  are historical and stay correct.
- **Built by the coordinator.** The orchestrator started this feature with
  `--method direct`. The change is one script run and a NOTES file, so this session made
  it itself and spawned no implementer delegate. The cost therefore lands under
  `build: implementer` but carries the coordinator's spend.

## Verification after the refresh

- `refresh_rates.py --check`: no changes, exit 0.
- `bash self/tests/rates-history.sh`: all assertions passed.
- `./self/gate.sh`: all checks passed.
