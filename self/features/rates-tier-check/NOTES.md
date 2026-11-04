# rates-tier-check — notes

Direct build (`AGENT_DIRECT.md`). Rulings as made, each with its reason.

## The finding (real corpus, 2026-09-27)

Run: `python3 -B analysis/refresh_rates.py --tiers` in this worktree (self corpus, live
LiteLLM), plus a one-off scratch run of the same functions (`corpus_models`,
`report_tiers`) over every corpus on this machine and, as a cross-check, over every
transcript under `~/.claude/projects`.

- **Models the corpus uses** (cost records): self — Fable 5.1, Haiku 4.5, Opus 5, Opus
  5.5, Sonnet 5; vinylCatalogue adds Fable 5; humanNetworkMap adds Opus 4.8; musicMap and
  mediaCore match self. Union: `claude-fable-5`, `claude-fable-5-1`, `claude-haiku-4-5`,
  `claude-opus-4-8`, `claude-opus-5`, `claude-opus-5-5`, `claude-sonnet-5`. The
  transcripts name the same set minus Opus 4.8 (its transcripts have aged out).
- **Which carry a tier: none.** Every one reads `no tier`; the residue line is "no model in
  the corpus carries a tiered rate". Among LiteLLM's Anthropic `claude-*` entries only
  `claude-sonnet-4-5` (and its dated alias) carries `*_above_200k_tokens` fields —
  input 6, output 22.5, cache_read 0.6, cache_creation_5m 7.5, cache_creation_1h 12 per
  million — and no corpus uses it.
- **Why it still matters:** prompts past 200k are common. Transcript responses with
  input + cache read + cache write over 200k: Opus 5 7,213 of 21,636; Opus 5.5 2,166 of
  7,702; Fable 5.1 1,710 of 4,213; Fable 5 623 of 1,574; Sonnet 5 865 of 7,458; Haiku 4.5
  none. So the gap is real the day LiteLLM (or Anthropic) prices one of these models by
  tier; today it is flat upstream. The backlog entry is parked on that, not closed.

## Rulings

- **"The models the corpus uses" are the ones its cost records name**, not a transcript
  scan: `planning.json` `priced[].model`, and every `*usage.json`'s `model_usage` keys and
  its attempts' `rates_applied` / `recovered_tokens` keys, across both features roots
  (`roots.all_features_roots()`), normalized with `pricing.normalize_model_id`. Records
  are committed and never expire, cost nothing to read at every capture, and are exactly
  what the corpus prices; transcripts expire in about four weeks and a full scan takes
  minutes. The one-off transcript cross-check above agreed.
- **Tier suffixes: `TIER_SUFFIXES`, every `_above_<N>k_tokens` threshold in the live list**
  (32k, 128k, 200k, 256k, 272k, 512k), keyed by label. A tier field is read only as
  `<one of the five flat fields><suffix>` exactly, so `cache_creation_input_token_cost_above_1hr_above_200k_tokens`
  is the 1h-cache tier and `…_above_1hr` alone (the 1h cache rate) is never a tier.
- **Service-tier variants are not read.** `_batches`, `_priority` and `_flex` follow the
  threshold suffix; they are other price lists (Batch API etc.), which Claude Code does
  not bill at. The test fixture carries Sonnet 4.5's `_batches` fields and T2 asserts the
  report shows the standard ones.
- **Same entry the refresh reads.** `upstream_entries` is the refresh's key rule
  (undated beats dated, latest date wins, incomplete entries skipped) factored out;
  `upstream_rates` and `--tiers` both call it, so the report cannot read a different
  entry from the one whose flat rates the history holds.
- **Flag shape:** `--tiers`, mutually exclusive with `--check`; writes nothing; exit 1 when
  a corpus model carries a tier, 0 when none does, `FETCH_FAILED_EXIT` (3) on a fetch
  failure — `--check`'s pair, reused as `TIERS_FOUND_EXIT` / `NO_TIERS_EXIT`. It skips the
  history status line so its last line is always the summary (or the fetch failure).
- **Summary wording** is the brief's, with the threshold labels joined: "N model(s) carry an
  above-200k tier: <models> — tiered pricing is unbuilt, see self/BACKLOG.md" (a model
  tiered at another threshold would read "above-128k/200k"). A model the corpus names and
  LiteLLM lacks prints `not in litellm` and counts as untiered.
- **No cache.** `refresh_rates.py` kept no copy of LiteLLM's JSON and this adds none: offline
  it needs `--source <local file>`. The residue runs `--tiers` as a second fetch of the same
  source (`RATES_CHECK_SOURCE` included), each bounded by `FETCH_TIMEOUT_S`; a cache would be
  a new on-disk artifact shipping through the subtree for a 15-second worst case.
- **Residue line** is `  tiers     <last line of --tiers>`, after the rates lines and their
  WARN, which are unchanged. It is informational, like the rest of the residue — a tier
  found never refuses a capture.
- `rates-history.sh`'s sandbox now copies `roots.py` as well (refresh_rates.py imports it);
  the two other sandboxes that copy `refresh_rates.py` already copied it.

## Deviations and open questions

- None from the brief. `analysis/rates_history.json` is untouched, as the brief required,
  though `--check` against live LiteLLM reports `claude-mythos-preview` as new.
