# 01 — review: rates-refresh-2026-11

Review a data refresh of `analysis/rates_history.json`, written from the spec before the
build. "No findings" is a legitimate verdict: this is a small, mechanical change, and a
clean diff should be called clean.

## What the feature was supposed to do

- Refresh `analysis/rates_history.json`, which was last checked on 2026-10-13, so that its
  `checked` date becomes the build date (2026-11-18) through
  `python3 analysis/refresh_rates.py`, not a hand edit.
- Add the two models that `refresh_rates.py --check` reported as missing,
  `claude-fable-5-2` and `claude-mythos-5-2`, each with input 8, output 40, cache_read 0.2,
  cache_creation_5m 10 and cache_creation_1h 16. Each is a first entry at
  `"from": "0000-01-01"` with `"source": "litellm"`, exactly as the script writes it.
- Check every appended figure against Anthropic's own pricing page first
  (`analysis/README.md`, `self/features/rates-haiku-live-warning/NOTES.md`). A figure that
  cannot be verified is either declined with `--only` or named in NOTES as taken
  unverified. The cache read at 0.025× input breaks the usual 0.1× ratio, so it needs
  explicit confirmation in NOTES and must not be assumed.
- **Excluded:** no change to `refresh_rates.py`, `pricing.py` or any other code; no edit,
  removal or re-dating of an existing history entry (an appended entry is never taken
  back); no prices for models the check did not name.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `analysis/rates_history.json`: the existing entries are byte-for-byte unchanged; the
  only changes are `checked` and the two appended model arrays, each with the five rate
  fields plus `from` and `source`, in the shape every other entry uses.
- `self/features/rates-refresh-2026-11/NOTES.md` records what `--check` reported, the
  source the figures were verified against (with the cache-read ratio explained), and
  the ruling on each model.
- `self/tests/rates-history.sh` and `./self/gate.sh` pass.
- Any README that states the history's checked date or its model list is current.
  Historical mentions of 2026-10-13 in other features' records are not stale.
- `python3 analysis/refresh_rates.py --check` after the build reports no missing models
  and no changes.

## Verdict
