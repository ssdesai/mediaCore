Verdict: clean

# Review — rates-refresh-2026-11

## What the batch was supposed to do

Refresh `analysis/rates_history.json`, last checked on 2026-10-13, with
`refresh_rates.py`. The refresh adds the two models `--check` reported as missing,
`claude-fable-5-2` and `claude-mythos-5-2`, each at input 8, output 40, cache_read 0.2,
cache_creation_5m 10 and cache_creation_1h 16, and moves `checked` to 2026-11-18. Every
figure had to be checked against Anthropic's pricing page first, and the 0.025× cache-read
ratio had to be confirmed explicitly. No code changes were allowed, and no existing
history entry could be edited.

## Does it do it

Yes.

- **`analysis/rates_history.json`**: the diff changes `checked` (2026-10-13 → 2026-11-18)
  and appends two model arrays, and nothing else. Every existing entry is byte-for-byte
  unchanged. Each new entry starts at `"from": "0000-01-01"` with `"source": "litellm"`,
  holds the five rate fields with the specified figures, and uses the one-entry-per-line
  shape every other entry uses.
- **`NOTES.md`** records:
  - the `--check` output (exit 4, `NEW_ONLY_EXIT`, both models new);
  - the pricing-page table for both models;
  - the cache-read ratio, quoted from the page's footnote and cross-checked against the
    existing Fable 5.1 and Mythos 5.1 entries, which are also at 0.025× (0.25 on $10). I
    confirmed those two entries in the file;
  - the ruling: both models were taken, with no `--only`.
- **No code changed.** The diff touches only the history file and this feature's own
  records.
- **READMEs**: `analysis/README.md` does not state the current `checked` date or list the
  models. Its 2026-10-13 mentions concern Sonnet 5.5's cache-read entry and are
  historical, so no README is stale.
- **Gate** (`self/gate-report.txt`): green with nothing skipped, and
  `self/tests/rates-history.sh` reports all assertions passed.

## Fixed in this pass

Nothing.

## Escalated to the next round

Nothing.
