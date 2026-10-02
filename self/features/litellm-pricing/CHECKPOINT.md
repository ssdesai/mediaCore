# Checkpoint: litellm-pricing

status: committed
updated: 2026-09-23T16:23:48Z
gate: === gate: done — all checks passed ===

## Slices
- [x] acceptance tests — self/tests/rates-history.sh (26 red at commit, all green now), fixtures/pricing/{rates-main-2026-09-22,litellm-sample}.json, cost-recovery.sh 1-3/7 and feature-lifecycle.sh C3a2/C4 adapted, gate wiring
- [x] 1. analysis/rates_history.json seeded from the old table (clean decimals, two sonnet-5 entries)
- [x] 2. pricing.py reads the history (get_rates by `from`, RatesApplied gains from/source, tier "standard")
- [x] 3. analysis/refresh_rates.py (--source, --check, --history, rounding, dated/undated rule)
- [x] 4. callers: capture_planning rates_source + warning, report.py footer, feature-capture.sh rates line via refresh_rates.py --check (RATES_CHECK_SOURCE seam)
- [x] 5. every other test sandbox copying pricing.py copies rates_history.json; timestamps-are-utc 7b asserts `from`
- [x] 6. BACKLOG entry for long-context pricing
- [x] READMEs: analysis/, self/tests/, self/tests/fixtures/, top-level README.md, LIFECYCLE.md residue line

## Learned
- Real LiteLLM (fetched once to scratch, not committed) matches every seeded rate; its only diff is a new claude-mythos-preview.
- The parity fixture was generated from main's pricing.py before any change; never regenerate it.

## Resume
- Nothing to resume: committed. Next is the review pass (`./run-review.sh --self litellm-pricing`).
