# Backlog

Escalations and decisions left open by finished features — one entry per item, phrased as
the assertion that would catch it, with the feature that raised it. Remove an entry in the
feature that closes it. Same shape as a consuming repo's `plans/BACKLOG.md`; this one is
agentTooling's own, for the harness rather than for a product.

- **A plan's minutes come from the attempts that reported one, and nothing says which
  attempts did not.** `report.py`'s `duration_from_usage` sums the live sidecar's
  `attempts[].duration_ms` and stops there, so a resumed plan whose first attempt was
  killed and whose second completed reports only the second's minutes, is in neither
  `time.missing_duration_plans[]` nor `time.recovered_duration_plans[]`, and marks no
  row — the total reads as whole when it is short by however long the killed attempt
  ran. The dollars do not have this hole: `compute_cost_rollup` walks the attempts
  individually and reads prior sidecars too, taking each session's figure from the first
  copy that has one (`ATTEMPT_FIGURE_FIELDS`, live before prior). Closing it means giving
  the time roll-up the same per-attempt, prior-aware walk — a recovered span for the
  killed attempt beside the measured figure for the completed one, which then has to
  decide what a cell holding both a wall clock and a transcript span means and how it is
  marked. `recovered-duration-lower-bound` deliberately did not: it credits a recovered
  span only where the plan has no measured duration at all, on the ground that blending
  the two inside one cell produces a figure that is neither, and the mixed case is rarer
  than the wholly-unmeasured one it was built for. Assertion: a plan with one measured
  attempt and one attempt whose duration was recovered reports both, and its bucket says
  which part of the figure is a lower bound.
  Raised by `recovered-duration-lower-bound`.
