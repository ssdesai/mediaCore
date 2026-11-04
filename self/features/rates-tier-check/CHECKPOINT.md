# Checkpoint: rates-tier-check

status: committed
updated: 2026-09-27T01:21:59Z
gate: === gate: done — all checks passed === (shellcheck skipped: not installed)

## Slices
- [x] acceptance tests — self/tests/rates-history.sh T1–T8b, feature-lifecycle.sh C3a3;
      fixture gains claude-sonnet-4-5 with LiteLLM's above-200k fields (committed eff18bf)
- [x] 1. refresh_rates.py `--tiers` (rates-history.sh all green)
- [x] 2. feature-capture.sh residue: one `tiers` line (C3a3 green)
- [x] 3. real-corpus run; finding in NOTES.md (no used model carries a tier)
- [x] 4. self/BACKLOG.md entry rewritten: parked until the report flips
- [x] 5. manifest prose
- [x] READMEs: analysis/, self/tests/, self/tests/fixtures/, root README, LIFECYCLE.md
- [x] gate green, commit

## Learned
- refresh_rates.py keeps no cached copy of LiteLLM's JSON; offline needs `--source <file>`.
- self/gate-report.txt truncates long suites' output (feature-lifecycle's C lines are
  absent from it); run the suite by hand to see a specific assertion.

## Resume
- Nothing to resume: the review pass is next (`./run-review.sh --self rates-tier-check`).
