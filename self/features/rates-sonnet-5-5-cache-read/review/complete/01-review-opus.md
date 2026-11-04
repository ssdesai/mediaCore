# 01 — review: rates-sonnet-5-5-cache-read

## What the feature was supposed to do

Correct `claude-sonnet-5-5`'s cache-read rate in `analysis/rates_history.json`.
Anthropic's live pricing page
(`https://platform.claude.com/docs/en/about-claude/pricing.md`) prices Sonnet 5.5 cache
hits at 0.05× base input, $0.10 per million tokens. Its other rates are input 2, output 10,
5m write 2.50, 1h write 4. The history held $0.20. The fix goes through the harness's own
tool, `analysis/refresh_rates.py --only claude-sonnet-5-5`. It appends one dated entry and
never edits an existing one. `analysis/README.md` should record that Sonnet 5.5 cache reads
before the new entry are unconfirmed, and that a moved price is checked against the live
page.

No code changes are expected. If the diff touches any `.py` or `.sh` file, that is a finding.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **Append-only** (`analysis/README.md` → `rates_history.json`): every entry that exists
  on `main` must be byte-for-byte unchanged. `claude-sonnet-5-5` gains exactly one entry,
  after the `0000-01-01` one: `from` `2026-10-13`, `input` 2, `output` 10, `cache_read`
  0.1, `cache_creation_5m` 2.5, `cache_creation_1h` 4, `source` `"litellm"`. No other
  model changes. `checked` is `2026-10-13`.
- **Format**: one entry per line, the way `refresh_rates.serialize` writes it, with the
  file still valid JSON. `python3 analysis/pricing.py` should import cleanly, and
  `pricing.get_rates("claude-sonnet-5-5", "2026-10-13")` should return cache_read 0.1 while
  `"2026-10-12"` still returns 0.2.
- **Upstream agreement**: with network, `python3 analysis/refresh_rates.py --check` exits
  0. Without network, say so; that is not a finding.
- **The README notes** are accurate and match the feature's `NOTES.md`. They must not
  claim that $0.20 was or was not ever billed, because that is unknown. The feature's
  manifest and `NOTES.md` should agree with the diff.
- `./self/gate.sh` is green.

## Verdict

First line `Verdict: clean` or `Verdict: escalated`. If none of the contracts above is
broken, "no findings" is a legitimate and expected verdict.
