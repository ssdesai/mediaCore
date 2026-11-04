# 01 — review: rates-tier-check

## What the feature was supposed to do

Narrow the `self/BACKLOG.md` entry "Long-context (above 200k input tokens) and other
tiered pricing is not priced." per its 2026-09-26 ruling: `refresh_rates.py` gains a mode
that reports, for each model the corpus uses, whether its LiteLLM entry carries an
above-200k (or other tiered) rate and at what rates; `feature-capture.sh`'s residue prints
one summary line from it. Tiered pricing itself is **not** built here. The backlog entry is
rewritten with the real corpus finding: parked until the report flips, or now due.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Read
`self/features/rates-tier-check/NOTES.md` for the implementer's rulings, but judge
against this brief, not against the notes.

## Contracts to hold it to

- The tier suffixes LiteLLM uses are a named constant, and the report reads them from the
  same fetched or cached JSON `refresh_rates.py` already uses — no second fetch path.
- The report works offline in the test, against the existing fixture extended with one
  tiered and one flat model, and the summary line's wording is asserted.
- `analysis/rates_history.json` is byte-for-byte unchanged on this branch.
- The residue line is one line, in the existing residue block's style, and the existing
  "rates verified / would change" lines are untouched.
- NOTES.md records the real-corpus finding (which models, which carry a tier), and the
  rewritten backlog entry states the same finding, keeps its `Raised by` line and the
  ruling, and keeps the original assertion if tiered pricing is now due.
- `analysis/README.md` documents the flag and the constant; the gate is green; READMEs of
  every touched folder are current.

Fix local findings in the pass; escalate structural ones. "No findings" is a legitimate
verdict.

## Verdict

First line of `self/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
