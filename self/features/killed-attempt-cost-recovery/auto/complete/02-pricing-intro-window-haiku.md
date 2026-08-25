# 02 — the intro tier needs a start date

Feature: a killed attempt's cost is recoverable from its session transcript, and
`pricing.py`'s intro tier must not apply to dates before the promotion began.

Plan 2 of 6 build plans. Small and surgical: one file, one predicate, one table entry, plus
the comment and README lines that describe them.

## The defect

`analysis/pricing.py:86` reads:

```python
    intro = entry.get("intro")
    if intro is not None and as_of <= intro["expires"]:
```

A one-sided window. `claude-sonnet-5` carries `intro: {"input": 2, "output": 10, "expires":
"2026-08-31"}` (`pricing.py:42`), so every date at or before 2026-08-31 gets the discount —
including dates before the promotion existed. The comment at `pricing.py:29-31` describes
this as intended ("on or before that date the intro rate applies"), so the comment is part of
the defect and must change with the code.

## The evidence for the start date

Measured over all 259 `claude-sonnet-5` runs in the consuming repo's corpus, pricing each
run's own `model_usage` tokens with `compute_cost` and comparing to the CLI's recorded
`costUSD`, grouped by run date: 2026-07-30 through 2026-08-21 all sit at a ratio of exactly
**1.500**, and 2026-08-22 sits at **1.000**. 1.5 is the standard/intro ratio. The promotion
began on 2026-08-22.

**This is inferred from billing behaviour, not read off a price list.** Say so in the table.

## Changes

1. `intro` gains a required `starts` key alongside `expires`. Update the comment at
   `pricing.py:29-31` to describe a two-sided, inclusive window.
2. The predicate becomes a both-ends test:

```python
    intro = entry.get("intro")
    if intro is not None and intro["starts"] <= as_of <= intro["expires"]:
```

3. `claude-sonnet-5`'s intro entry gains `"starts": "2026-08-22"`, with a comment on the
   line recording that the date was derived from observed billing ratios in this repo's
   usage corpus and is pending confirmation against Anthropic's published rates.
4. Bump `RATES_VERIFIED` to today's date and leave a note, in the same place the constant is
   defined, that the sonnet `starts` value is the one entry not confirmed from a published
   table.
5. If any other model in `RATES` carries an `intro` block, give it a `starts` too. Do **not**
   invent a date for it: use its `expires` value's own promotion start if the table records
   one, and otherwise set `starts` equal to a date that reproduces current behaviour for that
   model and flag it in the same comment. Never leave `starts` absent — the predicate must
   not have to cope with a missing key.

## Guard rails

- `get_rates`' docstring (`pricing.py:70-76`) already promises that `as_of` selects the tier
  and never the caller's wall clock. That promise is unchanged and still correct; do not
  reword it.
- Do not re-price anything. No `planning.json` is touched by this plan. Correcting the frozen
  figures is deliberately excluded from this batch — see the manifest.
- Do not change `CACHE_READ_MULTIPLIER`, `CACHE_WRITE_5M_MULTIPLIER` or
  `CACHE_WRITE_1H_MULTIPLIER`. The 1.500 ratio is explained entirely by the input/output base
  rates; the multipliers are already correct and assertion 7 of plan 01 depends on them.

## Done when

Assertions 1-3 of `self/tests/cost-recovery.sh` pass. Assertions 4-12 still fail — plan 03
owns those.

Update `analysis/README.md`'s `pricing.py` entry: its exposed-names list must show `RATES`
carrying `intro{input, output, starts, expires}` rather than `intro{input, output, expires}`.
