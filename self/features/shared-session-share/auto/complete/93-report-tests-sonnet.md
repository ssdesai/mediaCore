# 93 — tests: the report side of a shared session

feature: agentTooling/shared-session-share — plan 5 of 6. A session claimed by more than
one feature is priced by concurrent share; level 1 computes the share, and this plan is
the test for what `report.py` does with it. **RED until plan 94 lands.**

Depends on: `91-share-pricing-sonnet.md` — the `planning.json` fields asserted below are
written by it. Independent of plans 89 and 90.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- `self/tests/claims-ledger.sh` part B already stands up the exact fixture this needs —
  one session, two manifests pinning it, both captured, then `report_for two`. Read
  `self/tests/claims-ledger.sh:216-250` before writing; extend it rather than building a
  second world.
- Its `manifest` helper writes a fence with **no `session_window`**, so both claims are
  unbounded and the split is an even one over the whole transcript. That is the simplest
  shared case and the right one for the report assertions; the arithmetic lives in
  `self/tests/session-share.sh`.
- `jf FILE EXPR` is that file's JSON reader; `report_for SLUG` writes
  `self/features/<slug>/report.{json,md}`.
- `cost.shared_sessions[]` is produced by `report.py`'s `compute_shared_sessions`, and
  the footnote by the block reading `cost.get("shared_sessions")` under the Cost table.

## Files

- Modify `self/tests/claims-ledger.sh`
- Modify `self/tests/README.md`

## `self/tests/claims-ledger.sh`

Rewrite part B's report assertions and add the ones the share needs. Keep B1–B8 exactly
as they are: they are about the ledger's arity and the annotation, and neither moves.

- **B9** — the key set of `cost.shared_sessions[0]` is now
  `['also_claimed_by', 'cost_usd', 'session_cost_usd', 'session_id']`. Update the
  expected list and the label.
- **B10** — unchanged in intent; keep it.
- **B11** — the footnote still names the session and the other feature. Keep the two
  greps and add a third: the line must **not** claim the session is counted in full. Grep
  for the absence of `in full`, and say in the label why — that sentence was the whole
  disclosure before the split existed, and leaving it beside a divided figure would
  describe the opposite of what happened.
- **B12** (new) — `cost.shared_sessions[0].cost_usd` is this feature's **share**, and
  `session_cost_usd` the undivided session: assert `cost_usd` is within `1e-9` of half
  `session_cost_usd`, two claimants splitting an unbounded window evenly.
- **B13** (new) — the two features' shares sum to the session's own cost. Run
  `report_for one` as well and assert
  `one.cost.shared_sessions[0].cost_usd + two.…cost_usd == session_cost_usd` within
  `1e-9`. This is the report-side statement of the invariant
  `self/tests/session-share.sh` phase 1 asserts on the records themselves, and it is what
  catches a footnote that renders one figure while the table sums another. `report_for
  one` needs `one`'s record to be a *shared* one — re-capture it with `--recapture`
  first, since B7 only annotated it.
- **B14** (new) — a `planning.json` frozen **before** the share rule still reports the old
  way and says so. Strip `share_basis`, `session_cost_usd` and `session_duration_s` from
  `two`'s record with a `python3 -c` edit, re-run `report_for two`, and assert
  `cost.shared_sessions[0]` carries no `session_cost_usd` and that the footnote says the
  figure is counted in full there. Every consuming repo's corpus is full of such records
  and they must not be rendered as shares they are not.

## `self/tests/README.md`

Update the `claims-ledger.sh` entry's **B** paragraph: it currently says the second
capture's session "is priced in full by both" and that the footnote names the sharing.
Rewrite that half to the new behaviour — the second capture is still not refused, the
ledger still holds a list, and the money is now split evenly between the two unbounded
claims, with `session_cost_usd` beside the share and the two shares summing to the
session — and add one line for B14, the legacy record that carries no share and is
reported the old way. Leave A, C and D as they are.
