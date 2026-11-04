# 08 — batch verify

Feature: a killed attempt's cost is recoverable from its session transcript, and
`pricing.py`'s intro tier must not apply to dates before the promotion began.

Both levels are green. Read `self/gate-report.txt` first; do not re-run what it reports.

This pass is about the batch as a whole rather than any one level:

1. **Prove the headline claim end to end on real data.** The consuming repo has a real killed
   attempt: `plans/features/entry-delete-and-gate-parity/auto/complete/11-tests-real-stack-parity-sonnet.usage.json`
   carries two attempts, the first `{outcome: "killed", total_cost_usd: null}` with session
   `ba053b6a-2fe5-412c-8e9a-1f9198384e55`, the second `{outcome: "complete",
   total_cost_usd: 2.8982592}` with session `fdc02b3a-b94a-4344-8e3e-2c7bf7b41e5d`.
   Run the *same* derivation over the **successful** session's transcript and confirm it
   reproduces the CLI's own recorded `costUSD` for that model to within 0.5%. That is the
   validation that makes the recovered figure credible rather than plausible: the method is
   checked against a cost we already know. Record the two numbers in your report.
   Do not modify that sidecar — the consuming repo's corpus is not this batch's to edit.
2. **The rate-table inference is labelled as such.** `pricing.py`'s sonnet `starts` date was
   derived from billing ratios, not read from a published table. Confirm the file says so
   and that `RATES_VERIFIED`'s note names it as the unconfirmed entry. An inferred date
   presented as verified is the one thing in this batch that could quietly produce wrong
   numbers for years.
3. **Idempotence on the real corpus.** Run `recover_attempts.py` twice against the consuming
   repo and confirm the second run reports zero newly recovered and leaves no diff.
   Then `git checkout --` any sidecar it touched: this batch ships the tool, not a
   corpus-wide backfill, which the manifest excludes deliberately.
4. Full gate green in both modes.
