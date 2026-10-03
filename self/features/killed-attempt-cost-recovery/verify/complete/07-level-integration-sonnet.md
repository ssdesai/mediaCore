# 07 — level 2 verify: integration

Feature: a killed attempt's cost is recoverable from its session transcript, and
`pricing.py`'s intro tier must not apply to dates before the promotion began.

Tier 1 of level 2's ladder. Read `self/gate-report.07.txt` first.

Level 2 owns `analysis/report.py`, `self/gate.sh`, `analysis/README.md`,
`self/tests/README.md`, and the retractions in `plan-runner-lib.sh` / `AGENT_PLANS.md`.

Priorities, in order:

1. **Backward compatibility is the risk here.** Every `usage.json` and `report.json` in both
   corpora predates this batch. `python3 analysis/report.py --all` and
   `python3 analysis/report.py --self --all` must both run clean against them. If either
   raises a `KeyError`, the fix is a `.get(..., default)`, never a migration of committed
   artifacts.
2. **The three-bucket rule is actually three buckets.** Read `compute_cost_rollup` and
   confirm measured / recovered / unrecoverable are genuinely distinguished, and that only
   the third sets `total_is_partial`. A recovered attempt that still marks a total partial
   means plan 05 half-landed.
3. **No dollar figure is recomputed in `report.py`.** Its module docstring at `report.py:9`
   forbids it and plan 05 repeats why. If you find `compute_cost` imported into `report.py`,
   that is the bug.
4. **The retraction is complete.** Grep both corpora for "unrecoverable" and confirm every
   surviving use is the aged-out-transcript case, not the old blanket claim.
5. `bash self/gate.sh` green end to end.
