# Backlog

Escalations and decisions left open by finished features — one entry per item, phrased as
the assertion that would catch it, with the feature that raised it. Remove an entry in the
feature that closes it. Same shape as a consuming repo's `plans/BACKLOG.md`; this one is
agentTooling's own, for the harness rather than for a product.

- **A plan with a null `duration_ms` contributes nothing to its bucket's minutes, and
  nobody derives the lower bound its transcript could give.** `recover_attempts.py`
  prices a killed or resultless attempt from `~/.claude/projects/<…>/<session_id>.jsonl`,
  and `report.py`'s Time table now marks such a bucket and names the plan
  (`time.missing_duration_plans[]`, `† review: no duration for <stem> — <reason>`), so
  the minutes at least say why they are missing. What nobody derives is a number: the
  transcript's first and last instants bound the run, and `iter_billable_messages` walks
  every one of those lines already. It was excluded from
  `tooling-backlog-2026-09-06` deliberately and on the merits — a transcript span is not
  the executor's wall clock (it includes the model's own waiting and excludes whatever
  the runner did around the call), `recover_attempts.py` does not read timestamps today
  and would have to carry them into the sidecar beside `recovered_cost_usd`, and a
  derived figure sitting in the same column as a measured one needs a way to say which
  it is. That is a design, not an edit. Assertion: an attempt with a null `duration_ms`
  whose transcript survives carries a `recovered_duration_s` derived from that
  transcript's first and last instants, the Time table renders it as a lower bound
  visibly distinct from a measured figure, and an attempt whose transcript is gone still
  renders as it does today.
  Raised by `tooling-backlog-2026-09-06`.
