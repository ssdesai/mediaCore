# Review — recovered-totals-stay-honest

**What the batch was supposed to do.** Close the two escalations from
`killed-attempt-cost-recovery`'s review, both of one class: *a total that reads complete and is
low.* (1) `recover_attempts.py` dropped an unpriced model's tokens into a silent 0 and
`report.py` filed the attempt under *recovered*; (2) `report.py` read a plan's recovered dollars
from the sidecar's top-level `recovered_cost_usd`, the one key `write_usage_sidecar` rebuilds
away on a resumed plan's next write.

**Does it?** Yes, both. The gate is green on arrival (assertions 13a–14d pass), and the parts a
green gate does not prove check out:

- **The chain closes.** `recovered_is_partial` is written (`recover_attempts.py:106-108`), read
  (`report.py:314-319`), bucketed into `cost.partially_recovered_attempts[]`, folded into
  `total_is_partial` (`report.py:371`), and rendered (`report.py:787-800`). The render block sits
  inside `if cost.get("total_is_partial")`, and a partial attempt always sets that flag, so it is
  reachable rather than dead. `recover_attempts.py` also prints it, so it is not discoverable only
  by opening JSON.
- **Assertion 13 can fail.** `normalize_model_id` strips only an 8-digit date suffix, so
  `claude-not-a-real-model-9` stays absent from `RATES` and `get_rates` returns `None`. 13c (the
  mixed transcript still recovers the priced model's dollars) keeps 13a-13d from passing
  vacuously under a "refuse the whole attempt" implementation.
- **Assertion 14's fixture is faithful.** Checked against `plan-runner-lib.sh:539-581` rather than
  the fixture's own comment: the 16 top-level keys the `p14a` sidecar carries are exactly the ones
  the jq rebuild emits, and `recovered_cost_usd` is correctly not among them. 14c is meaningful —
  `total_is_partial: false` there requires the manifest and `planning.json` fixtures to be
  otherwise clean, and they are.
- **The sweep for a third instance** turned up one (escalation 3). The other `get(…, 0)` sites in
  `analysis/` — `transcript.py:56-61`, `backfill_usage.py:140-145`, `compute_cold_start_tax` — are
  token counts genuinely absent from a usage block, not unpriced-model coercions, and
  `report.py:346`'s `(cost or 0.0)` is guarded by the branch above it.

## Fixed in this pass

- `analysis/README.md` — the `recover_attempts.py` entry still listed only the five original
  recovered fields. Added `unpriced_models[]` / `recovered_is_partial` and the `partial (…)`
  summary heading, and noted that the top-level sum is rewritten only on a run that recovered
  something, which is why `--force` is what repairs a drifted top-level figure.
- `analysis/README.md` — named the cross-layer invariant the fix rests on (README Rule 2): the
  attempt-level fields survive `write_usage_sidecar` only because it merges `attempts[]` by
  `session_id` and a resumed attempt gets a fresh id. An entry whose id *matches* is replaced by
  the rebuilt five-key attempt, recovered fields included.
- `analysis/report.py:287-292` — the disagreement warning named both figures and said which won
  but not what to do. It now points at `recover_attempts.py --force` and says why a plain re-run
  does not repair it.
- `self/tests/README.md`, `self/tests/cost-recovery.sh:53-56` — both still said assertions 13-14
  are "RED until plan 02 lands". Plan 02 landed in this batch and the gate shows them green.

## Escalated to the next batch

**1. A top-level/`attempts[]` disagreement warns but leaves the total looking whole.**
`analysis/report.py:284-292` appends a warning and moves on; `total_is_partial`
(`report.py:366-373`) never hears about it. Every other "this number may be low" signal in the
roll-up sets that flag, for the reason the file's own comment at `report.py:357-359` gives — the
`--all` trend table shows totals without warnings. The two directions are not symmetric and the
fix should say so: when `top_level > plan_recovered`, dollars are missing from `attempts[]` and
the total is a lower bound; when `top_level < plan_recovered`, the top-level figure is merely
stale and the total is whole. Mark partial only in the first direction. Wanted: a
`recovered_disagreements[]` list in the rollup dict, fed into `total_is_partial`, exposed in
`report.json` (plus its README field list) and rendered in the lower-bound block.
**Missing assertion:** the `rpt14-mismatch` fixture already constructs exactly this case ($9.75
top-level vs $4.25 in attempts) and asserts only the warning text — one more
`report_field_equals … cost.total_is_partial true` on the same fixture buys the invariant.

**2. A recovered $0.00 is read as "not recovered".** `analysis/report.py:293` branches on
`not plan_recovered`, so a plan whose recovered sum is exactly zero takes the
`priced_without_cost` path and `continue`s before the bucket loop. This batch made that case
newly reachable: a transcript whose *every* model is unpriced recovers exactly `0.0` with
`recovered_is_partial: true`. Such a plan lands in neither `cost.partially_recovered_attempts[]`
nor `cost.unrecoverable_attempts[]`, and the new "Partially recovered attempts" section of
`report.md` stays silent about it. The total is still marked partial, so the number is not wrong —
but the reader is told "plan X has no total_cost_usd; excluded from cost roll-up", i.e. that
recovery has not run, when it ran and found no rates. Branch on whether any attempt carries a
`recovered_cost_usd` key rather than on the truthiness of the sum. **Missing assertion:** an
all-unpriced-model transcript appears in `cost.partially_recovered_attempts[]`.

**3. The third instance of the class, in the same file.** `analysis/report.py:434` —
`total_turns = sum((u.get("num_turns") or 0) for _, u, _ in members)`. `num_turns` is `null`
exactly when no attempt produced a result event (`plan-runner-lib.sh:559-563` says so: "`add` over
an empty array is null, which is the honest answer … and what report.py reads as 'unpriced'"), so
a killed attempt silently costs the model-fit table turns. The very next line propagates `None`
for the same input rather than coercing it. Not introduced by this batch — found by the sweep the
plan commissioned — and it is turns rather than dollars, but it is the same shape and it is one
line below code this batch touched. The fix is a decision: propagate `None` the way
`total_cost_usd` does, or carry a `total_turns_is_partial` flag; either way `report.json`'s
`model_fit` field list in `analysis/README.md` changes. The per-plan turn flags
(`HAIKU_HIGH_TURN_THRESHOLD` and friends) skip `None` already and are unaffected.

**4. Nothing asserts the invariant the whole fix rests on.** "A resumed attempt is a fresh
`claude -p` with a fresh session id" (`plan-runner-lib.sh:493-495`) is what makes `attempts[]` the
durable location. If a same-session rewrite ever became possible, `write_usage_sidecar`'s
`$seen` branch (`plan-runner-lib.sh:554-558`) would replace the matching entry with the rebuilt
five-key attempt and take `recovered_cost_usd` with it — defect 2 returns, silently, and the
cross-check in escalation 1 is the only thing that would notice. It is not reachable today
(`harvest_orphan_attempt` fires only for a session `attempts[]` has never seen), so this is a
guard, not a bug. **Missing assertion:** a runner-level test that a second `write_usage_sidecar`
call for a session already in `attempts[]` preserves that entry's `recovered_*` fields — this is
the cheap one to write, and it pins the contract the README now states.
