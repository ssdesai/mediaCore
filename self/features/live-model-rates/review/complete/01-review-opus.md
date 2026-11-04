# 01 — review: live-model-rates

## What the feature was supposed to do

Read `self/features/live-model-rates/README.md` → "The spec" (six numbered points) and
"Deliberately excluded". In one line: a model absent from `rates_history.json` is priced
from LiteLLM at the moment it is missing (`source: "litellm-live"`), without the history
being written, and this repo's one short record (sandbox-consumer-reads planning) is
repaired after a refresh.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff.

## Contracts to hold it to

- **Import is network-free.** Importing `analysis/pricing.py` performs no fetch; a
  model the history knows never triggers one.
- **At most one fetch per process**, on the first miss, with a timeout; a failure is
  cached too, so a capture over many unknown-model sessions does not retry per session.
- **One parser.** The live lookup and `refresh_rates.py` use the same selection
  (anthropic provider, `claude-` key, undated beats dated, latest date wins) and the
  same conversion and rounding. Check there is exactly one copy of each. `refresh_rates.py`
  output and exit codes are unchanged (`self/tests/rates-history.sh` H*/T* still pass
  without edits to their expectations).
- **No circular import**, and every sandbox/test that copies `pricing.py` beside
  `rates_history.json` also copies the new module (the README says sandboxes copy
  `pricing.py`; find each and check).
- **`RatesApplied` shape.** `source` gains `"litellm-live"`; no field added or removed
  without the `analysis/README.md` field list (Rule 1) saying so. `from` is
  `0000-01-01` for a live price.
- **Never `(0.0, None)`.** Fetch failure or model absent upstream → `(None, None)`, and
  existing unknown-model warnings still fire.
- **History untouched by pricing.** No code path outside `refresh_rates.py` writes
  `rates_history.json`.
- **Visibility.** A live-priced figure is named as such wherever price provenance is
  surfaced (capture warnings / report / close residue) — not silently indistinguishable
  from a history price.
- **Tests offline.** Every new test goes through the offline seam; none reaches the
  network. Run `./self/gate.sh` yourself.
- **Repair.** `rates_history.json` gains only appended entries (no existing line
  changed); the sandbox-consumer-reads record now prices `claude-sonnet-5-5`, is no
  longer partial, and its total rose accordingly; no unrelated record changed
  (hook-hash-chained-cd needed no repair — see the manifest's spec point 6).
- **READMEs** for every touched folder describe the new module and the fallback.

## Verdict

"No findings" is a legitimate verdict. Report each finding with file:line, the concrete
failure, and severity; do not fix anything.
