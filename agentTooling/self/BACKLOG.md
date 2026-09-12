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

- **A co-claimant still in flight is unbounded in this feature's split.** The share walk
  reads every other claimant's `session_window` as it stands, and a feature that has not
  closed yet carries `to: null` — so on a coordinator both features claim, the in-flight
  one takes an equal share of every response from its `from` to the end of the transcript,
  including the stretch after its own work stopped. `claim-window-precision` closed the
  same defect for the CAPTURING feature, by stamping its own `to` from the last instant of
  its branch-selected sessions, and deliberately did not close it for the others: bounding
  another feature's claim would mean walking that feature's transcripts from here, on
  every capture, to derive a bound its own close is about to derive anyway — and a figure
  derived here would then disagree with the one that feature freezes. Its own close bounds
  its own record, and re-capturing this feature afterwards picks the tightened bound up.
  Assertion: a feature captured while a co-claimant's `to` is still null, then re-captured
  after that co-claimant closes, reports a larger share the second time, and the first
  record says which of its claimants were still open.
  Raised by `claim-window-precision`.

- **A pinned delegate that cost nothing is listed as unclaimed forever.** The ledger's
  subagent side is written from the capture's priced entries (`add_session_claims` over
  `costs`), so a delegate whose transcript holds no billable response — a rework one-shot
  killed at spawn, two lines and 0.3 seconds — is captured into `planning.json`'s
  `subagents[]` as `selected_by: pinned`, and never reaches the ledger. `--list-subagents
  --unclaimed` reads the ledger, so every sweep prints the pin that is already there and
  tells the human to write it, which is the exact advice `manifest_pinned_subagents` was
  added to stop for `--for`. Seen on `humanNetworkMap/node-query-payload`'s
  `a3cb921a319b2c2ee` on 2026-09-10. Assertion: a manifest pinning a delegate whose
  transcript has no `assistant` line captures it, the ledger names the feature for that
  id with `cost_usd` 0, and `--list-subagents --unclaimed` does not list it.
  Raised by the 2026-09-10 delegate sweep.

- **The head's remedy has no tool.** The bounded opening stretch (`head_bound`) leaves the
  part of a session's head nobody planned in `unclaimed_usd`/`unclaimed_duration_s`, and
  the "unclaimed by any feature" warning names the two repairs that can reach it: pin the
  session into the feature the work belongs to, or move the earliest claimant's `from`
  back. The first has a tool (`sessions` in the manifest fence); the second does not —
  `analysis/manifest.py` has `set-window-to` and no `set-window-from`, so the warning ends
  by telling the reader to edit the fence by hand, which is the one thing every manifest
  and `LIFECYCLE.md` say not to do. `bounded-opening-stretch` deliberately did not build
  the twin: `set-window-to`'s value is that it refuses to WIDEN a bound already stamped
  from evidence, and the symmetric refusal for `from` is not the same rule — moving `from`
  back is a widening, which is exactly the operation being asked for, so the command would
  be a bare writer with no guard, and what stops a `from` from being moved to claim a head
  the feature did not plan is judgement, not arithmetic. Assertion: a `from` moved back to
  cover a disclosed head is applied by a command that shows the old and new bound and
  refuses to move it PAST the session's own first instant, and the unclaimed warning names
  that command instead of "by hand".
  Raised by `bounded-opening-stretch`.
