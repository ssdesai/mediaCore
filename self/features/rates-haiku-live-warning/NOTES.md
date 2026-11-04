# Notes — rates-haiku-live-warning

## Why

A humanNetworkMap session relayed the capture residue's warning: "the tooling's model
prices are out of date for two models, Haiku 5.5 and Sonnet 5.5." Running
`refresh_rates.py --check` against the live list on 2026-10-13 gave:

```
would change claude-haiku-5-5: new, input 0.1, output 0.5, cache_read 0.01, cache_creation_5m 0.125, cache_creation_1h 0.2
would change claude-sonnet-5-5: cache_read 0.2 -> 0.1 from 2026-10-13
```

## Rulings

- **Haiku 5.5 is taken.** LiteLLM's $0.10 / $0.50 matches Anthropic's published price for
  prompts up to 100K tokens. The derived cache figures follow the standard ratios
  (read 0.1×, 5m write 1.25×, 1h write 2× of input). First entry at `0000-01-01`, like
  every model's first entry.
- **Sonnet 5.5 is held.** Anthropic's published cache-read rate for Sonnet 5.5 is $0.20
  (the same as Sonnet 5), so LiteLLM's 0.1 is 5% of input where every other current model
  is 10%. An appended entry is never taken back, so a wrong upstream figure written today
  would mis-price every Sonnet 5.5 session from today onwards, in every consuming repo.
  The cost of holding it is one `WARN` per capture until LiteLLM changes.
- **`--only` rather than a hand-written entry.** The Haiku entry is the exact one a full
  refresh would append (`source: "litellm"`, the same rounding), and the next time
  LiteLLM carries a bad figure the same flag handles it with no hand edit to the history.
  It is write-mode only: `--check` already writes nothing, so a filter there would only
  hide news.
- **A new exit code rather than parsing output.** `feature-capture.sh` branches on
  `refresh_rates.py --check`'s exit status already (`RATES_CHANGED_RC`). A model the
  history lacks is priced live from the same list a refresh would append from
  (`live-model-rates`), so every figure is right and only the record is behind. That
  merits a `note`, not a `WARN`. `NEW_ONLY_EXIT` = 4: 2 is argparse's and 3 is
  `FETCH_FAILED_EXIT`. A mixed diff is `CHANGES_EXIT`: one moved price is enough to warn.
- **The `WARN` now says to check the pricing page first.** That was the missing step that
  would have led to the Sonnet figure being appended blindly.

## Round 2 — the round ends on a clean tree

Round 1 came back clean, and the coordinator paused before the close because the close
opens a PR. The cloud environment's stop hook flags any uncommitted file at the end of a
turn, and the review runner had left its `plan_end`/`pass_end` stamps uncommitted on
purpose: the stamp names the pass commit's sha, so it cannot ride that commit, and the
close committed it later as `S: PR`. Locally the same pause exists but nothing checks it.
`run-batch.sh` closes straight after a clean review, so it never shows.

Rulings:

- **`run-review.sh` commits the stamps itself, as `S: review stamps`, staging
  `timing.jsonl` alone.** It uses the same guards as the pass commit: no commit on the base
  branch or a detached HEAD, and advisory, so a git failure leaves the file for the close's
  existing `S: PR` fallback. It also runs on escalated and budget-capped-after-report
  rounds, so every recorded verdict ends on a clean tree.
- **`feature-close.sh` accepts the subject only when the commit touches the feature's
  `timing.jsonl` and nothing else.** On the subject alone, any unreviewed change written
  under it would pass. `S: PR` and `S: cost records` are admitted on subject alone as
  before; tightening those was out of scope.
- **`stray_labels` moves above the head check** in `feature-close.sh`, so `FEATURE_REL`
  is set when the stamps commit is checked. It is idempotent, so the stray check below
  reads the same labels.
- **Closing right after a clean review is now a written rule.** The owner said a clean
  review should end in a PR without being asked. That goes in `LIFECYCLE.md` step 5 and
  in `CONVENTIONS.md` → "Closing a feature", which every consuming repo imports, so a
  cloud coordinator no longer waits for permission at that step.

## Verification

- `bash self/tests/rates-history.sh`: all pass, including the new H10 (`--only`) and H11
  (new-only vs changed).
- `./self/gate.sh`: all checks passed (feature-lifecycle C3a2 still sees the `WARN`: its
  fixture has moved prices).
- Live, after the refresh: `refresh_rates.py --check` names only Sonnet 5.5 and exits 1.
