# 05 — review: review-base-and-cloud-hook, round 5

A re-review scoped to one backlog entry. "No findings" is a legitimate verdict.

## What round 5 was supposed to do

Record, not build: one new `self/BACKLOG.md` entry, decided by the human after round 4 —
**a recapture re-prices a record from the table instead of from the rates it already
recorded.** It must say that `planning.json` already stores `rates_applied` per model per
session; that `capture_planning.py --recapture` prices again from
`analysis/rates_history.json` (or the `litellm-live` fallback) instead; the proposal (the
record's own rates win for sessions it already priced, the table prices only new ones, an
explicit flag re-prices on purpose); why the table stays (pricing by session date across a
price change, shared-session halves summing, `manual` corrections in one place, no
network); an assertion; and who raised it.

## The diff

`git log --oneline -4` to find `review-base-and-cloud-hook: review round 4`, then
`git diff <that sha>..HEAD`. Expect `self/BACKLOG.md` and this feature's own records only.

## Contracts to hold it to

- The entry is in `self/BACKLOG.md`'s existing style: a bold one-line title, then the
  detail, an "Assertion:" phrased as the test that would catch it, then "Raised by …".
- Every factual claim in it is true of the code today: check that `planning.json` records
  carry `rates_applied` with `from` and `source` (`analysis/README.md`, `pricing.py`'s
  `RatesApplied`), and that the recapture path prices through `pricing.compute_cost` /
  `get_rates` rather than reading a prior record's rates (`analysis/capture_planning.py`).
  A claim that is wrong is a finding — fix the wording.
- No code, test or other doc changed in this round (`git diff --stat`).

## Verdict

Write `self/review-report.md`. Its FIRST line is exactly `Verdict: clean` or
`Verdict: escalated`. Fix wording in `self/BACKLOG.md` yourself and say what you changed.
