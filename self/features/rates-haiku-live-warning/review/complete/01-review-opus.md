# 01 — review: rates-haiku-live-warning

## What the feature was supposed to do

A consuming repo's capture warned that the rate history was out of date for two models,
Haiku 5.5 and Sonnet 5.5. That warning sounded the same whether a model was missing
(which `pricing.py`'s live fallback already prices) or a recorded price had moved. The
feature does three things:

1. **Adds Haiku 5.5 to `analysis/rates_history.json`** as one `litellm` entry from
   `0000-01-01` at LiteLLM's figures (input 0.1, output 0.5, cache_read 0.01,
   cache_creation_5m 0.125, cache_creation_1h 0.2). Those match Anthropic's published
   $0.10 / $0.50 per MTok (for prompts up to 100K). `checked` moves to the refresh date.
   **Sonnet 5.5 is deliberately not refreshed**: LiteLLM now says its cache_read is 0.1,
   while Anthropic's published figure is still $0.20. An appended entry can never be taken
   back, so the disputed figure is held.
2. **`refresh_rates.py --only <model>`** (repeatable, dated alias normalized, write mode
   only; refused beside `--check`/`--tiers`). It appends only the named models, prints
   every other difference as `held …`, prints `no change for …` for a named model with no
   difference, and still sets `checked`. The Haiku entry was written with it.
3. **`--check` tells a new model from a moved price.** It exits `CHANGES_EXIT` (1) when any
   recorded price moved and the new `NEW_ONLY_EXIT` (4) when every difference is a model
   the history lacks; its last line is the matching summary. `feature-capture.sh`'s
   residue prints a `WARN` for 1 (now telling the reader to check the figure against
   Anthropic's pricing page first) and a `note` for 4 (saying the models are priced live
   and no figure is wrong).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

Expected files: `analysis/refresh_rates.py`, `analysis/rates_history.json`,
`feature-capture.sh`, `self/tests/rates-history.sh`, and the READMEs and `LIFECYCLE.md`
that describe `--check` and the residue, plus this feature's directory.

## Contracts to hold it to

- **The history is append-only.** The diff to `rates_history.json` adds exactly one model
  list (`claude-haiku-5-5`) and changes `checked`. No existing entry is edited, removed
  or reordered (`rates-history.sh` H0 asserts it against the seed).
- **Exit codes.** `NEW_ONLY_EXIT` is none of 0, 1, 2 (argparse) or 3 (`FETCH_FAILED_EXIT`).
  `feature-capture.sh`'s `RATES_NEW_ONLY_RC` must equal it, as `RATES_CHANGED_RC` equals
  `CHANGES_EXIT`, because bash cannot import them. A mixed diff (some new, some moved) must
  be 1, never 4.
- **No caller is broken by the new exit code.** Grep for every reader of
  `refresh_rates.py`'s exit status (`feature-capture.sh`, `run-batch.sh`, `self/gate.sh`,
  the tests) and confirm that 4 is handled or harmless everywhere. The capture must
  still never refuse on the rates check.
- **`--only` takes exactly what a full refresh would** for the named model (the same
  entry, the same `from`). It never appends a held model, and it normalizes an alias the
  way `plan_changes` keys do.
- **The live fallback is unchanged.** `pricing.py` and `litellm_prices.py` are untouched.
- **Docs match code.** The `refresh_rates.py` entry in `analysis/README.md`, the repair
  section there, `self/tests/README.md` (H10, H11, C3a2), `LIFECYCLE.md` and the root
  `README.md` describe the same codes and wordings the code prints.
- **Named constants.** Exit codes and summary wordings are module constants, not inline
  literals (CONVENTIONS.md → "Named constants").

Not a finding: `feature-lifecycle.sh` has no end-to-end case for the `note` branch. The
exit code that drives it is asserted in H11, and the branch itself is two lines of bash.
If you think it needs one anyway, say so.

## Verdict

"No findings" is a legitimate verdict. Fix local issues in the pass. Escalate anything
structural, such as a change to how the history is written or to the live fallback.
